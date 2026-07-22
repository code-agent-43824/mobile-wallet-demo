package com.example.mobile_wallet_demo.rutoken

import com.sun.jna.Native
import ru.rutoken.pkcs11jna.RtPkcs11
import ru.rutoken.pkcs11wrapper.main.Pkcs11BaseModule
import ru.rutoken.pkcs11wrapper.rutoken.attribute.RtPkcs11AttributeFactory
import ru.rutoken.pkcs11wrapper.rutoken.lowlevel.jna.RtPkcs11JnaLowLevelApi
import ru.rutoken.pkcs11wrapper.rutoken.lowlevel.jna.RtPkcs11JnaLowLevelFactory
import ru.rutoken.pkcs11wrapper.rutoken.main.RtPkcs11Api
import ru.rutoken.pkcs11wrapper.rutoken.main.RtPkcs11HighLevelFactory

/** Entry point for the vendor PKCS#11 library bundled for arm64-v8a. */
internal class WtPkcs11Module : Pkcs11BaseModule(
    RtPkcs11Api(
        RtPkcs11JnaLowLevelApi(
            Native.load("wtpkcs11ecp", RtPkcs11::class.java),
            RtPkcs11JnaLowLevelFactory(),
        ),
    ),
    RtPkcs11HighLevelFactory(),
    RtPkcs11AttributeFactory(),
)
