/// 隐私政策统一数据源
///
/// ====================================================================
/// ⚠️  所有隐私政策内容均在此文件维护，修改一次，三处同步生效：
///   1. 应用首次启动弹窗（privacy_policy_dialog.dart）
///   2. 关于页面的隐私政策页（privacy_policy_page.dart）
///   3. 服务器 HTML 页面（运行 dart run scripts/generate_privacy_html.dart 重新生成）
/// ====================================================================
///
/// 修改流程：
///   1. 编辑本文件中的 sections / dialogBody / 元信息
///   2. 运行 `dart run scripts/generate_privacy_html.dart`
///   3. 将生成的 docs/privacy_policy.html 部署到服务器
///   4. 更新 [version]（若需触发已有用户重新同意）
library;

/// 一条内容段落（标题 + 可选正文 + 可选条目列表 + 可选尾注）
class PrivacySection {
  final String title;
  final String? content;
  final List<String> items;
  final String? footer;

  /// true 时渲染为高亮承诺卡片（通常为最后一节）
  final bool isCard;

  const PrivacySection({
    required this.title,
    this.content,
    this.items = const [],
    this.footer,
    this.isCard = false,
  });
}

/// 隐私政策全部内容
abstract final class PrivacyPolicyContent {
  // ── 元信息 ──────────────────────────────────────────────────────────
  /// 当前版本号；修改隐私政策实质内容时请同步升级，
  /// PrivacyConsentService 会据此判断是否需要用户重新同意。
  static const String version = '1.0.2';
  static const String lastUpdated = '2026年2月';
  static const String appName = '易览文件';
  static const String developerName = '北京光启东方科技有限公司';
  static const String contactEmail = 'easyfile@guangqitech.cn';
  static const String packageName = 'com.guangqi.easyfile';

  // ── 弹窗摘要（首次启动同意弹窗中展示的简短说明） ────────────────
  /// 此摘要故意简短，用户点击"《隐私政策》"可跳转到完整页面。
  static const String dialogIntro = '在使用我们的服务前，请您仔细阅读并充分理解';

  static const String dialogBody = '我们将严格按照您同意的各项条款使用您的个人信息，以便为您提供更好的服务。'
      '我们会收集和使用以下必要信息：\n\n'
      '• 设备标识符（OAID / Android ID）：由友盟 SDK 用于安装量去重统计\n'
      '• 设备信息（品牌、型号、系统版本）：用于崩溃分析与兼容性改善\n'
      '• 存储权限：用于文件管理核心功能\n'
      '• 已安装应用列表：用于应用管理功能\n\n'
      '我们承诺：\n'
      '• 您的文件内容仅保留在本地设备，不上传\n'
      '• 不会将您的信息出售给第三方\n'
      '• 您可以随时撤回权限或卸载应用删除全部数据\n\n'
      '点击"同意并继续"即表示您已阅读并同意上述协议。';

  // ── 完整正文（关于页面 & HTML 共用） ────────────────────────────────
  static const List<PrivacySection> sections = [
    PrivacySection(
      title: '主体信息与声明',
      content: '$appName（以下简称"本应用"）由$developerName'
          '（以下简称"我们"）开发并运营，适用于所有包名为 $packageName 的渠道版本。',
      items: [
        '开发者主体：$developerName',
        '统一展示名称：$developerName',
      ],
      footer: '本隐私政策适用于您安装、使用或升级本应用期间发生的个人信息处理活动。',
    ),
    PrivacySection(
      title: '1. 信息收集',
      content: '本应用是一款完全本地化的文件管理工具，我们坚持最小化数据收集原则：',
      items: [
        '本应用自身不收集可直接识别您个人身份的信息',
        '不上传您的文件内容或文件列表',
        '不记录您的具体使用行为',
        '默认不启用账号体系，也不提供云端同步',
        '除依法依规保存的必要日志外，数据均保留在设备本地',
      ],
      footer: '注：为统计应用安装量与崩溃情况，本应用集成了友盟+统计 SDK，'
          '该 SDK 会采集设备标识符（Android ID、OAID）等信息，具体说明详见第6条。',
    ),
    PrivacySection(
      title: '2. 权限使用说明',
      content: '为了提供完整的文件管理功能，本应用可能申请以下系统权限：',
      items: [
        '存储权限：用于读取、管理设备上的文件和文件夹',
        '照片和视频权限（Android 13+）：用于访问图片和视频分类',
        '生物识别权限（可选）：用于隐私空间的指纹/面容解锁',
        '查询已安装应用权限（可选）：用于应用管理功能',
        '修改系统设置权限：仅用于视频播放时调节应用内亮度，退出播放器后自动恢复',
        '应用使用统计权限（可选）：用于应用管理功能展示各应用最近使用时间，识别闲置应用',
        'APK 安装权限：用于应用管理功能中安装用户主动选择的 APK 文件',
      ],
      footer: '权限仅用于实现对应功能且在本地执行，我们不会将相关数据分享给未在本政策中说明的第三方。',
    ),
    PrivacySection(
      title: '3. 数据存储与安全',
      items: [
        '应用设置、缓存、收藏等信息存储在您的设备本地',
        '隐私空间 PIN 码采用加密方式保存',
        '我们不会主动备份您的数据到云端',
        '卸载应用后，相关本地数据将被删除',
      ],
      footer: '我们遵循最小权限原则，并通过访问控制与加密手段降低数据被未经授权访问或泄露的风险。',
    ),
    PrivacySection(
      title: '4. 用户权利',
      content: '在符合法律法规的前提下，您可以随时行使以下权利：',
      items: [
        '访问：直接在应用中查看本地存储的数据',
        '更正：通过设置或删除重新生成数据来更正信息',
        '删除/清除：删除文件、清空隐私空间或卸载应用以删除全部本地数据',
        '撤回授权：在系统设置中关闭已授予的权限，或在隐私政策弹窗中选择不同意',
        '投诉与反馈：通过 $contactEmail 向我们反馈，我们将在 15 个工作日内回复',
      ],
    ),
    PrivacySection(
      title: '5. 账号与个性化服务',
      content: '当前版本不提供账号注册/登录功能，也没有个性化推荐、定向推送或自动化决策。'
          '不存在账号注销流程。如未来新增账号或个性化相关功能，我们会在上线前再次征得您的授权，'
          '并提供清晰的退出及注销路径。',
    ),
    PrivacySection(
      title: '6. 第三方 SDK 与数据共享',
      content: '为保障应用稳定性及统计安装量，我们仅在您同意隐私政策后初始化以下第三方 SDK，'
          '并遵循全国 SDK 管理服务平台的要求：',
      items: [
        '【SDK 名称】友盟+ 统计 SDK',
        '【提供方】北京锐讯灵通科技有限公司（友盟）',
        '【收集的个人信息类型】'
            '设备标识符：Android ID（系统生成的设备唯一标识符）、'
            'OAID（开放匿名设备标识符）；'
            '设备信息：品牌、型号、系统版本；'
            '网络信息：IP 地址、网络连接类型（Wi-Fi / 蜂窝）；'
            '应用运行信息：启动事件、崩溃堆栈',
        '【收集目的】区分不同设备以统计应用安装量、活跃用户数及渠道投放效果；'
            '采集崩溃堆栈用于排查与修复应用异常',
        '【收集方式】由友盟+ SDK 在应用启动时自动采集，'
            '通过 HTTPS 加密传输至友盟数据服务器，不采集您在本应用内处理的任何文件内容',
        '【隐私政策】https://www.umeng.com/policy',
      ],
      footer: '除上述 SDK 外，我们不会与其他第三方共享您的个人信息。'
          '若未来新增第三方组件，我们会更新本政策并再次征得您的授权。',
    ),
    PrivacySection(
      title: '7. 儿童隐私保护',
      content: '本应用面向普通用户，不以儿童为对象。我们不会故意收集 13 周岁以下儿童的信息。'
          '如您认为我们误收集了儿童信息，请通过 $contactEmail 联系我们，我们会在确认后尽快删除相关数据。',
    ),
    PrivacySection(
      title: '8. 隐私政策变更',
      content: '我们可能会根据业务发展或法律法规更新本政策。'
          '重大变更（如第三方 SDK 调整、信息收集目的改变等）会通过弹窗、站内提示或版本更新说明通知您。'
          '继续使用本应用即表示您接受更新后的政策。',
    ),
    PrivacySection(
      title: '9. 联系我们',
      content: '如对本隐私政策有任何疑问、投诉或建议，可通过 $contactEmail 联系我们，'
          '邮件主题请注明"隐私政策相关咨询"，以便我们快速处理。',
    ),
    PrivacySection(
      title: '我们的承诺',
      items: [
        '您的文件仅保留在本地设备',
        '任一第三方 SDK 均需在您授权后才会启用',
        '若未来新增账号或推送功能，将提供清晰的退出机制',
        '我们持续投入资源提升数据与隐私安全',
      ],
      isCard: true,
    ),
  ];
}
