package com.example.mobile_wallet_demo.rutoken

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class RutokenMethodChannel(
    messenger: BinaryMessenger,
    private val runtime: RutokenRuntime,
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    fun register() {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openSession" -> execute(result) {
                runtime.openSession(
                    operationId = call.requiredString("operationId"),
                    pin = call.requiredString("pin"),
                )
            }
            "cancelOperation" -> {
                runtime.cancelOperation(call.requiredString("operationId"))
                result.success(null)
            }
            "readAccountDescriptor" -> execute(result) {
                runtime.readAccountDescriptor(call.requiredString("sessionId"))
            }
            "signDigest" -> execute(result) {
                runtime.signDigest(
                    sessionId = call.requiredString("sessionId"),
                    derivationPath = call.requiredLongArray("derivationPath"),
                    digest = call.requiredBytes("digest"),
                )
            }
            "importWallet" -> execute(result) {
                runtime.importWallet(
                    sessionId = call.requiredString("sessionId"),
                    masterPrivateKey = call.requiredBytes("masterPrivateKey"),
                    chainCode = call.requiredBytes("chainCode"),
                )
            }
            "closeSession" -> execute(result) {
                runtime.closeSession(call.requiredString("sessionId"))
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun execute(result: MethodChannel.Result, block: RutokenRuntime.() -> Any?) {
        runtime.submit(block) { operation ->
            activity.runOnUiThread {
                operation.fold(
                    onSuccess = result::success,
                    onFailure = { error ->
                        result.error(
                            nativeErrorCode(error),
                            nativeErrorMessage(error),
                            mapOf("type" to error.javaClass.name),
                        )
                    },
                )
            }
        }
    }

    private fun MethodCall.requiredString(name: String): String =
        argument<String>(name)?.takeIf { it.isNotEmpty() }
            ?: throw IllegalArgumentException("Missing non-empty '$name'.")

    private fun MethodCall.requiredBytes(name: String): ByteArray =
        argument<ByteArray>(name) ?: throw IllegalArgumentException("Missing '$name'.")

    private fun MethodCall.requiredLongArray(name: String): LongArray {
        val values = argument<List<Number>>(name)
            ?: throw IllegalArgumentException("Missing '$name'.")
        return values.map(Number::toLong).toLongArray()
    }

    private fun nativeErrorCode(error: Throwable): String {
        if (error is RutokenOperationCancelledException) return "rutoken_cancelled"
        if (error is RutokenWaitTimeoutException) return "rutoken_timeout"
        if (error is RutokenNfcLostException) return "rutoken_nfc_lost"
        val diagnostic = "${error.javaClass.name} ${error.message}".uppercase()
        return when {
            "CKR_PIN_LOCKED" in diagnostic -> "rutoken_pin_locked"
            "CKR_PIN_INCORRECT" in diagnostic || "CKR_PIN_INVALID" in diagnostic ->
                "rutoken_pin_invalid"
            "CKR_DEVICE_REMOVED" in diagnostic ||
                "CKR_TOKEN_NOT_PRESENT" in diagnostic ||
                "SCARD_W_REMOVED_CARD" in diagnostic -> "rutoken_nfc_lost"
            else -> "rutoken_native"
        }
    }

    private fun nativeErrorMessage(error: Throwable): String =
        when (nativeErrorCode(error)) {
            "rutoken_cancelled" -> "Rutoken NFC wait was cancelled."
            "rutoken_timeout" -> "Rutoken was not detected over NFC within 30 seconds."
            "rutoken_pin_invalid" -> "Rutoken PIN is invalid."
            "rutoken_pin_locked" -> "Rutoken PIN is locked."
            "rutoken_nfc_lost" -> "Rutoken NFC connection was lost."
            else -> "Rutoken native operation failed."
        }

    companion object {
        const val CHANNEL_NAME = "wallet_demo/rutoken"
    }
}
