# EasyFile 回收站模块 说明书（模版E）

---

## 1. 模块定位与入口
- 页面入口：`lib/ui/pages/trash_page.dart`，类 `TrashPage`。
- 服务入口：`lib/core/services/app_trash_manager.dart`，类 `AppTrashManager`。
- 数据结构：`lib/data/models/app_trash_item.dart`，类 `AppTrashItem`。

## 2. 功能概述
- 提供应用级回收站功能，支持软删除、恢复、永久删除、清空、自动清理。
- 所有操作均基于数据库与物理文件双重管理，支持跨分区移动、进度反馈。

## 3. 主要实现点
### 3.1 页面与交互
- `TrashPage`：展示回收站文件列表、统计信息、恢复/删除/清空操作。
- 支持空状态、统计卡片、详情弹窗、操作确认。

### 3.2 服务与核心逻辑
- `AppTrashManager`：
  - 初始化回收站目录，恢复未完成任务。
  - 软删除：`markFilesAsDeleted()`，批量标记为deleted，后台异步移动到回收站。
  - 文件移动：优先rename，跨分区降级copy+delete，支持文件夹递归。
  - 恢复：`restoreFile()`，优先原位置，冲突自动重命名，降级到父目录或默认目录。
  - 永久删除：`deleteFilePermanently()`，物理删除+数据库清理。
  - 清空：`emptyTrash()`，批量永久删除所有回收站文件。
  - 自动清理：`cleanExpiredFiles()`，按保留天数批量清理过期文件。
  - 查询：`getAllItems()`、`getStatistics()`、`getExpiringSoonItems()`。

### 3.3 数据结构
- `AppTrashItem`：记录UUID、回收站路径、原始路径、文件名、大小、MIME类型、删除时间、缩略图路径。
- 支持过期判断、类型分类、大小格式化。

## 4. 关键流程
### 4.1 删除文件
- 用户删除文件 → `markFilesAsDeleted()` → 数据库标记 → 加入后台队列 → 异步移动到回收站。

### 4.2 恢复文件
- 回收站页面点击“恢复” → `restoreFile()` → 优先原位置，冲突自动重命名，降级到父目录或默认目录 → 数据库清理。

### 4.3 永久删除
- 回收站页面点击“删除” → `deleteFilePermanently()` → 物理删除+数据库清理。

### 4.4 清空回收站
- 回收站页面点击“一键清空” → `emptyTrash()` → 批量永久删除所有回收站文件。

### 4.5 自动清理
- 应用启动时自动执行 `cleanExpiredFiles()`，按保留天数批量清理。

## 5. 主要配置项
- 回收站目录、保留天数、默认恢复目录、MIME类型推断。

## 6. 典型调用链
- UI 触发删除 → `AppTrashManager.markFilesAsDeleted()` → 后台移动 → 回收站页面展示 → 恢复/删除/清空操作调用 `AppTrashManager`。

## 7. 其它说明
- 所有功能 strictly based on EasyFile 源码实现，未做任何主观推断。
- 详细字段、方法、流程请参见上述各实现文件。

---

（本说明 strictly based on EasyFile 源码，未做任何主观推断）
