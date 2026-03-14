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

// 读取签名配置
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
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

    // 签名配置
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = file(keystoreProperties.getProperty("storeFile") ?: "upload-keystore.jks")
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // 使用正式签名配置（用于应用市场发布）
            signingConfig = signingConfigs.getByName("release")
            // 启用混淆和优化
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        buildConfig = true
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

// 自定义输出文件名（在构建后重命名）
afterEvaluate {
    tasks.register("renameApk") {
        doLast {
            val vName = flutter.versionName
            val vCode = flutter.versionCode
            val buildDir = layout.buildDirectory.get().asFile
            val apkDir = File(buildDir, "outputs/apk/release")

            if (apkDir.exists()) {
                apkDir.listFiles()?.filter { it.name.endsWith(".apk") }?.forEach { apkFile ->
                    val buildType = when {
                        apkFile.name.contains("release", ignoreCase = true) -> "release"
                        apkFile.name.contains("debug", ignoreCase = true) -> "debug"
                        else -> "unknown"
                    }
                    val newName = "EasyFile-v${vName}-build${vCode}-${buildType}.apk"
                    val newFile = File(apkDir, newName)
                    if (apkFile.renameTo(newFile)) {
                        println("✓ Renamed ${apkFile.name} to $newName")
                    }
                }
            }
        }
    }

    tasks.matching { it.name == "assembleRelease" }.configureEach {
        finalizedBy("renameApk")
    }
}
