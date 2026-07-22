package com.example.mobile_wallet_demo

import android.os.Bundle
import com.example.mobile_wallet_demo.rutoken.RutokenMethodChannel
import com.example.mobile_wallet_demo.rutoken.RutokenRuntime
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity): local_auth's BiometricPrompt
// requires the host activity to be a FragmentActivity, otherwise enabling
// biometrics fails with "local_auth plugin requires activity to be a
// FragmentActivity".
class MainActivity : FlutterFragmentActivity() {
    private val rutokenRuntime by lazy { RutokenRuntime.get(application) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycle.addObserver(rutokenRuntime)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RutokenMethodChannel(
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            runtime = rutokenRuntime,
            activity = this,
        ).register()
    }
}
