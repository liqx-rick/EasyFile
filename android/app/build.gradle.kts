plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.guangqi.easyfile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.guangqi.easyfile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // NDK 配置 - 只打包真实Android设备需要的ARM架构
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }
    
    // CMake 外部构建配置 - FFI Native 层
    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    
    // 限制CMake只编译指定的ABI
    defaultConfig.externalNativeBuild {
        cmake {
            abiFilters("arm64-v8a", "armeabi-v7a")
        }
    }

    buildTypes {
        release {
            // 使用 debug 签名配置，生产环境需要配置正式签名
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    // ExifInterface 支持（用于读取照片 EXIF 信息）
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}