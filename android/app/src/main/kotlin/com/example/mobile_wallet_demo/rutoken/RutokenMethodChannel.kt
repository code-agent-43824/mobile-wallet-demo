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
                runtime.openSession(call.requiredString("pin"))
            }
            "readPublicMaterial" -> execute(result) {
                runtime.readPublicMaterial(call.requiredString("sessionId"))
            }
            "signDigest" -> execute(result) {
                runtime.signDigest(
                    sessionId = call.requiredString("sessionId"),
                    derivationPath = call.requiredLongArray("derivationPath"),
                    digest = call.requiredBytes("digest"),
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
                            "rutoken_native",
                            error.message ?: error.javaClass.simpleName,
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

    companion object {
        const val CHANNEL_NAME = "wallet_demo/rutoken"
    }
}
