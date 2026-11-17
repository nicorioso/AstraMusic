import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningFile = rootProject.file("key.properties")
val releaseSigning = Properties()
if (releaseSigningFile.exists()) {
    releaseSigningFile.inputStream().use(releaseSigning::load)
    require(listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
        !releaseSigning.getProperty(it).isNullOrBlank()
    }) { "android/key.properties debe incluir storeFile, storePassword, keyAlias y keyPassword" }
}

android {
    namespace = "com.nicorioso.astramusic"
    compileSdk = 36
    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += "**/libpython.zip.so"
            keepDebugSymbols += "**/libffmpeg.zip.so"
        }
    }
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nicorioso.astramusic"
        minSdk = 24
        ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64") }
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningFile.exists()) {
                val configuredStoreFile = releaseSigning.getProperty("storeFile")
                val rootStoreFile = rootProject.file(configuredStoreFile)
                val appStoreFile = project.file(configuredStoreFile)
                storeFile = when {
                    rootStoreFile.isFile -> rootStoreFile
                    appStoreFile.isFile -> appStoreFile
                    else -> error("No existe el storeFile indicado en android/key.properties")
                }
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
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

// Los artefactos oficiales se publican en Maven Central.
dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
}
