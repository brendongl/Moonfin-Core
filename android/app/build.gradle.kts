import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

fun pubspecValue(rootDir: File, key: String): String? {
    val pubspec = rootDir.resolve("../pubspec.yaml")
    if (!pubspec.exists()) return null
    val line = pubspec.readLines().firstOrNull {
        it.trimStart().startsWith("$key:")
    } ?: return null
    return line.substringAfter(":", "").trim().ifEmpty { null }
}

// Sipflix fork: sipflix_tv_* is the release identity the OTA updater compares,
// so it takes precedence over upstream's android_tv_* fields when present.
fun loadAndroidTvVersionCode(rootDir: File, fallback: Int): Int {
    return pubspecValue(rootDir, "sipflix_tv_build_number")?.toIntOrNull()
        ?: pubspecValue(rootDir, "android_tv_build_number")?.toIntOrNull()
        ?: fallback
}

fun loadAndroidTvVersionName(rootDir: File, fallback: String): String {
    return pubspecValue(rootDir, "sipflix_tv_version")
        ?: pubspecValue(rootDir, "android_tv_version")
        ?: fallback
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
        // Sipflix fork: launcher label. Flavors append " Beta" to this.
        val baseAppName = "Sipflix Moonfin"
        // Optional application-id suffix for on-device testing, set through the
        // environment so an unset build is byte-identical to before:
        //   MOONFIN_TEST_ID_SUFFIX=.hwtest flutter build apk --flavor androidTv --debug
        //
        // Why this exists: a debug-signed test build cannot install over a
        // release-signed build of the same flavor, and uninstalling to make room
        // deletes that package's data directory - which holds the cartridge
        // saves (SRAM/EEPROM). Those are stored locally and are NOT backed up to
        // the server, so an uninstall can lose real game progress. A distinct id
        // installs alongside instead and touches nothing.
        val testIdSuffix = System.getenv("MOONFIN_TEST_ID_SUFFIX").orEmpty()
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
            applicationId = baseAppId + testIdSuffix
            versionCode = androidTvVersionCode
            versionName = androidTvVersionName
            ndk { abiFilters += tvAbis }
            manifestPlaceholders["appName"] =
                if (testIdSuffix.isEmpty()) baseAppName else "$baseAppName Test"
            // Impeller off by default on TV: the GLES fallback stutters on
            // TV-box GPUs. MoonfinApplication turns it on for boxes where it
            // runs on Vulkan.
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

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    implementation("com.google.android.gms:play-services-cast-framework:22.3.1")
    implementation("eu.simonbinder:sqlite3-native-library:3.52.0")
    implementation("androidx.tvprovider:tvprovider:1.1.0")
    implementation("androidx.work:work-runtime-ktx:2.12.0")
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
