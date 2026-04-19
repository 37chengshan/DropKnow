# DropKnow V1 在 Xcode 中的快速开始指南

## ✅ 项目已就绪！

你的 DropKnow V1 工程骨架已经可以在 Xcode 中正常使用。

### 编译状态
- **编译结果**：✅ 成功（0 errors, 4 warnings）
- **测试结果**：✅ 全部通过（13/13 tests passed）

---

## 🚀 在 Xcode 中使用

### 1. 打开项目

```bash
open -a Xcode /Users/cc/luozhi/DropKnow/Package.swift
```

或者直接在 Xcode 中：
- File → Open → 选择 `/Users/cc/luozhi/DropKnow` 文件夹

### 2. 编译项目

**快捷键**：⌘B

在 Xcode 工具栏看到：
- 左侧：Product 菜单中有 "Build" 选项
- 或直接按 ⌘B

### 3. 运行测试

**快捷键**：⌘U

将运行所有 13 个测试用例：
- ✅ EnumFallbackTests (3 tests)
- ✅ ErrorCodeRetryPolicyTests (4 tests)
- ✅ IngestionPipelineIntegrationTests (1 test)
- ✅ ProviderParsingTests (2 tests)
- ✅ RepositoryLayerTests (1 test)
- ✅ UISmokeTests (1 test)
- ✅ WatcherRenameTests (1 test)

---

## 📁 项目结构导航

在左侧导航栏中浏览：

```
DropKnow/
├── App/
│   ├── Scenes/              # SwiftUI 场景 (MenuBar, DocumentDetail, Settings, QuickPanel)
│   └── DropKnowV1Container  # 依赖注入容器
├── Domain/
│   ├── Entities/            # 数据库行、DTO、模型
│   ├── Enums/               # 状态枚举、错误码
│   └── Protocols/           # 管道协议
├── Features/
│   ├── Watcher/             # 文件监听（hash 去重）
│   ├── Import/              # 导入与管道协调
│   ├── Parsing/             # 文档解析
│   ├── Summarization/       # 摘要提取
│   ├── Events/              # 事件提取
│   ├── UIBridge/            # UI 服务桥接
│   └── MenuBar/ViewModels/  # ViewModel 层
├── Infrastructure/
│   ├── Database/            # SQLite schema 和初始化
│   └── Providers/           # 提供商实现（Summary、Event、SearchQA）
├── Repositories/            # CRUD 层（9 个 Repository actors）
├── Shared/
│   ├── Components/          # SwiftUI 组件
│   ├── DesignSystem/        # 设计系统
│   └── Errors/              # 错误码定义
├── Views/                   # SwiftUI 页面视图
└── Tests/
    ├── UnitTests/           # 单元测试
    ├── IntegrationTests/    # 集成测试
    └── UITests/             # UI 测试
```

---

## 🔧 常见操作

| 操作 | 快捷键 | 说明 |
|------|---------|------|
| 编译 | ⌘B | 检查编译错误 |
| 运行测试 | ⌘U | 运行所有单元测试 |
| 清理构建 | ⇧⌘K | 删除构建文件并重新编译 |
| 搜索文件 | ⌘⇧O | 快速打开文件 |
| 搜索代码 | ⌘⇧F | 在整个项目中搜索文本 |
| 跳到定义 | ⌘Click | 点击符号跳到其定义 |

---

## 📊 项目统计

- **总文件数**：80+ Swift 文件
- **测试覆盖**：13 个测试用例（覆盖关键路径）
- **主要 actors**：9 个 Repository + 1 个 RepositoryAuxiliaryStore
- **ViewModels**：4 个（RecentFiles, ImportantReminders, DocumentDetail, Search）
- **SwiftUI 场景**：4 个（MenuBar, DocumentDetail, Settings, QuickPanel）
- **SwiftUI 组件**：5 个（SummaryCard, ImportantEventCard, RiskGateSheet, QuotaBadge, EvidenceSnippetList）

---

## ⚠️ 编译警告说明

你可能会看到 4 个关于"unhandled files"的警告：
```
'dropknow': found 4 file(s) which are unhandled
    - migration_v1.sql
    - schema.sql
    - README.md
    - Assets.xcassets
```

这些是非 Swift 文件的资源，可以忽略（不影响编译）。如果要消除警告，可以在 `Package.swift` 中声明它们为资源。

---

## 🎯 下一步

### P1（立即）：SQLite Repository 实装
- 将 `InMemoryRepositories` 替换为真实 SQLite 持久化
- 需要修改 `Infrastructure/Database/` 目录

### P2（后续）：完成 Search 功能
- 实装文档分块检索
- 集成搜索 QA 和 citations

### P3（后续）：Calendar 同步
- Event → Calendar 状态转换
- 权限处理与冲突检测

### P4（后续）：Quota 强制
- 日额度追踪与显示
- 升级引导

---

## 💡 建议

1. **先编译**（⌘B）→ 验证项目加载无误
2. **运行测试**（⌘U）→ 确保所有功能可用
3. **浏览代码**→ 熟悉架构和分层
4. **按优先级实装** → 从 P1 开始

有任何问题，可以继续询问我！
