package com.example.mobile_wallet_demo.rutoken

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

/**
 * Serializes every PKCS#11 call on one thread and binds module lifetime to the
 * foreground Activity. The runtime owns all login/session guards; Dart only
 * receives opaque UUIDs.
 */
internal class RutokenRuntime private constructor() : DefaultLifecycleObserver {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "wallet-demo-rutoken").apply { isDaemon = true }
    }
    private val slotEventExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "wallet-demo-rutoken-slots").apply { isDaemon = true }
    }
    private val module = WtPkcs11Module()
    private val sessions = linkedMapOf<String, OpenSession>()
    private val tokenMonitor = Object()
    private var presentTokens = emptyMap<Long, RtPkcs11Token>()
    private var slotEventGeneration = 0L
    private var initialized = false

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
        // The vendor wrapper represents the empty/master derivation path as a
        // null pointer. A non-null LongArray(0) reaches JNA as a zero-byte
        // allocation and fails before PKCS#11 with "allocation size must be
        // greater than zero".
        val masterPublic = derivePublic(open.session, master, null)
        val parentPublic = derivePublic(
            open.session,
            master,
            longArrayOf(hardened(44), hardened(60)),
        )
        val accountPublic = derivePublic(
            open.session,
            master,
            longArrayOf(hardened(44), hardened(60), hardened(0)),
        )
        val addressPublic = derivePublic(
            open.session,
            master,
            longArrayOf(hardened(44), hardened(60), hardened(0), 0, 0),
        )
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
        startSlotEvents()
    }

    private fun finalizeModule() {
        stopSlotEvents()
        sessions.values.toList().forEach { runCatching { it.close() } }
        sessions.clear()
        if (initialized) {
            runCatching { module.finalizeModule() }
            initialized = false
        }
    }

    private fun awaitSingleToken(): RtPkcs11Token {
        val deadline = System.nanoTime() + TOKEN_WAIT_NANOS
        synchronized(tokenMonitor) {
            while (true) {
                if (presentTokens.size == 1) return presentTokens.values.single()
                if (presentTokens.size > 1) {
                    error("More than one Rutoken is connected; leave exactly one token in NFC range.")
                }

                val remaining = deadline - System.nanoTime()
                if (remaining <= 0) error("Rutoken was not detected over NFC within 30 seconds.")
                val waitMillis = remaining / NANOS_PER_MILLISECOND
                val waitNanos = (remaining % NANOS_PER_MILLISECOND).toInt()
                tokenMonitor.wait(waitMillis, waitNanos)
            }
        }
    }

    /**
     * The Android PC/SC bridge publishes NFC insertion/removal through
     * C_WaitForSlotEvent. Repeated C_GetSlotList calls only snapshot known
     * slots; they do not replace the bridge's blocking slot-event listener.
     */
    private fun startSlotEvents() {
        val generation = synchronized(tokenMonitor) {
            slotEventGeneration += 1
            presentTokens = currentTokens()
            tokenMonitor.notifyAll()
            slotEventGeneration
        }
        slotEventExecutor.execute {
            while (isSlotEventGenerationActive(generation)) {
                try {
                    val slot = module.waitForSlotEvent(false) ?: continue
                    synchronized(tokenMonitor) {
                        if (slotEventGeneration != generation) return@execute
                        presentTokens = if (slot.slotInfo.isTokenPresent) {
                            presentTokens + (slot.id to (slot.token as RtPkcs11Token))
                        } else {
                            presentTokens - slot.id
                        }
                        tokenMonitor.notifyAll()
                    }
                } catch (_: Throwable) {
                    // C_Finalize unblocks the vendor's blocking slot wait during
                    // Activity teardown. A new generation is started on resume.
                    synchronized(tokenMonitor) {
                        if (slotEventGeneration == generation) {
                            presentTokens = emptyMap()
                            tokenMonitor.notifyAll()
                        }
                    }
                    return@execute
                }
            }
        }
    }

    private fun stopSlotEvents() {
        synchronized(tokenMonitor) {
            slotEventGeneration += 1
            presentTokens = emptyMap()
            tokenMonitor.notifyAll()
        }
    }

    private fun isSlotEventGenerationActive(generation: Long): Boolean =
        synchronized(tokenMonitor) { slotEventGeneration == generation }

    private fun currentTokens(): Map<Long, RtPkcs11Token> =
        module.getSlotList(true).associate { it.id to (it.token as RtPkcs11Token) }

    private fun requireSession(id: String): OpenSession =
        sessions[id] ?: error("Rutoken session is closed or unknown.")

    private fun findSingleMasterKey(session: RtPkcs11Session): Pkcs11PrivateKeyObject {
        val template = listOf(
            session.attributeFactory.makeAttribute(CKA_CLASS, CKO_PRIVATE_KEY),
            session.attributeFactory.makeAttribute(CKA_PRIVATE, true),
            session.attributeFactory.makeAttribute(CKA_KEY_TYPE, CKK_VENDOR_BIP32),
        )
        val keys = session.objectManager.findObjectsAtOnce(Pkcs11PrivateKeyObject::class.java, template)
        check(keys.isNotEmpty()) {
            "Rutoken contains no BIP32 ECDSA master key; create or import a wallet first."
        }
        check(keys.size == 1) {
            "Rutoken contains ${keys.size} BIP32 ECDSA master keys; Wallet Demo currently supports exactly one."
        }
        return keys.single()
    }

    private fun derivePublic(
        session: RtPkcs11Session,
        master: Pkcs11PrivateKeyObject,
        path: LongArray?,
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

    private fun hardened(index: Long): Long {
        require(index in 0 until HARDENED)
        return index or HARDENED
    }

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
        private const val TOKEN_WAIT_NANOS = 30_000_000_000L
        private const val NANOS_PER_MILLISECOND = 1_000_000L
        private const val HARDENED = 0x80000000L
        private val SECP256K1_OID = byteArrayOf(0x06, 0x05, 0x2B, 0x81.toByte(), 0x04, 0x00, 0x0A)

        @Volatile private var instance: RutokenRuntime? = null

        fun get(): RutokenRuntime =
            instance ?: synchronized(this) {
                instance ?: RutokenRuntime().also { instance = it }
            }
    }
}
