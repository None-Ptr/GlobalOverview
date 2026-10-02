plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.github.overviewsoftware.globaloverview"
    compileSdk = flutter.compileSdkVersion
    ndkPath = "D:/OI/Android/ndk/28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        // 复用老 uni-app 离线基座的签名密钥，使新 Flutter 版可直接覆盖升级已安装的老 app。
        // keyAlias / 密码来自 legacy/Android-SDK 的 simpleDemo 模块（alias=my-alias）。
        create("release") {
            keyAlias = "my-alias"
            keyPassword = "lyc131429"
            storeFile = file("../../legacy/key.jks")
            storePassword = "lyc131429"
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

flutter {
    source = "../.."
}
