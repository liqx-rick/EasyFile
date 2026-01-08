import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/app_scanner_config.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/storage/local_config_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppScannerConfig', () {
    late AppScannerConfig appScannerConfig;

    setUp(() async {
      // 初始化测试环境
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // 使用 LocalConfigStorage
      final storage = LocalConfigStorage(prefs);
      appScannerConfig = AppScannerConfig(storage);
    });

    test('should get default app config', () async {
      // 获取微信配置
      final wechatConfig = await appScannerConfig.getAppConfig('wechat');

      expect(wechatConfig, isNotNull);
      expect(wechatConfig!.appKey, 'wechat');
      expect(wechatConfig.appName, '微信');
      expect(wechatConfig.packageNames, contains('com.tencent.mm'));
      expect(wechatConfig.enabled, true);
      expect(wechatConfig.priority, 1);
    });

    test('should get all enabled apps', () async {
      final enabledApps = await appScannerConfig.getEnabledApps();

      // 默认有5个应用：微信、QQ、Telegram、WPS、钉钉
      expect(enabledApps.length, 5);

      // 验证优先级排序（微信和QQ优先级为1，其他为2）
      expect(enabledApps[0].priority, 1); // 微信或QQ
      expect(enabledApps[1].priority, 1); // 微信或QQ
    });

    test('should set app enabled/disabled', () async {
      // 禁用微信
      await appScannerConfig.setAppEnabled('wechat', false);

      // 验证微信被禁用
      final wechatConfig = await appScannerConfig.getAppConfig('wechat');
      expect(wechatConfig!.enabled, false);

      // 验证微信不在启用列表中
      final enabledApps = await appScannerConfig.getEnabledApps();
      expect(enabledApps.any((app) => app.appKey == 'wechat'), false);

      // 重新启用微信
      await appScannerConfig.setAppEnabled('wechat', true);
      final enabledApps2 = await appScannerConfig.getEnabledApps();
      expect(enabledApps2.any((app) => app.appKey == 'wechat'), true);
    });

    test('should update app priority', () async {
      // 设置微信优先级为10
      await appScannerConfig.setAppPriority('wechat', 10);

      // 验证优先级已更新
      final wechatConfig = await appScannerConfig.getAppConfig('wechat');
      expect(wechatConfig!.priority, 10);

      // 验证排序改变（优先级10应该排在最后）
      final enabledApps = await appScannerConfig.getEnabledApps();
      expect(enabledApps.last.appKey, 'wechat');
    });

    test('should add custom app', () async {
      // 创建自定义应用配置
      final customApp = AppConfigData(
        appKey: 'custom_app',
        appName: '自定义应用',
        description: '测试自定义应用',
        packageNames: ['com.example.custom'],
        folderKeywords: ['CustomApp'],
        enabled: true,
        priority: 5,
      );

      // 添加自定义应用
      await appScannerConfig.addCustomApp(customApp);

      // 验证自定义应用已添加
      final customConfig = await appScannerConfig.getAppConfig('custom_app');
      expect(customConfig, isNotNull);
      expect(customConfig!.appName, '自定义应用');
      expect(customConfig.packageNames, contains('com.example.custom'));

      // 验证自定义应用是否已启用（默认应该是 true）
      expect(customConfig.enabled, true);
    });

    test('should remove custom app', () async {
      // 添加然后移除自定义应用
      final customApp = AppConfigData(
        appKey: 'custom_app',
        appName: '自定义应用',
        description: '测试自定义应用',
        packageNames: ['com.example.custom'],
        folderKeywords: ['CustomApp'],
        enabled: true,
        priority: 5,
      );

      await appScannerConfig.addCustomApp(customApp);

      // 验证添加成功
      var customConfig = await appScannerConfig.getAppConfig('custom_app');
      expect(customConfig, isNotNull);

      // 移除自定义应用
      await appScannerConfig.removeCustomApp('custom_app');

      // 验证已移除
      customConfig = await appScannerConfig.getAppConfig('custom_app');
      expect(customConfig, isNull);
    });

    test('should reset app to default config', () async {
      // 修改微信配置
      await appScannerConfig.setAppEnabled('wechat', false);
      await appScannerConfig.setAppPriority('wechat', 10);

      // 验证修改生效
      var wechatConfig = await appScannerConfig.getAppConfig('wechat');
      expect(wechatConfig!.enabled, false);
      expect(wechatConfig.priority, 10);

      // 重置为默认配置
      await appScannerConfig.resetAppConfig('wechat');

      // 验证已恢复默认值
      wechatConfig = await appScannerConfig.getAppConfig('wechat');
      expect(wechatConfig!.enabled, true);
      expect(wechatConfig.priority, 1);
    });

    test('should persist config across instances', () async {
      // 禁用微信
      await appScannerConfig.setAppEnabled('wechat', false);

      // 创建新实例（模拟应用重启）
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalConfigStorage(prefs);
      final newInstance = AppScannerConfig(storage);

      // 验证配置已持久化
      final wechatConfig = await newInstance.getAppConfig('wechat');
      expect(wechatConfig!.enabled, false);
    });

    test('should merge remote configs', () async {
      // 模拟远程配置（Map<String, dynamic>格式）
      final remoteConfigs = {
        'wechat': {
          'appKey': 'wechat',
          'appName': '微信（更新）',
          'description': '远程更新的微信配置',
          'packageNames': ['com.tencent.mm'],
          'folderKeywords': ['WeiXin'],
          'enabled': true,
          'priority': 1,
        },
        'new_app': {
          'appKey': 'new_app',
          'appName': '新应用',
          'description': '远程推送的新应用',
          'packageNames': ['com.example.newapp'],
          'folderKeywords': ['NewApp'],
          'enabled': true,
          'priority': 3,
        },
      };

      // 合并远程配置
      await appScannerConfig.mergeRemoteConfigs(remoteConfigs);

      // 验证微信配置已更新
      final wechatConfig = await appScannerConfig.getAppConfig('wechat');
      expect(wechatConfig!.appName, '微信（更新）');
      expect(wechatConfig.description, '远程更新的微信配置');

      // 验证新应用已添加
      final newAppConfig = await appScannerConfig.getAppConfig('new_app');
      expect(newAppConfig, isNotNull);
      expect(newAppConfig!.appName, '新应用');
    });

    test('should validate app config', () {
      // 有效配置（有包名）
      final validConfig1 = AppConfigData(
        appKey: 'test1',
        appName: '测试1',
        packageNames: ['com.example.test'],
        folderKeywords: [],
      );
      expect(validConfig1.isValid, true);

      // 有效配置（有文件夹关键字）
      final validConfig2 = AppConfigData(
        appKey: 'test2',
        appName: '测试2',
        packageNames: [],
        folderKeywords: ['TestFolder'],
      );
      expect(validConfig2.isValid, true);

      // 无效配置（包名和文件夹关键字都为空）
      final invalidConfig = AppConfigData(
        appKey: 'test3',
        appName: '测试3',
        packageNames: [],
        folderKeywords: [],
      );
      expect(invalidConfig.isValid, false);
    });
  });

  group('AppConfig Integration', () {
    setUp(() async {
      // 初始化 AppConfig
      SharedPreferences.setMockInitialValues({});
      await AppConfig.instance.initialize();
    });

    test('should access app scanner config via AppConfig', () async {
      // 通过 AppConfig 访问应用扫描配置
      final wechatConfig =
          await AppConfig.instance.appScanner.getAppConfig('wechat');

      expect(wechatConfig, isNotNull);
      expect(wechatConfig!.appKey, 'wechat');
      expect(wechatConfig.appName, '微信');
    });

    test('should support runtime configuration changes', () async {
      // 运行时禁用QQ
      await AppConfig.instance.appScanner.setAppEnabled('qq', false);

      // 验证改变生效
      final enabledApps = await AppConfig.instance.appScanner.getEnabledApps();
      expect(enabledApps.any((app) => app.appKey == 'qq'), false);

      // 运行时调整Telegram优先级
      await AppConfig.instance.appScanner.setAppPriority('telegram', 1);

      // 验证优先级改变
      final telegramConfig =
          await AppConfig.instance.appScanner.getAppConfig('telegram');
      expect(telegramConfig!.priority, 1);
    });
  });
}
