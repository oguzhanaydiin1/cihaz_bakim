import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.oalabs.harrier"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.oalabs.harrier"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 10 ve üstü: MediaStore ile göreli yol (RELATIVE_PATH) ve güvenli silme.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Kalıcı imza anahtarı GitHub "secret"larından gelir (ANDROID_KEYSTORE_BASE64,
    // ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS). Yoksa geçici test anahtarıyla imzalanır;
    // o durumda yeni bir test sürümü kurmadan önce eskisini kaldırmak gerekir.
    val keystoreB64 = System.getenv("ANDROID_KEYSTORE_BASE64").orEmpty()
    val keystorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD").orEmpty()
    val hasReleaseKey = keystoreB64.isNotBlank() && keystorePassword.isNotBlank()

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                val file = layout.buildDirectory.file("release.jks").get().asFile
                file.parentFile.mkdirs()
                file.writeBytes(Base64.getMimeDecoder().decode(keystoreB64))
                storeFile = file
                storePassword = keystorePassword
                keyAlias = System.getenv("ANDROID_KEY_ALIAS").orEmpty().ifBlank { "harrier" }
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
