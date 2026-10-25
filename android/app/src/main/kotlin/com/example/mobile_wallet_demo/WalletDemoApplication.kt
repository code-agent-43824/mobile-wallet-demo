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
    /** Null when this process cannot load the card libraries. */
    internal var rutokenRuntime: RutokenRuntime? = null
        private set

    override fun onCreate() {
        super.onCreate()

        // Tech debt: the PKCS#11 library ships for arm64-v8a only and the
        // PC/SC bridge has no x86_64 build, so any other ABI (x86_64
        // emulators, 32-bit phones) runs without cards rather than dying
        // with UnsatisfiedLinkError. Dart mirrors this check.
        if (!isRutokenSupported) return

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

    companion object {
        /**
         * The ABI this process runs as, not the device's list: x86_64 images
         * with ARM translation report arm64-v8a in Build.SUPPORTED_ABIS while
         * the app itself runs as x86_64.
         */
        val isRutokenSupported: Boolean
            get() = System.getProperty("os.arch") == "aarch64"
    }
}
