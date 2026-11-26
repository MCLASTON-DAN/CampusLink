plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ug.ac.cavendish.campuslink"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Needed by the notifications plugin.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ug.ac.cavendish.campuslink"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One permanent key, so every new APK installs over the old one.
    // GitHub Actions puts it in place from the ANDROID_KEYSTORE_BASE64 secret.
    val keystoreFile = System.getenv("ANDROID_KEYSTORE_PATH")?.let { file(it) }
    val keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
    signingConfigs {
        if (keystoreFile != null && keystoreFile.exists() && keyPassword != null) {
            create("release") {
                storeFile = keystoreFile
                storePassword = keyPassword
                keyAlias = "campuslink"
                this.keyPassword = keyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    // Slim APK for one kind of phone processor. The release build sets
    // CAMPUSLINK_ABI (e.g. arm64-v8a) to leave out the parts other phones
    // need, which makes in-app updates about 3x smaller. The version number
    // stays the same, so the all-in-one APK and the slim ones can replace
    // each other in both directions.
    val onlyAbi = System.getenv("CAMPUSLINK_ABI")
    if (!onlyAbi.isNullOrBlank()) {
        packaging {
            jniLibs {
                listOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86")
                    .filter { it != onlyAbi }
                    .forEach { excludes += "lib/$it/**" }
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
