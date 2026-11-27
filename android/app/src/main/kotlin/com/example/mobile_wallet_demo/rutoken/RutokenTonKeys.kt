package com.example.mobile_wallet_demo.rutoken

import ru.rutoken.pkcs11wrapper.attribute.Pkcs11Attribute
import ru.rutoken.pkcs11wrapper.constant.IPkcs11KeyType
import ru.rutoken.pkcs11wrapper.constant.IPkcs11MechanismType
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_CLASS
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_EC_PARAMS
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_EC_POINT
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_EXTRACTABLE
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_ID
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_KEY_TYPE
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_LABEL
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_PRIVATE
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_SENSITIVE
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_SIGN
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_TOKEN
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_VALUE
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11AttributeType.CKA_VERIFY
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11ObjectClass.CKO_PRIVATE_KEY
import ru.rutoken.pkcs11wrapper.constant.standard.Pkcs11ObjectClass.CKO_PUBLIC_KEY
import ru.rutoken.pkcs11wrapper.mechanism.Pkcs11Mechanism
import ru.rutoken.pkcs11wrapper.`object`.key.Pkcs11PrivateKeyObject
import ru.rutoken.pkcs11wrapper.`object`.key.Pkcs11PublicKeyObject
import ru.rutoken.pkcs11wrapper.rutoken.main.RtPkcs11Session

/** Owns Wallet Demo's Ed25519 objects. Call only within the runtime's NFC session. */
internal class RutokenTonKeys(private val session: RtPkcs11Session) {
    private val attributes = session.attributeFactory
    private val objects = session.objectManager

    fun read(): Map<String, Any> {
        val publicKey = findPublic() ?: return emptyMap()
        val privateKey = findPrivate(id(publicKey)) ?: return emptyMap()
        return describe(publicKey, privateKey)
    }

    fun generate(keyId: ByteArray): Map<String, Any> {
        if (findPublic() != null) throw RutokenTonKeyExistsException()
        val pair = session.keyManager.generateKeyPair(
            Pkcs11PublicKeyObject::class.java,
            Pkcs11PrivateKeyObject::class.java,
            Pkcs11Mechanism.make(CKM_EC_EDWARDS_KEY_PAIR_GEN),
            publicTemplate(keyId),
            privateTemplate(keyId),
        )
        return describe(pair.publicKey, pair.privateKey)
    }

    fun importKey(keyId: ByteArray, seed: ByteArray, publicKeyBytes: ByteArray): Map<String, Any> {
        require(seed.size == 32 && publicKeyBytes.size == 32)
        val existing = findPublic()
        if (existing != null && !publicBytes(existing).contentEquals(publicKeyBytes)) {
            throw RutokenTonKeyExistsException()
        }
        // The public object is written first. After a disconnect, the same
        // phrase can finish the import, or adopt the already-complete pair.
        val publicKey = existing ?: objects.createObject(
            Pkcs11PublicKeyObject::class.java,
            publicTemplate(keyId) +
                attributes.makeAttribute(CKA_EC_POINT, byteArrayOf(0x04, 0x20) + publicKeyBytes),
        )
        val objectId = id(publicKey)
        val privateKey = findPrivate(objectId) ?: objects.createObject(
            Pkcs11PrivateKeyObject::class.java,
            privateTemplate(objectId) + listOf(
                attributes.makeAttribute(CKA_EC_PARAMS, ED25519_OID),
                attributes.makeAttribute(CKA_VALUE, seed),
            ),
        )
        return describe(publicKey, privateKey)
    }

    fun sign(keyId: ByteArray, hash: ByteArray): ByteArray {
        require(keyId.size == 16 && hash.size == 32)
        val key = checkNotNull(findPrivate(keyId)) { "TON signing key was not found on the card." }
        assertProtected(key)
        // Null parameters select PureEdDSA. The TON cell hash is the message.
        return session.signManager.signAtOnce(hash, Pkcs11Mechanism.make(CKM_EDDSA), key).also {
            check(it.size == 64) { "Invalid Ed25519 signature length from the card." }
        }
    }

    private fun findPublic(): Pkcs11PublicKeyObject? {
        val keys = objects.findObjectsAtOnce(
            Pkcs11PublicKeyObject::class.java,
            listOf(attributes.makeAttribute(CKA_CLASS, CKO_PUBLIC_KEY)) + keyFilter(),
        )
        check(keys.size <= 1) { "Multiple TON public keys found on the card." }
        return keys.singleOrNull()
    }

    private fun findPrivate(id: ByteArray): Pkcs11PrivateKeyObject? {
        val keys = objects.findObjectsAtOnce(
            Pkcs11PrivateKeyObject::class.java,
            keyFilter() + listOf(
                attributes.makeAttribute(CKA_CLASS, CKO_PRIVATE_KEY),
                attributes.makeAttribute(CKA_ID, id),
            ),
        )
        check(keys.size <= 1) { "Multiple private keys match the TON key identity." }
        return keys.singleOrNull()
    }

    private fun keyFilter() = listOf(
        attributes.makeAttribute(CKA_LABEL, LABEL),
        attributes.makeAttribute(CKA_KEY_TYPE, CKK_EC_EDWARDS),
        attributes.makeAttribute(CKA_TOKEN, true),
    )

    private fun publicTemplate(id: ByteArray): List<Pkcs11Attribute> = keyFilter() + listOf(
        attributes.makeAttribute(CKA_CLASS, CKO_PUBLIC_KEY),
        attributes.makeAttribute(CKA_ID, id),
        attributes.makeAttribute(CKA_EC_PARAMS, ED25519_OID),
        attributes.makeAttribute(CKA_VERIFY, true),
    )

    private fun privateTemplate(id: ByteArray): List<Pkcs11Attribute> = keyFilter() + listOf(
        attributes.makeAttribute(CKA_CLASS, CKO_PRIVATE_KEY),
        attributes.makeAttribute(CKA_ID, id),
        attributes.makeAttribute(CKA_PRIVATE, true),
        attributes.makeAttribute(CKA_SIGN, true),
        attributes.makeAttribute(CKA_SENSITIVE, true),
        attributes.makeAttribute(CKA_EXTRACTABLE, false),
    )

    private fun describe(
        publicKey: Pkcs11PublicKeyObject,
        privateKey: Pkcs11PrivateKeyObject,
    ): Map<String, Any> {
        assertProtected(privateKey)
        return mapOf(
            "keyId" to id(publicKey),
            "publicKey" to publicBytes(publicKey),
            "generatedOnCard" to (privateKey.getLocalAttributeValue(session).value == true),
        )
    }

    private fun assertProtected(privateKey: Pkcs11PrivateKeyObject) {
        check(
            privateKey.getSensitiveAttributeValue(session).value == true &&
                privateKey.getExtractableAttributeValue(session).value == false,
        ) { "The TON key must be sensitive and non-extractable." }
    }

    private fun id(key: Pkcs11PublicKeyObject): ByteArray =
        key.getIdAttributeValue(session).byteArrayValue.also { check(it.size == 16) }

    private fun publicBytes(key: Pkcs11PublicKeyObject): ByteArray {
        val point = key.getByteArrayAttributeValue(session, CKA_EC_POINT).byteArrayValue
        if (point.size == 32) return point
        check(point.size == 34 && point[0] == 0x04.toByte() && point[1] == 0x20.toByte()) {
            "Invalid Ed25519 public key encoding from the card."
        }
        return point.copyOfRange(2, 34)
    }

    companion object {
        // PKCS#11 3.x identifiers not enumerated by pkcs11wrapper 4.3.1.
        private val CKM_EC_EDWARDS_KEY_PAIR_GEN = IPkcs11MechanismType.getInstance(0x1055L)
        private val CKM_EDDSA = IPkcs11MechanismType.getInstance(0x1057L)
        private val CKK_EC_EDWARDS = IPkcs11KeyType.getInstance(0x40L)
        private val ED25519_OID = byteArrayOf(0x06, 0x03, 0x2B, 0x65, 0x70)
        private const val LABEL = "Wallet Demo TON Ed25519"
    }
}

internal class RutokenTonKeyExistsException : RuntimeException("Card already has a TON key.")
