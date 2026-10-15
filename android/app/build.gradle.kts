import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials. Gitignored, so an absent file is normal on a
// fresh clone and the release build falls back to the debug signature.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val missingKeyProperties = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .filter { keyProperties.getProperty(it).isNullOrBlank() }
// A present-but-incomplete file means someone meant to sign: fail with the
// missing names instead of a Gradle NPE or a silent debug-signed release.
if (keyProperties.isNotEmpty() && missingKeyProperties.isNotEmpty()) {
    throw GradleException("android/key.properties is missing: ${missingKeyProperties.joinToString()}")
}
val hasReleaseKey = keyProperties.isNotEmpty()

android {
    namespace = "com.tedif.weight_buddy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications for scheduled notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Unique application ID.
        applicationId = "com.tedif.weight_buddy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keyProperties.getProperty("storeFile")!!)
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug signature only when the (gitignored)
            // keystore is absent; tool/ship.sh refuses to distribute that.
            signingConfig = if (hasReleaseKey)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
