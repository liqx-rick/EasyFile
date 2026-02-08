# 软著申请源代码文档生成工具

本工具用于自动生成符合中国版权保护中心要求的软著申请源代码文档（Word格式）。

## 功能特点

✅ **直接生成Word文档**
- 无需中间步骤，直接从源码生成Word
- 保留完整源代码，不做任何修改
- 便于手动调整格式和内容

✅ **精确格式控制**
- 自动添加页眉：软件名称 + 页码
- 使用等宽字体（Consolas 10号）
- 生成标准A4 Word文档
- 页面设置：上下边距2.5cm，左右边距2cm

✅ **突出核心特色**
- **智能推荐系统**（根据应用动态推荐文件分类、重复文件检测）
- **快捷访问管理**（智能文件夹检测、多级缓存优化）
- 完整架构展示（从入口到核心业务）

## 生成内容

### 前30页
包含5个核心文件（约2733行）：
- **main.dart** - 应用初始化入口
- **app.dart** - 应用壳层、权限管理
- **locator.dart** - 依赖注入配置
- **quick_access_section.dart** - 快捷访问UI与缓存策略
- **quick_access_presenter.dart** - 快捷访问业务逻辑

### 后30页
包含4个核心文件（约2837行）：
- **recommendation_service.dart** - 推荐服务核心
- **duplicate_files_recommendation_engine.dart** - 重复文件推荐引擎
- **recommendation_card.dart** - 推荐卡片数据模型
- **recommend_aggregate_page.dart** - 推荐聚合页面

## 使用方法

### 前置条件

- Windows系统
- PowerShell 5.1+
- Microsoft Word（用于生成Word文档）

### 快速开始

```powershell
cd scripts
.\generate_copyright_word.ps1
```

生成的Word文档位于：`Copyright_Application_Documents/`
- `Copyright_SourceCode_Front30.docx` - 前30页源代码
- `Copyright_SourceCode_Back30.docx` - 后30页源代码

### 高级选项

#### 仅生成前30页
```powershell
.\generate_copyright_word.ps1 -GenerateFront
```

#### 仅生成后30页
```powershell
.\generate_copyright_word.ps1 -GenerateBack
```

## 目录结构

```
easyfile/
├── scripts/
│   ├── generate_copyright_word.ps1     # Word文档生成脚本
│   └── README_COPYRIGHT.md             # 本文件
└── Copyright_Application_Documents/
    ├── Copyright_SourceCode_Front30.docx   # 前30页Word文档
    └── Copyright_SourceCode_Back30.docx    # 后30页Word文档
```

## 后续处理

生成Word文档后，需要手动调整以满足版权中心要求：

### 必须完成的调整

1. **调整页数**
   - 前30页和后30页文档各需调整为恰好30页
   - 当前生成的文档约48-50页，需要压缩

2. **压缩页数的方法**
   - 删除不必要的注释
   - 调整行间距（从1.0调整到1.15-1.3）
   - 适当增加页边距（上下2.5→3cm）
   - 删除过多的空行

3. **修改文本为中文**
   - 页眉左侧改为："易览文件（EasyFile） v1.0.0"
   - 文件名前缀改为："代码文件：filename.dart"

4. **重命名文件**
   - `Copyright_SourceCode_Front30.docx` → `软著申请_源代码_前30页.docx`
   - `Copyright_SourceCode_Back30.docx` → `软著申请_源代码_后30页.docx`

### 质量检查

提交前确认：
- ✅ 前30页恰好30页
- ✅ 后30页恰好30页（页码应为31-60）
- ✅ 页眉格式正确，包含中文软件名和页码
- ✅ 每页不少于50行（结束页除外）
- ✅ 代码完整、格式整齐、无乱码
- ✅ 后30页以完整代码结束，无截断

## 常见问题

### Q1: 为什么生成Word而不是PDF？
**A:** Word格式便于手动调整，可以：
- 灵活调整行间距和边距
- 方便删除或修改内容
- 更容易控制页数

### Q2: 如何快速调整到30页？
**A:** 建议步骤：
1. 先删除非核心注释（如示例注释）
2. 将行间距从1.0调整到1.15-1.3
3. 适当增加页边距（上下2.5→3cm）
4. 如仍超过30页，删除部分详细注释

### Q3: 如何修改文件列表？
**A:** 编辑 `generate_copyright_word.ps1` 中的文件列表：
```powershell
$FrontFiles = @(
    @{Path="main.dart"}
    @{Path="app.dart"}
    # 添加或修改文件...
)
```

### Q4: 生成失败提示没有Word？
**A:** 确保系统已安装Microsoft Word。脚本使用Word COM对象生成文档。

## 技术实现

### 核心技术
- **PowerShell 5.1+** - 脚本自动化
- **Word COM对象** - 文档生成和格式控制
- **UTF-8编码** - 确保中文正确显示

### 关键特性
1. **完整源代码保留**
   - 不做任何修改或删除
   - 保留所有注释和空行
   - 确保代码专业性和完整性

2. **自动格式设置**
   - A4页面，标准边距
   - 页眉：软件名 + 页码
   - Consolas 10号等宽字体
   - 单倍行间距

3. **灵活的生成选项**
   - 可单独生成前30页或后30页
   - 默认生成两个文档
   - 支持自定义起始页码

## 输出示例

生成的Word文档包含：

```
页眉：EasyFile v1.0.0                                          1

main.dart

import 'package:audio_session/audio_session.dart';
import 'package:easyfile/analytics/analytics_manager.dart';
import 'package:easyfile/app.dart';
...
```

## 注意事项

⚠️ **重要提醒**
1. 生成后必须手动调整到恰好30页
2. 页眉文本需改为中文格式
3. 文件名前缀需改为"代码文件："
4. 检查页码连续性（前30页：1-30，后30页：31-60）

⚠️ **文件说明**
- 生成的Word文档仅用于软著申请
- 包含完整源代码，便于审核
- 可保留Word文档用于后续修改

## 维护说明

如需更新版本号或文件选择，编辑 `generate_copyright_word.ps1`：

```powershell
# 前30页文件列表
$FrontFiles = @(
    @{Path="main.dart"}
    @{Path="app.dart"}
    ...
)

# 后30页文件列表
$BackFiles = @(
    @{Path="core\services\recommendation_service.dart"}
    ...
)
```

## 许可

本工具为EasyFile项目内部使用，不对外开源。

---

**更新日期:** 2026-02-09
**工具版本:** 1.0.0
**适用于:** EasyFile V1.0.0 软著申请
