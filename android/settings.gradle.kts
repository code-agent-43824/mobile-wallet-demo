pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    // Legacy KGP mode: built-in Kotlin is BLOCKED by the unmigrated pub
    // plugin file_selector_android 0.5.2+6 (applies kotlin-android on top of
    // the built-in Kotlin extension -> "extension already registered").
    // Revisit when the plugin ships a built-in-Kotlin-compatible release.
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
