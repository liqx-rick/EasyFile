# GitHub Copilot 开发工作流模板

本文档定义了 EasyFile 项目中与 GitHub Copilot 协作时使用的标准开发流程。

## 使用方式

在与 Copilot 交流时，直接引用模板名称即可：
- **示例**：`请用模板A实现批量删除优化功能`
- **示例**：`按照模板C修复文件加载bug`

---

## 模板A：功能开发标准流程

**适用场景**：新增功能、重构代码

**流程步骤**：
1. **需求分析**
   - 理解需求并确认实现方案
   - 列出涉及的文件和修改点
   - 询问不明确的需求细节

2. **代码实现**
   - 按照项目代码规范实现功能
   - 添加必要的注释和日志
   - 确保错误处理完善

3. **代码质量检查**
   - 运行 `flutter analyze` 检查代码问题
   - 运行 `dart format` 格式化代码
   - 确保无新增 errors 或 warnings

4. **展示改动**
   - 使用 `get_changed_files` 展示所有改动
   - 说明关键改动点和实现逻辑
   - 提供性能影响评估（如适用）

5. **等待确认**
   - 等待开发者 review 代码
   - 根据反馈进行调整

6. **提交代码**（经确认后）
   - 编写规范的 commit message（遵循 Conventional Commits）
   - 执行 `git commit`
   - 不自动 push（由开发者决定何时推送）

---

## 模板B：性能优化流程

**适用场景**：性能瓶颈优化、大规模数据处理优化

**流程步骤**：
1. **性能分析**
   - 定位性能瓶颈（IO、计算、内存等）
   - 分析当前实现的时间/空间复杂度
   - 使用 `semantic_search` 和 `grep_search` 查找相关代码

2. **优化方案设计**
   - 提出优化方案（算法优化、批量处理、缓存等）
   - 说明预期性能提升（如：10x, 50x）
   - 列出需要修改的文件

3. **代码实现**
   - 实现优化逻辑
   - 保持向后兼容性
   - 添加性能相关注释

4. **性能验证**
   - 说明优化前后的对比（IO次数、时间复杂度等）
   - 如有测试代码则运行测试

5. **代码质量检查**
   - 运行 `flutter analyze`
   - 运行 `dart format`

6. **展示改动**
   - 展示 diff 和性能对比数据
   - 说明优化原理

7. **等待确认**
   - 等待开发者确认优化效果

8. **提交代码**（经确认后）
   - 提交信息需包含性能提升数据
   - 格式：`perf: 优化XXX性能 (提升Nx)`

---

## 模板C：Bug修复流程

**适用场景**：修复已知Bug、解决运行时错误

**流程步骤**：
1. **问题诊断**
   - 理解Bug现象和复现步骤
   - 使用 `grep_search` 查找相关代码
   - 定位问题根因

2. **修复方案**
   - 说明修复思路
   - 评估影响范围
   - 确认是否需要额外测试

3. **代码修复**
   - 实现修复逻辑
   - 添加防御性代码（如需要）
   - 确保不引入新问题

4. **验证修复**
   - 运行相关测试（如有）
   - 运行 `flutter analyze` 确保无新问题

5. **代码格式化**
   - 运行 `dart format`

6. **展示改动**
   - 展示修复的代码 diff
   - 说明修复原理和测试结果

7. **等待确认**
   - 等待开发者验证修复效果

8. **提交代码**（经确认后）
   - 提交信息格式：`fix: 修复XXX问题`
   - 包含问题描述和修复方式

---

## 模板D：快速迭代流程

**适用场景**：小改动、样式调整、简单修复

**流程步骤**：
1. **理解需求**
   - 确认改动点

2. **快速实现**
   - 直接修改代码

3. **质量检查**
   - 运行 `dart format`
   - 快速 `flutter analyze`（可选）

4. **立即提交**
   - 简洁的 commit message
   - 不需要详细 review

**注意**：此模板适合信任度高的简单改动，复杂功能请使用模板A

---

## 模板E：探索性分析流程

**适用场景**：代码调研、架构分析、问题排查

**流程步骤**：
1. **信息收集**
   - 使用 `semantic_search` 搜索相关代码
   - 使用 `grep_search` 查找特定模式
   - 阅读相关文件

2. **分析总结**
   - 梳理代码结构和调用关系
   - 识别潜在问题或优化点
   - 提供清晰的分析报告

3. **建议方案**（可选）
   - 提出改进建议
   - 评估实施难度和收益

**注意**：此模板不涉及代码修改，仅用于分析和调研

---

## 模板F：测试驱动开发流程

**适用场景**：关键功能开发、需要高测试覆盖率的模块

**流程步骤**：
1. **需求分析**
   - 理解功能需求
   - 定义输入输出和边界条件

2. **编写测试**
   - 编写单元测试或集成测试
   - 覆盖正常场景和异常场景

3. **运行测试**（应该失败）
   - 使用 `runTests` 运行测试
   - 确认测试正确反映需求

4. **实现功能**
   - 编写最小可用代码
   - 使测试通过

5. **重构优化**
   - 优化代码质量
   - 保持测试通过

6. **最终验证**
   - 运行所有相关测试
   - 运行 `flutter analyze` 和 `dart format`

7. **展示结果**
   - 展示测试结果和代码 diff

8. **等待确认并提交**

---

## 通用规则

### Commit Message 规范
遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

- `feat:` 新功能
- `fix:` Bug修复
- `perf:` 性能优化
- `refactor:` 重构（不改变外部行为）
- `style:` 代码格式调整
- `docs:` 文档更新
- `test:` 测试相关
- `chore:` 构建/工具链相关

### 代码质量标准
- 必须通过 `flutter analyze`（允许 info 级别提示）
- 必须通过 `dart format` 格式化
- 新增代码需要适当的注释和日志
- 错误处理必须完善（try-catch + logger.e）

### 安全检查
- 涉及文件操作时必须进行路径安全检查
- 使用 `PathSecurity` 类验证操作安全性
- 敏感操作需要用户确认

---

## 模板G：Git 分支管理流程

**适用场景**：创建功能分支、合并代码、分支清理

### G1：创建新功能分支

**流程步骤**：
1. **确认基准分支**
   - 确认从 `ef-dev-v2` 创建 feature 分支
   - 检查当前分支状态

2. **创建并切换分支**
   ```bash
   git checkout ef-dev-v2
   git pull origin ef-dev-v2
   git checkout -b feature/功能名称
   ```

3. **分支命名规范**
   - 功能开发：`feature/功能描述`（如：`feature/optimize-file-browser-ux`）
   - Bug修复：`bugfix/问题描述`（如：`bugfix/fix-favorite-crash`）
   - 性能优化：`perf/优化内容`（如：`perf/optimize-batch-operations`）
   - 重构：`refactor/重构内容`（如：`refactor/clean-presenter-layer`）

4. **开始开发**
   - 按照对应的开发流程模板进行开发

### G2：合并功能分支到开发分支

**流程步骤**：
1. **开发分支最终检查**
   - 确保所有改动已提交
   - 运行 `flutter analyze` 和 `dart format`
   - 确认功能完整且测试通过

2. **同步最新开发分支**
   ```bash
   git checkout ef-dev-v2
   git pull origin ef-dev-v2
   ```

3. **合并功能分支**
   ```bash
   git merge --no-ff feature/功能名称
   ```
   - 使用 `--no-ff` 保留分支历史记录
   - 编写合并提交信息（如：`Merge feature/optimize-file-browser-ux`）

4. **解决冲突**（如有）
   - 使用 `git status` 查看冲突文件
   - 手动解决冲突
   - `git add` 标记为已解决
   - `git commit` 完成合并

5. **推送到远程**
   ```bash
   git push origin ef-dev-v2
   ```

6. **清理本地分支**
   ```bash
   git branch -d feature/功能名称
   ```

7. **清理远程分支**（如果推送过）
   ```bash
   git push origin --delete feature/功能名称
   ```

### G3：紧急修复流程（Hotfix）

**适用场景**：生产环境紧急 bug 需要立即修复

**流程步骤**：
1. **从 main 创建 hotfix 分支**
   ```bash
   git checkout main
   git pull origin main
   git checkout -b hotfix/问题描述
   ```

2. **快速修复**
   - 最小化改动范围
   - 添加必要的日志和错误处理
   - 严格测试

3. **合并到 main**
   ```bash
   git checkout main
   git merge --no-ff hotfix/问题描述
   git tag -a v版本号 -m "Hotfix: 问题描述"
   git push origin main --tags
   ```

4. **同步到开发分支**
   ```bash
   git checkout ef-dev-v2
   git merge --no-ff hotfix/问题描述
   git push origin ef-dev-v2
   ```

5. **清理 hotfix 分支**
   ```bash
   git branch -d hotfix/问题描述
   ```

### G4：版本发布流程

**适用场景**：v2 开发完成，准备发布到生产环境

**流程步骤**：
1. **开发分支最终验收**
   - 完成所有功能开发
   - 通过集成测试
   - 更新 CHANGELOG.md
   - 更新版本号（pubspec.yaml）

2. **合并到 main**
   ```bash
   git checkout main
   git pull origin main
   git merge --no-ff ef-dev-v2
   ```

3. **打版本标签**
   ```bash
   git tag -a v2.0.0 -m "Release version 2.0.0"
   ```

4. **推送到远程**
   ```bash
   git push origin main --tags
   ```

5. **创建 GitHub Release**（可选）
   - 在 GitHub 上创建 Release
   - 关联 tag v2.0.0
   - 上传编译产物（APK/AAB）
   - 填写 Release Notes

### G5：同步功能分支与开发分支

**适用场景**：功能分支开发时间较长，需要同步最新的开发分支改动

**流程步骤**：
1. **提交当前工作**
   ```bash
   git add -A
   git commit -m "WIP: 当前进度"
   ```

2. **获取最新开发分支**
   ```bash
   git fetch origin ef-dev-v2:ef-dev-v2
   ```

3. **合并开发分支**
   ```bash
   git merge ef-dev-v2
   ```

4. **解决冲突**（如有）
   - 手动解决冲突
   - 测试确保功能正常
   - 提交合并结果

5. **继续开发**

---

## 分支管理最佳实践

### 分支结构
```
main (生产版本，使用 Git Tag 标记版本)
  ↓
ef-dev-v2 (v2 开发集成分支)
  ↓
feature/* (功能分支，开发完成后删除)
bugfix/* (修复分支，开发完成后删除)
perf/* (性能优化分支，开发完成后删除)
refactor/* (重构分支，开发完成后删除)
hotfix/* (紧急修复分支，合并后删除)
```

### 提交规范
- 小步提交，频繁推送
- 每个提交只做一件事
- commit message 遵循 Conventional Commits
- 合并时使用 `--no-ff` 保留分支历史

### 版本标记
使用 Git Tag 替代长期发布分支：
```bash
# 正式版本
git tag -a v1.0.0 -m "Release version 1.0.0"
git tag -a v2.0.0 -m "Release version 2.0.0"

# 预发布版本
git tag -a v2.0.0-beta.1 -m "Beta release"

# 查看所有标签
git tag -l

# 检出特定版本
git checkout v1.0.0
```

### Git Alias 配置（可选）

在 `~/.gitconfig` 或项目 `.git/config` 中添加：

```ini
[alias]
  # 创建功能分支
  feat = "!f() { git checkout ef-dev-v2 && git pull && git checkout -b feature/$1; }; f"
  
  # 创建性能优化分支
  perf = "!f() { git checkout ef-dev-v2 && git pull && git checkout -b perf/$1; }; f"
  
  # 创建修复分支
  fix = "!f() { git checkout ef-dev-v2 && git pull && git checkout -b bugfix/$1; }; f"
  
  # 快速合并到开发分支
  merge-dev = "!git checkout ef-dev-v2 && git pull && git merge --no-ff @{-1} && git push"
  
  # 同步开发分支
  sync = "!git fetch origin ef-dev-v2:ef-dev-v2 && git merge ef-dev-v2"
  
  # 清理已合并的本地分支
  cleanup = "!git branch --merged ef-dev-v2 | grep -v 'ef-dev-v2\\|main' | xargs -r git branch -d"
```

使用示例：
```bash
git feat optimize-ux       # 创建 feature/optimize-ux 分支
git sync                   # 同步最新的 ef-dev-v2
git merge-dev              # 合并回 ef-dev-v2 并推送
git cleanup                # 清理已合并的分支
```

---

## 自定义模板

你可以根据项目需求添加自定义模板，格式如下：

```markdown
## 模板X：自定义流程名称

**适用场景**：...

**流程步骤**：
1. ...
2. ...
```

---

**最后更新**：2025-11-21  
**维护者**：liqx-rick
