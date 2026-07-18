import java.util.Properties

fun loadAndroidTvVersionCode(rootDir: File, fallback: Int): Int {
    val pubspec = rootDir.resolve("../pubspec.yaml")
    if (!pubspec.exists()) return fallback

    val line = pubspec.readLines().firstOrNull {
        it.trimStart().startsWith("android_tv_build_number:")
    } ?: return fallback

    val rawValue = line.substringAfter(":", "").trim()
    return rawValue.toIntOrNull() ?: fallback
}

fun loadAndroidTvVersionName(rootDir: File, fallback: String): String {
    val pubspec = rootDir.resolve("../pubspec.yaml")
    if (!pubspec.exists()) return fallback

    val line = pubspec.readLines().firstOrNull {
        it.trimStart().startsWith("android_tv_version:")
    } ?: return fallback

    val rawValue = line.substringAfter(":", "").trim()
    return rawValue.ifEmpty { fallback }
}

plugins {
    id("com.android.application")
    // Sipflix fork: Google Services (Firebase) plugin disabled. Firebase is only
    // push messaging, which returns early on Android TV (PlatformDetection.isMobile
    // is false), so it's never initialized here — and we don't ship against
    // upstream Moonfin's Firebase project (google-services.json has no client for
    // com.sipflix.moonfin). Re-add the plugin + a matching client to use Firebase.
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val keystoreStoreType = keystoreProperties
    .getProperty("storeType")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }

val hasReleaseKeystore = rootProject.file("app/release.keystore").exists() &&
    (keystoreProperties.getProperty("keyAlias")?.isNotBlank() == true)

android {
    namespace = "org.moonfin.androidtv"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    val androidTvVersionCode = loadAndroidTvVersionCode(rootDir, flutter.versionCode)
    val androidTvVersionName = loadAndroidTvVersionName(rootDir, flutter.versionName)

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Fallback so the main manifest's ${enableImpeller} always resolves;
        // TV flavors override this to "false".
        manifestPlaceholders["enableImpeller"] = "true"
    }

    flavorDimensions += "device"
    productFlavors {
        // Sipflix fork uses its own applicationId so it coexists with the
        // official Moonfin (org.moonfin.androidtv) on the same device. The code
        // namespace stays org.moonfin.androidtv (unchanged).
        val baseAppId = "com.sipflix.moonfin"
        val baseAppName = "Moonfin"
        val mobileAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        val tvAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        create("mobile") {
            dimension = "device"
            applicationId = baseAppId
            versionCode = flutter.versionCode
            versionName = flutter.versionName
            ndk { abiFilters += mobileAbis }
            manifestPlaceholders["appName"] = baseAppName
        }
        create("mobile-beta") {
            dimension = "device"
            applicationId = "$baseAppId.beta"
            versionCode = flutter.versionCode
            versionName = flutter.versionName
            ndk { abiFilters += mobileAbis }
            manifestPlaceholders["appName"] = "$baseAppName Beta"
        }
        create("androidTv") {
            dimension = "device"
            applicationId = baseAppId
            versionCode = androidTvVersionCode
            versionName = androidTvVersionName
            ndk { abiFilters += tvAbis }
            manifestPlaceholders["appName"] = baseAppName
            // Impeller off on TV: the GLES fallback stutters on TV-box GPUs.
            manifestPlaceholders["enableImpeller"] = "false"
        }
        create("androidTv-beta") {
            dimension = "device"
            applicationId = "$baseAppId.beta"
            versionCode = androidTvVersionCode
            versionName = androidTvVersionName
            ndk { abiFilters += tvAbis }
            manifestPlaceholders["appName"] = "$baseAppName Beta"
            manifestPlaceholders["enableImpeller"] = "false"
        }
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = file("release.keystore")
                storeType = keystoreStoreType
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            pickFirsts += setOf("**/libc++_shared.so")
        }
    }

}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.android.gms:play-services-cast-framework:22.0.0")
    implementation("eu.simonbinder:sqlite3-native-library:3.52.0")
    implementation("androidx.tvprovider:tvprovider:1.1.0")
    implementation("androidx.work:work-runtime-ktx:2.10.1")
}

val flutterApkOutputDir = layout.buildDirectory.dir("app/outputs/flutter-apk")

tasks.register<Copy>("copyAndroidTvDebugApkForFlutter") {
    from(flutterApkOutputDir.map { it.file("app-androidtv-debug.apk") })
    into(flutterApkOutputDir)
    rename { "app-debug.apk" }
}

tasks.matching { it.name == "assembleDebug" }.configureEach {
    finalizedBy("copyAndroidTvDebugApkForFlutter")
}
