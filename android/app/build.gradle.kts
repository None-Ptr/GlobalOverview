import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 签名凭据外置到 android/key.properties（不入库，见 android/.gitignore）。
// 缺失时直接失败并说清怎么办，而不是等打包时报一个看不懂的签名错误。
val keystorePropertiesFile = rootProject.file("key.properties")
require(keystorePropertiesFile.exists()) {
    "缺少 android/key.properties（需要 storePassword / keyPassword / keyAlias / storeFile 四项）。" +
        "该文件不入库，请本地创建；密钥文件在 legacy/key.jks。"
}
val keystoreProperties = Properties().apply { load(FileInputStream(keystorePropertiesFile)) }

android {
    namespace = "com.github.overviewsoftware.globaloverview"
    compileSdk = flutter.compileSdkVersion
    ndkPath = "D:/OI/Android/ndk/28.2.13676358"

    compileOptions {
        // flutter_local_notifications 需要核心库脱糖（java.time 等）。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        // 复用老 uni-app 离线基座的签名密钥，使新 Flutter 版可直接覆盖升级已安装的老 app。
        // 凭据来自 android/key.properties（alias=my-alias），明文不再出现在本文件里。
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = file(keystoreProperties.getProperty("storeFile"))
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    defaultConfig {
        applicationId = "com.github.overviewsoftware.globaloverview"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
