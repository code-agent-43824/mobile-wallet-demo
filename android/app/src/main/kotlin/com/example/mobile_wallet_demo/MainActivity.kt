package com.example.mobile_wallet_demo

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity): local_auth's BiometricPrompt
// requires the host activity to be a FragmentActivity, otherwise enabling
// biometrics fails with "local_auth plugin requires activity to be a
// FragmentActivity".
class MainActivity : FlutterFragmentActivity()
