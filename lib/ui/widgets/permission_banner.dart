import 'package:flutter/material.dart';

/// 权限提示横幅组件
///
/// 在页面顶部显示非阻塞式的权限未授予提示，用户可以点击进行授权。
/// 使用橙色背景和警告图标，显眼但不会阻塞主内容显示。
class PermissionBanner extends StatelessWidget {
  /// 点击横幅时的回调，通常用于跳转到权限请求流程
  final VoidCallback onTap;

  const PermissionBanner({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade700,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '您还没有授权访问文件系统，点这里进行授权',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
