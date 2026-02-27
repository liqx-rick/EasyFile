# EasyFile 隐私空间模块 说明书（模版E）

---

## 1. 模块定位与入口
- 页面入口：`lib/ui/pages/privacy_auth_page.dart`（身份验证）、`lib/ui/pages/privacy_space_page.dart`（隐私空间主页）。
- 服务入口：`lib/core/services/privacy_service.dart`，类 `PrivacyService`。

## 2. 功能概述
- 提供隐私空间（私密文件保险箱）功能，支持文件移入/移出/删除。
- 支持 PIN 验证与生物识别（指纹/人脸/虹膜）双重认证。
- 隐私空间文件物理隔离，原始路径元数据管理，支持恢复到原位置。
- 支持隐私空间重置（清空所有文件与配置）。

## 3. 主要实现点
### 3.1 页面与交互
- `PrivacyAuthPage`：负责 PIN/生物识别验证，认证通过后进入隐私空间。
- `PrivacySpacePage`：展示隐私文件列表，支持分类、网格/列表视图、文件操作（打开、移出、删除）。
- 支持帮助引导、设置入口、空状态引导。

### 3.2 服务与核心逻辑
- `PrivacyService`：
  - 隐私空间初始化、PIN 设置与验证、重置。
  - 生物识别能力检测与认证（集成 `local_auth`）。
  - 文件移入：物理移动到 App 私有目录，记录原始路径，支持跨分区降级复制+删除。
  - 文件移出：优先恢复到原位置，若不可用则用户选择目标目录，支持同名冲突处理。
  - 文件删除：彻底删除，支持原生方法避免触发系统回收站。
  - 文件列表：按修改时间降序，支持分类统计。
  - 元数据管理：`.metadata.json` 记录文件名与原始路径映射。
  - 隐私空间重置：删除所有文件与配置。

### 3.3 安全与认证
- PIN 验证：SHA-256 哈希存储，支持错误锁定机制。
- 生物识别：优先高安全级别（指纹/人脸/虹膜），支持 Android/iOS。
- 会话管理：认证成功后标记会话有效，支持快速免验证。

### 3.4 文件操作
- 移入：`moveToPrivate(FileItem)`，移动文件到隐私空间，记录原始路径。
- 移出：`moveFromPrivate(FileItem, {userSelectedPath})`，优先恢复原位置，支持用户自选。
- 删除：`deletePrivateFile(FileItem)`，彻底删除。
- 列表：`getPrivateFiles()`，返回所有隐私文件。

## 4. 关键流程
### 4.1 认证与进入
- 用户访问隐私空间，先经 `PrivacyAuthPage` 验证 PIN 或生物识别。
- 认证通过后进入 `PrivacySpacePage`，展示文件列表。

### 4.2 文件移入
- 文件浏览器长按文件 → 选择“移入隐私空间” → 验证 → 物理移动文件 → 记录原始路径。

### 4.3 文件移出
- 隐私空间长按文件 → 选择“移出隐私空间” → 优先恢复原位置，若不可用则用户选择目标目录。

### 4.4 文件删除
- 隐私空间长按文件 → 选择“删除” → 彻底删除文件。

### 4.5 重置隐私空间
- 设置页可重置隐私空间，删除所有文件与配置。

## 5. 主要配置项
- PIN 长度（4-6位）、生物识别开关、会话有效期。

## 6. 典型调用链
- UI 触发认证 → `PrivacyService.verifyPin()`/`authenticateWithBiometric()` → 认证通过 → `PrivacySpacePage` 展示文件 → 文件操作调用 `PrivacyService`。

## 7. 其它说明
- 所有功能 strictly based on EasyFile 源码实现，未做任何主观推断。
- 详细字段、方法、流程请参见上述各实现文件。

---

（本说明 strictly based on EasyFile 源码，未做任何主观推断）
