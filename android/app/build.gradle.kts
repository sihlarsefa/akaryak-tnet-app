import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Gizli değerler git dışındadır (spec C.9):
// - android/key.properties: yayın imzası (storeFile, storePassword, keyAlias, keyPassword); yoksa debug imzası.
// - android/local.properties: MAPS_API_KEY (Google Maps, com.ortakplatform.akaryakitnet ile kısıtlı).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
val hasReleaseKeystore = !keystoreProperties.getProperty("storeFile").isNullOrBlank()

android {
    namespace = "com.ortakplatform.akaryakitnet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications için gerekli.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ortakplatform.akaryakitnet"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = localProperties.getProperty("MAPS_API_KEY") ?: ""
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                // Mutlak yol (/… ya da C:\…) ya da android/ köküne göre (ör. app/upload-keystore.jks).
                val path = keystoreProperties.getProperty("storeFile").replace('\\', '/').trim()
                storeFile = if (path.startsWith("/") || (path.length > 2 && path[1] == ':')) file(path) else rootProject.file(path)
            }
        }
    }

    buildTypes {
        release {
            // key.properties yoksa (CI) debug imzasıyla derlenir; mağaza sürümü için key.properties + jks şarttır.
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// Firebase: google-services.json yalnızca varsa uygulanır; yoksa push kapalı çalışır (spec C.9).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
