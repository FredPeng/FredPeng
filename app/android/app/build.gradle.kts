import groovy.json.JsonSlurper
import java.net.URI
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google (Firebase Analytics -> Google Ads): drop google-services.json into
// android/app/ and it is picked up automatically.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// One config file for Dart and Android: config/app_config.json
// (build with --dart-define-from-file=config/app_config.json).
@Suppress("UNCHECKED_CAST")
val appConfig: Map<String, Any?> = rootProject.file("../config/app_config.json").let {
    if (it.exists()) JsonSlurper().parse(it) as Map<String, Any?> else emptyMap()
}
fun cfg(key: String, default: String = ""): String = (appConfig[key] as? String)?.takeIf { it.isNotBlank() } ?: default

val storeHost: String = cfg("STORE_URL").let { url ->
    if (url.isBlank()) "example.invalid" else URI(url).host ?: "example.invalid"
}

// Release signing: android/key.properties (never commit it; see README).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.sophieshop.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent once published on Google Play: choose carefully.
        applicationId = cfg("APPLICATION_ID", "com.sophieshop.app")
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Apostrophes must be escaped in Android string resources ("Sophie's").
        resValue("string", "app_name", cfg("APP_LABEL", "Sophie's").replace("'", "\\'"))
        resValue("string", "facebook_app_id", cfg("META_APP_ID", "0"))
        resValue("string", "facebook_client_token", cfg("META_CLIENT_TOKEN", "0"))
        manifestPlaceholders["metaEnabled"] = cfg("META_APP_ID").isNotBlank().toString()
        manifestPlaceholders["storeHost"] = storeHost
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                // Lets `flutter build apk` work before a keystore exists.
                // Google Play will reject debug-signed uploads.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
