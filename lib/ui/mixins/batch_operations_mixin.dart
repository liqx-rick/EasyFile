import 'package:flutter/material.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';

/// 批量操作服务混入
///
/// 提供统一的 BatchOperationsService 创建和初始化逻辑
/// 避免在每个页面重复实现相同的服务初始化代码
///
/// 使用方法：
/// ```dart
/// class MyPageState extends State<MyPage> 
///     with EditModeMixin, BatchOperationsMixin {
///   
///   late final FilePresenter _presenter;
///   late final FileViewModel _viewModel;
///   
///   @override
///   FilePresenter get presenter => _presenter;
///   
///   @override
///   FileViewModel get viewModel => _viewModel;
///   
///   @override
///   Future<void> refreshData() async {
///     // 刷新页面数据的逻辑
///   }
///   
///   Widget buildBottomBar() {
///     final batchService = createBatchService();
///     return SelectionBottomBar(
///       onDelete: () => batchService.batchDelete(context, selected),
///       // ...
///     );
///   }
/// }
/// ```
mixin BatchOperationsMixin<T extends StatefulWidget> on EditModeMixin<T> {
  /// 子类必须提供 FilePresenter 实例
  FilePresenter get presenter;

  /// 子类必须提供 FileViewModel 实例
  FileViewModel get viewModel;

  /// 子类必须实现刷新数据的方法
  Future<void> refreshData();

  /// 创建 BatchOperationsService 实例
  ///
  /// 统一的初始化逻辑：
  /// - 自动绑定 presenter 和 viewModel
  /// - 自动配置刷新回调
  /// - 自动配置退出选择模式的回调（使用 addPostFrameCallback 确保安全）
  BatchOperationsService createBatchService() {
    return BatchOperationsService(
      viewModel: viewModel,
      presenter: presenter,
      onRefresh: refreshData,
      onExitSelectionMode: () {
        // 延迟到下一帧执行，确保所有 notifyListeners() 完成
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          exitEditMode();
        });
      },
    );
  }
}
