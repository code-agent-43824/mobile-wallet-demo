plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mobile_wallet_demo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.mobile_wallet_demo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // The official Rutoken PC/SC bridge supports Android 9 (API 28) and
        // newer. Keeping the minimum explicit prevents an APK that installs
        // successfully but can never load the native transport.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // reown_walletkit's yttrium bindings talk to native Rust over JNA,
            // whose libjnidispatch.so resolves Java fields (e.g.
            // com.sun.jna.Pointer.peer) by name via JNI at init. R8 shrinking
            // renames/strips them -> UnsatisfiedLinkError ~1s after launch
            // (release only; debug has no R8). Disable shrinking for this demo;
            // proguard-rules.pro keeps the JNA/uniffi rules if it's re-enabled.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    implementation("ru.rutoken.rtpcscbridge:rtpcscbridge:1.4.0")
    implementation("ru.rutoken.pkcs11wrapper:pkcs11wrapper:4.3.1") {
        isTransitive = false
    }
    implementation("ru.rutoken:pkcs11jna:4.2.0") {
        isTransitive = false
    }
    implementation("net.java.dev.jna:jna:5.17.0@aar")
}

flutter {
    source = "../.."
}
