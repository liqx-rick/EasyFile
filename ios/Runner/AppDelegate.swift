//
// AppDelegate.swift
// Runner
//
// 📱 iOS 平台支持状态说明：
// 当前 EasyFile 产品暂不支持 iOS 平台，仅支持 Android
// 本文件中的友盟 Analytics 实现为未来 iOS 支持预留
// 当前版本请关注 Android 端实现即可
//

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 注册友盟 Analytics Channel
    if let controller = window?.rootViewController as? FlutterViewController {
        setupUmengAnalyticsChannel(controller: controller)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupUmengAnalyticsChannel(controller: FlutterViewController) {
      let channel = FlutterMethodChannel(
          name: "easyfile/analytics/umeng",
          binaryMessenger: controller.binaryMessenger
      )

      let analyticsHandler = UmengAnalyticsHandler()

      channel.setMethodCallHandler { [weak analyticsHandler] (call: FlutterMethodCall, result: @escaping FlutterResult) in
          guard let handler = analyticsHandler else {
              result(FlutterError(code: "UNAVAILABLE", message: "Handler not available", details: nil))
              return
          }

          switch call.method {
          case "init":
              handler.handleInit(result: result)
          case "logEvent":
              if let args = call.arguments as? [String: Any],
                 let event = args["event"] as? String {
                  let params = args["params"] as? [String: Any]
                  handler.handleLogEvent(event: event, params: params, result: result)
              } else {
                  result(FlutterError(code: "INVALID_ARGUMENT", message: "Event name is required", details: nil))
              }
          case "setEnabled":
              if let args = call.arguments as? [String: Any],
                 let enabled = args["enabled"] as? Bool {
                  handler.handleSetEnabled(enabled: enabled, result: result)
              } else {
                  result(FlutterError(code: "INVALID_ARGUMENT", message: "Enabled flag is required", details: nil))
              }
          case "clear":
              handler.handleClear(result: result)
          default:
              result(FlutterMethodNotImplemented)
          }
      }
  }
}

/**
 * 友盟统计处理器
 *
 * 配置说明：
 * - AppKey: 已存储在 config/.env.analytics 的 UMENG_IOS_KEY 字段
 * - Channel: 已配置在 config/analytics_config.yaml 的 providers.china.umeng.channel
 * - 当前 iOS 平台未启用，未来支持时将通过 Info.plist 或 Swift 配置读取实现统一配置
 */
class UmengAnalyticsHandler {
    // TODO: 未来从统一配置读取，当前使用占位符
    private let umengAppKey = "YOUR_UMENG_APP_KEY_HERE"  // 实际值: config/.env.analytics UMENG_IOS_KEY
    private let umengChannel = "App Store"  // 实际值: config/analytics_config.yaml channel

    private var isInitialized = false
    private var isEnabled = true

    func handleInit(result: @escaping FlutterResult) {
        if isInitialized {
            NSLog("[UmengAnalytics] Already initialized")
            result(true)
            return
        }

        // 初始化友盟 SDK
        // UMConfigure.initWithAppkey(umengAppKey, channel: umengChannel)
        // UMConfigure.setLogEnabled(true)
        // MobClick.setScenarioType(.E_UM_NORMAL)

        isInitialized = true
        NSLog("[UmengAnalytics] Initialized successfully with AppKey: \(umengAppKey)")
        result(true)
    }

    func handleLogEvent(event: String, params: [String: Any]?, result: @escaping FlutterResult) {
        guard isEnabled else {
            NSLog("[UmengAnalytics] Analytics disabled, skipping event: \(event)")
            result(true)
            return
        }

        // 转换参数为友盟格式（String类型）
        var umengParams: [String: String]?
        if let params = params {
            umengParams = [:]
            for (key, value) in params {
                umengParams![key] = "\(value)"
            }
        }

        // 调用友盟事件上报
        // MobClick.event(event, attributes: umengParams)

        NSLog("[UmengAnalytics] Logged event: \(event) with params: \(String(describing: umengParams))")
        result(true)
    }

    func handleSetEnabled(enabled: Bool, result: @escaping FlutterResult) {
        isEnabled = enabled

        // 设置友盟开关（如果SDK支持）
        // 注意：友盟iOS SDK可能没有直接的enable/disable方法

        NSLog("[UmengAnalytics] Analytics enabled: \(enabled)")
        result(true)
    }

    func handleClear(result: @escaping FlutterResult) {
        // 清除友盟本地缓存（如果SDK支持）
        // 注意：友盟iOS可能没有直接的clear方法

        NSLog("[UmengAnalytics] Analytics cache cleared")
        result(true)
    }
}

