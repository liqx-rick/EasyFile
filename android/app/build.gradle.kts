plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// =============================================================================
// Analytics 配置读取依赖
// =============================================================================
buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        classpath("org.yaml:snakeyaml:2.0")
    }
}

// =============================================================================
// Analytics 配置读取（优化版）
// =============================================================================
import org.yaml.snakeyaml.Yaml
import java.util.Properties

// 延迟加载配置文件（减少不必要的 I/O）
val analyticsConfigFile = file("../../config/analytics_config.yaml")
val analyticsConfig: Map<String, Any> by lazy {
    if (analyticsConfigFile.exists()) {
        try {
            Yaml().load<Map<String, Any>>(analyticsConfigFile.readText()) ?: emptyMap()
        } catch (e: Exception) {
            println("Warning: Failed to load analytics config: ${e.message}")
            emptyMap()
        }
    } else {
        emptyMap()
    }
}

// 延迟加载环境变量文件
val envFile = file("../../config/.env.analytics")
val envProps: Properties by lazy {
    Properties().apply {
        if (envFile.exists()) {
            try {
                envFile.inputStream().use { load(it) }
            } catch (e: Exception) {
                println("Warning: Failed to load env file: ${e.message}")
            }
        }
    }
}

// 统一的配置提取函数（优化版 - 合并两个重复函数）
fun getAnalyticsConfig(path: String, default: String = ""): String {
    var current: Any? = analyticsConfig
    for (key in path.split(".")) {
        current = (current as? Map<*, *>)?.get(key) ?: return default
    }
    return current?.toString() ?: default
}

// 提取配置值（由于 lazy，只在实际使用时才加载）
val analyticsEnabled = getAnalyticsConfig("enabled", "true").toBoolean()
val analyticsMarket = getAnalyticsConfig("market", "china")
val umengChannel = getAnalyticsConfig("providers.china.umeng.channel", "GooglePlay")
val umengAppKey = envProps.getProperty("UMENG_ANDROID_KEY", "")

val umengCommonVersion = getAnalyticsConfig("providers.china.umeng.sdk_versions.common", "9.6.8")
val umengAsmsVersion = getAnalyticsConfig("providers.china.umeng.sdk_versions.asms", "1.8.3")
val umengAbtestVersion = getAnalyticsConfig("providers.china.umeng.sdk_versions.abtest", "1.0.3")

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
            abiFilters += listOf("arm64-v8a")
        }

        // Analytics 配置注入到 BuildConfig
        buildConfigField("boolean", "ANALYTICS_ENABLED", "$analyticsEnabled")
        buildConfigField("String", "ANALYTICS_MARKET", "\"$analyticsMarket\"")
        buildConfigField("String", "UMENG_APP_KEY", "\"$umengAppKey\"")
        buildConfigField("String", "UMENG_CHANNEL", "\"$umengChannel\"")
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
            abiFilters("arm64-v8a")

            // ======== CMake 编译性能优化 ========
            // 注意：并行编译由 Ninja 自动处理，无需手动指定

            // 启用 ccache 加速 C/C++ 编译（如果系统安装了 ccache）
            // arguments("-DCMAKE_C_COMPILER_LAUNCHER=ccache", "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache")

            // 优化编译速度（Debug 模式使用 -O1 而不是 -O0）
            cFlags("-O1")
            cppFlags("-O1")

            // 减少调试信息大小（加快链接速度）
            cFlags("-g1")
            cppFlags("-g1")
        }
    }

    buildTypes {
        release {
            // 使用 debug 签名配置，生产环境需要配置正式签名
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    // 自定义输出文件名
    applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            output.outputFileName = "EasyFile-v${variant.versionName}-build${variant.versionCode}-${variant.buildType.name}.apk"
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    // ExifInterface 支持（用于读取照片 EXIF 信息）
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    // Umeng Analytics SDK（版本号从 config/analytics_config.yaml 读取）
    implementation("com.umeng.umsdk:common:$umengCommonVersion")        // 友盟基础组件
    implementation("com.umeng.umsdk:asms:$umengAsmsVersion")          // 反作弊组件
    // implementation("com.umeng.umsdk:abtest:$umengAbtestVersion")     // ABTest 组件（可选，暂未在 Maven 仓库）
}
