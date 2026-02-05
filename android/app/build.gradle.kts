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
// Analytics 配置读取
// =============================================================================
// 读取 YAML 配置文件
import org.yaml.snakeyaml.Yaml
import java.util.Properties
val analyticsConfigFile = file("../../config/analytics_config.yaml")
val analyticsConfig = if (analyticsConfigFile.exists()) {
    Yaml().load<Map<String, Any>>(analyticsConfigFile.readText())
} else {
    mapOf<String, Any>()
}

// 读取环境变量文件（密钥）
val envFile = file("../../config/.env.analytics")
val envProps = Properties()
if (envFile.exists()) {
    envFile.inputStream().use { envProps.load(it) }
}

// 提取配置值
fun getAnalyticsConfig(path: String, default: String = ""): String {
    var current: Any? = analyticsConfig
    for (key in path.split(".")) {
        current = (current as? Map<*, *>)?.get(key)
    }
    return current?.toString() ?: default
}

val analyticsEnabled = getAnalyticsConfig("enabled", "true").toBoolean()
val analyticsMarket = getAnalyticsConfig("market", "china")
val umengChannel = getAnalyticsConfig("providers.china.umeng.channel", "GooglePlay")
val umengAppKey = envProps.getProperty("UMENG_ANDROID_KEY", "")

// 读取 SDK 版本号（支持嵌套路径）
fun getNestedConfig(path: String, default: String = ""): String {
    var current: Any? = analyticsConfig
    for (key in path.split(".")) {
        current = (current as? Map<*, *>)?.get(key)
    }
    return current?.toString() ?: default
}

val umengCommonVersion = getNestedConfig("providers.china.umeng.sdk_versions.common", "9.6.8")
val umengAsmsVersion = getNestedConfig("providers.china.umeng.sdk_versions.asms", "1.8.3")
val umengAbtestVersion = getNestedConfig("providers.china.umeng.sdk_versions.abtest", "1.0.3")

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
