import 'package:flutter/material.dart';

/// 最简单的启动页 - 立即显示内容，后台异步初始化
class SimpleStartPage extends StatefulWidget {
  const SimpleStartPage({super.key});

  @override
  State<SimpleStartPage> createState() => _SimpleStartPageState();
}

class _SimpleStartPageState extends State<SimpleStartPage> {
  @override
  void initState() {
    super.initState();
    // 立即导航到主页面，不等待任何初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushReplacementNamed(context, '/fileBrowser');
    });
  }

  @override
  Widget build(BuildContext context) {
    // 最简单的白色页面
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}