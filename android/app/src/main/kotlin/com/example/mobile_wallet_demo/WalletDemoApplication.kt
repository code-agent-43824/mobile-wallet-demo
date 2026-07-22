package com.example.mobile_wallet_demo

import android.app.Application
import com.example.mobile_wallet_demo.rutoken.RutokenRuntime
import ru.rutoken.rtpcscbridge.RtPcscBridge
import ru.rutoken.rttransport.InitParameters
import ru.rutoken.rttransport.TokenInterface

/**
 * Starts the Rutoken transport before Android creates the first Activity.
 *
 * The official demo performs these calls from Application.onCreate. Attaching
 * later from MainActivity can miss the Activity callbacks through which the
 * PC/SC bridge enables NFC exchange.
 */
class WalletDemoApplication : Application() {
    internal lateinit var rutokenRuntime: RutokenRuntime
        private set

    override fun onCreate() {
        super.onCreate()

        RtPcscBridge.setAppContext(this)
        RtPcscBridge.getTransportExtension().attachToLifecycle(
            this,
            true,
            InitParameters.Builder()
                .setEnabledTokenInterfaces(TokenInterface.NFC)
                .build(),
        )

        // Construct the token manager/runtime before MainActivity is created;
        // PKCS#11 itself remains bound to the Activity onStart/onStop observer.
        rutokenRuntime = RutokenRuntime.get()
    }
}
