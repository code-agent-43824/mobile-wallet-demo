# R8/ProGuard keep rules.
#
# reown_walletkit's `yttrium` bindings talk to native Rust over **JNA**. JNA's
# native libjnidispatch.so resolves Java classes/fields by name via JNI at init
# (e.g. com.sun.jna.Pointer.peer in Native.initIDs). If R8 renames or strips
# them the result is, on launch:
#   java.lang.UnsatisfiedLinkError: Can't obtain peer field ID for class com.sun.jna.Pointer
# So JNA (and the uniffi-generated bindings that use it) must be kept verbatim.
# The release build currently disables shrinking entirely (see build.gradle.kts),
# but these rules keep it correct if shrinking is ever re-enabled.

# --- JNA (com.sun.jna) — accessed natively by name ---
-keep class com.sun.jna.** { *; }
-keepclassmembers class com.sun.jna.** { *; }
-keep class * extends com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-dontwarn com.sun.jna.**
-dontwarn java.awt.**

# --- uniffi-generated bindings (reown yttrium / walletconnect_pay) ---
# uniffi maps Rust structs to JNA Structures whose fields are read by layout,
# so their members must not be renamed/removed.
-keep class uniffi.** { *; }
-keepclassmembers class uniffi.** { *; }

# --- reown / WalletConnect SDK ---
-keep class com.reown.** { *; }
-keep class com.walletconnect.** { *; }
-dontwarn com.reown.**
-dontwarn com.walletconnect.**
