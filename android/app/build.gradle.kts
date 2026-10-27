import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. android/key.properties is written only on a trusted
// machine or by the protected "Release App Bundle" workflow; it is
// git-ignored and never committed (see docs/RELEASE_SIGNING.md).
// Without it, a release APK falls back to the debug key for local testing,
// but a Google Play App Bundle (bundleRelease) refuses to build, so a
// debug-signed bundle can never be uploaded by mistake.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.aduchat.chat_adunka"
    // Google Play requires new apps and updates to target Android 16 (API 36).
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aduchat.chat_adunka"
        // Firebase Authentication and WebRTC need Android 6.0 (API 23) or newer.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        // Version name and code come from `version:` in pubspec.yaml.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}

tasks.matching { it.name == "bundleRelease" || it.name == "signReleaseBundle" }.configureEach {
    doFirst {
        if (!hasReleaseKey) {
            throw GradleException(
                "Release App Bundle needs the upload key: android/key.properties is missing. " +
                    "See docs/RELEASE_SIGNING.md. A debug-signed bundle is never built."
            )
        }
    }
}
