package com.example.mobile_wallet_demo.rutoken

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_CLASS
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_EC_PARAMS
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_EC_POINT
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_KEY_TYPE
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_PRIVATE
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_TOKEN
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11MechanismType.CKM_ECDSA
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11ObjectClass.CKO_PRIVATE_KEY
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11ObjectClass.CKO_PUBLIC_KEY
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11UserType.CKU_USER
import ru.rutoken.pkcs11wrapper.datatype.Pkcs11InitializeArgs
import ru.rutoken.pkcs11wrapper.main.Pkcs11Session
import ru.rutoken.pkcs11wrapper.mechanism.Pkcs11Mechanism
import ru.rutoken.pkcs11wrapper.mechanism.parameter.CkVendorBip32DeriveParams
import ru.rutoken.pkcs11wrapper.`object`.key.Pkcs11PrivateKeyObject
import ru.rutoken.pkcs11wrapper.`object`.key.Pkcs11PublicKeyObject
import ru.rutoken.pkcs11wrapper.rutoken.constant.RtPkcs11AttributeType.CKA_VENDOR_BIP32_CHAINCODE
import ru.rutoken.pkcs11wrapper.rutoken.constant.RtPkcs11KeyType.CKK_VENDOR_BIP32
import ru.rutoken.pkcs11wrapper.rutoken.constant.RtPkcs11MechanismType.CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE
import ru.rutoken.pkcs11wrapper.rutoken.constant.RtPkcs11MechanismType.CKM_VENDOR_BIP32_DERIVE_PUBLIC_FROM_PRIVATE
import ru.rutoken.pkcs11wrapper.rutoken.main.RtPkcs11Session
import ru.rutoken.pkcs11wrapper.rutoken.main.RtPkcs11Token
import ru.rutoken.rtpcscbridge.RtPcscBridge
import ru.rutoken.rttransport.InitParameters
import ru.rutoken.rttransport.TokenInterface

/**
 * Serializes every PKCS#11 call on one thread and binds module lifetime to the
 * foreground Activity. The runtime owns all login/session guards; Dart only
 * receives opaque UUIDs.
 */
internal class RutokenRuntime private constructor(application: Application) : DefaultLifecycleObserver {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "wallet-demo-rutoken").apply { isDaemon = true }
    }
    private val module = WtPkcs11Module()
    private val sessions = linkedMapOf<String, OpenSession>()
    private var initialized = false

    init {
        RtPcscBridge.setAppContext(application)
        RtPcscBridge.getTransportExtension().attachToLifecycle(
            application,
            true,
            InitParameters.Builder()
                .setEnabledTokenInterfaces(TokenInterface.NFC)
                .build(),
        )
    }

    override fun onStart(owner: LifecycleOwner) {
        executor.execute { initializeIfNeeded() }
    }

    override fun onStop(owner: LifecycleOwner) {
        executor.execute { finalizeModule() }
    }

    fun <T> submit(block: RutokenRuntime.() -> T, callback: (Result<T>) -> Unit) {
        executor.execute {
            callback(runCatching {
                initializeIfNeeded()
                block()
            })
        }
    }

    fun openSession(pin: String): Map<String, Any> {
        require(pin.isNotEmpty()) { "Rutoken PIN must not be empty." }
        val token = awaitSingleToken()
        val session = token.openSession(true)
        try {
            val login = session.login(CKU_USER, pin)
            val id = UUID.randomUUID().toString()
            sessions[id] = OpenSession(session, login)
            val info = token.tokenInfo
            return mapOf(
                "sessionId" to id,
                "tokenLabel" to info.label.trim(),
                "tokenModel" to info.model.trim(),
                "tokenSerial" to info.serialNumber.trim(),
            )
        } catch (error: Throwable) {
            session.close()
            throw error
        }
    }

    fun readPublicMaterial(sessionId: String): Map<String, ByteArray> {
        val open = requireSession(sessionId)
        val master = findSingleMasterKey(open.session)
        val masterPublic = derivePublic(open.session, master, longArrayOf())
        val parentPublic = derivePublic(open.session, master, path(44u, 60u))
        val accountPublic = derivePublic(open.session, master, path(44u, 60u, 0u))
        val addressPublic = derivePublic(open.session, master, path(44u, 60u, 0u, 0u, 0u))
        try {
            return mapOf(
                "masterPublicKey" to ecPoint(open.session, masterPublic),
                "parentPublicKey" to ecPoint(open.session, parentPublic),
                "accountPublicKey" to ecPoint(open.session, accountPublic),
                "addressPublicKey" to ecPoint(open.session, addressPublic),
                "accountChainCode" to accountPublic
                    .getByteArrayAttributeValue(open.session, CKA_VENDOR_BIP32_CHAINCODE)
                    .byteArrayValue,
            )
        } finally {
            listOf(masterPublic, parentPublic, accountPublic, addressPublic).forEach {
                open.session.objectManager.destroyObject(it)
            }
        }
    }

    fun signDigest(sessionId: String, derivationPath: LongArray, digest: ByteArray): ByteArray {
        require(digest.size == 32) { "CKM_ECDSA input must be a 32-byte EVM digest." }
        val open = requireSession(sessionId)
        val master = findSingleMasterKey(open.session)
        val derived = derivePrivate(open.session, master, derivationPath)
        try {
            return open.session.signManager.signAtOnce(
                digest,
                Pkcs11Mechanism.make(CKM_ECDSA),
                derived,
            )
        } finally {
            open.session.objectManager.destroyObject(derived)
        }
    }

    fun closeSession(sessionId: String) {
        sessions.remove(sessionId)?.close()
    }

    private fun initializeIfNeeded() {
        if (initialized) return
        module.initializeModule(Pkcs11InitializeArgs.Builder().setOsLockingOk(true).build())
        initialized = true
    }

    private fun finalizeModule() {
        sessions.values.toList().forEach { runCatching { it.close() } }
        sessions.clear()
        if (initialized) {
            runCatching { module.finalizeModule() }
            initialized = false
        }
    }

    private fun awaitSingleToken(): RtPkcs11Token {
        val deadline = System.nanoTime() + TOKEN_WAIT_NANOS
        while (true) {
            val tokens = module.getSlotList(true).map { it.token as RtPkcs11Token }
            if (tokens.size == 1) return tokens.single()
            if (tokens.size > 1) error("More than one Rutoken is connected; leave exactly one token in NFC range.")
            if (System.nanoTime() >= deadline) error("Rutoken was not detected over NFC within 30 seconds.")
            Thread.sleep(TOKEN_POLL_MILLIS)
        }
    }

    private fun requireSession(id: String): OpenSession =
        sessions[id] ?: error("Rutoken session is closed or unknown.")

    private fun findSingleMasterKey(session: RtPkcs11Session): Pkcs11PrivateKeyObject {
        val template = listOf(
            session.attributeFactory.makeAttribute(CKA_CLASS, CKO_PRIVATE_KEY),
            session.attributeFactory.makeAttribute(CKA_PRIVATE, true),
            session.attributeFactory.makeAttribute(CKA_KEY_TYPE, CKK_VENDOR_BIP32),
        )
        val keys = session.objectManager.findObjectsAtOnce(Pkcs11PrivateKeyObject::class.java, template)
        check(keys.size == 1) {
            "Expected exactly one BIP32 master private key on Rutoken, found ${keys.size}."
        }
        return keys.single()
    }

    private fun derivePublic(
        session: RtPkcs11Session,
        master: Pkcs11PrivateKeyObject,
        path: LongArray,
    ): Pkcs11PublicKeyObject {
        val template = listOf(
            session.attributeFactory.makeAttribute(CKA_CLASS, CKO_PUBLIC_KEY),
            session.attributeFactory.makeAttribute(CKA_PRIVATE, false),
            session.attributeFactory.makeAttribute(CKA_TOKEN, false),
            session.attributeFactory.makeAttribute(CKA_KEY_TYPE, CKK_VENDOR_BIP32),
            session.attributeFactory.makeAttribute(CKA_EC_PARAMS, SECP256K1_OID),
        )
        return session.keyManager.deriveKey(
            Pkcs11PublicKeyObject::class.java,
            Pkcs11Mechanism.make(
                CKM_VENDOR_BIP32_DERIVE_PUBLIC_FROM_PRIVATE,
                CkVendorBip32DeriveParams(path),
            ),
            master,
            template,
        )
    }

    private fun derivePrivate(
        session: RtPkcs11Session,
        master: Pkcs11PrivateKeyObject,
        path: LongArray,
    ): Pkcs11PrivateKeyObject {
        val template = listOf(
            session.attributeFactory.makeAttribute(CKA_CLASS, CKO_PRIVATE_KEY),
            session.attributeFactory.makeAttribute(CKA_PRIVATE, true),
            // Session-only: a signing child must never persist on the token.
            session.attributeFactory.makeAttribute(CKA_TOKEN, false),
            session.attributeFactory.makeAttribute(CKA_KEY_TYPE, CKK_VENDOR_BIP32),
            session.attributeFactory.makeAttribute(CKA_EC_PARAMS, SECP256K1_OID),
        )
        return session.keyManager.deriveKey(
            Pkcs11PrivateKeyObject::class.java,
            Pkcs11Mechanism.make(
                CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE,
                CkVendorBip32DeriveParams(path),
            ),
            master,
            template,
        )
    }

    private fun ecPoint(session: Pkcs11Session, key: Pkcs11PublicKeyObject): ByteArray =
        key.getByteArrayAttributeValue(session, CKA_EC_POINT).byteArrayValue

    private fun path(vararg indices: UInt): LongArray =
        indices.map { (it.toLong() or HARDENED) }.toLongArray()

    private data class OpenSession(
        val session: RtPkcs11Session,
        val login: Pkcs11Session.LoginGuard,
    ) {
        fun close() {
            try {
                login.close()
            } finally {
                session.close()
            }
        }
    }

    companion object {
        private const val TOKEN_POLL_MILLIS = 200L
        private const val TOKEN_WAIT_NANOS = 30_000_000_000L
        private const val HARDENED = 0x80000000L
        private val SECP256K1_OID = byteArrayOf(0x06, 0x05, 0x2B, 0x81.toByte(), 0x04, 0x00, 0x0A)

        @Volatile private var instance: RutokenRuntime? = null

        fun get(application: Application): RutokenRuntime =
            instance ?: synchronized(this) {
                instance ?: RutokenRuntime(application).also { instance = it }
            }
    }
}
