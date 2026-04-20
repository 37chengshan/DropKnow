# DropKnow：从工程收口到搜索的 5.3 Codex 执行清单

> 适用模型：`gpt-5.3-codex`
> 适用仓库：`/Users/cc/Desktop/DropKnow`
> 目标顺序：`工程收口 -> 真持久化 -> 真 provider -> 真监听闭环 -> 日历/订阅 -> 搜索`
> 用法：本文档本身就是执行手册；Codex 读取后按阶段逐轮执行，一轮只做一个阶段

---

# 1. 先说明白：这份清单是给 Codex 直接干活的

这不是产品规划文档，而是给 `gpt-5.3-codex` 的执行手册。要求是：

1. 先读真集和仓库地图，再动代码
2. 每轮只做一个阶段，做完就停
3. 每轮必须自己编译/测试/汇报，不允许只给方案不落地
4. 改动必须落在当前仓库真实目录，不写不存在的路径
5. 如果涉及状态、Provider 契约、组件 Props、数据库结构，必须先同步对应文档

---

# 2. 开工前必须读取的文档

按以下顺序读取：

1. `/Users/cc/Desktop/DropKnow/AGENTS.md`
2. `/Users/cc/Desktop/DropKnow/落知_状态机与错误码设计_v1.1.md`
3. `/Users/cc/Desktop/DropKnow/落知_Prompt与JSONSchema_FewShot规范_v1.1.md`
4. `/Users/cc/Desktop/DropKnow/落知_信息架构_技术架构_数据表设计_前端设计.md`
5. `/Users/cc/Desktop/DropKnow/落知_SwiftUI组件规格与页面实现指南.md`
6. `/Users/cc/Desktop/DropKnow/docs/数据库迁移清单.md`
7. `/Users/cc/Desktop/DropKnow/docs/Provider 输入输出契约.md`
8. `/Users/cc/Desktop/DropKnow/docs/ViewModel 状态映射表.md`
9. `/Users/cc/Desktop/DropKnow/docs/Swift enum DTO 对照表.md`

---

# 3. 当前仓库真实现状

这部分是为了防止 Codex 按想象施工。

## 3.1 已存在的真实入口和骨架

- App 入口：`/Users/cc/Desktop/DropKnow/DropKnow/DropKnowApp.swift`
- 旧占位入口：`/Users/cc/Desktop/DropKnow/DropKnow/MainApp.swift`
- 主容器：`/Users/cc/Desktop/DropKnow/DropKnow/App/DropKnowV1Container.swift`
- Scene：
  - `/Users/cc/Desktop/DropKnow/DropKnow/App/Scenes/MenuBarScene/MenuBarScene.swift`
  - `/Users/cc/Desktop/DropKnow/DropKnow/App/Scenes/QuickPanelScene/QuickPanelScene.swift`
  - `/Users/cc/Desktop/DropKnow/DropKnow/App/Scenes/DocumentDetailScene/DocumentDetailScene.swift`
  - `/Users/cc/Desktop/DropKnow/DropKnow/App/Scenes/SettingsScene/SettingsScene.swift`
- 当前主窗口：`/Users/cc/Desktop/DropKnow/DropKnow/App/DropKnowMainWindowView.swift`
- 测试目录真实位置：`/Users/cc/Desktop/DropKnow/Tests`

## 3.2 已存在的能力骨架

- Ingestion/Import：`DropKnow/Features/Import/`、`DropKnow/Features/Ingestion/`
- Watcher：`DropKnow/Features/Watcher/`
- Parsing：`DropKnow/Features/Parsing/`
- PrivacyGate：`DropKnow/Features/PrivacyGate/`
- Summary/Event/Search Provider：`DropKnow/Infrastructure/Providers/`
- 数据库骨架：`DropKnow/Infrastructure/Database/`
- 仓库层：`DropKnow/Repositories/RepositoryTypes.swift`

## 3.3 当前主要缺口

1. `DropKnowV1Container` 仍以 mock + in-memory 为主
2. `InMemoryIngestionPersistence` 仍承担主要落库职责
3. provider client 还是抽象层，真实 HTTP 链路未完整接通
4. watcher、持久化、UI 之间还没有形成完整闭环
5. 日历、订阅、搜索仍停在骨架或占位态

---

# 4. Codex 必须遵守的工作边界

## 4.1 一轮只做一个阶段

不允许在同一轮同时做：

- 真持久化 + 真 provider
- 真监听闭环 + 搜索
- 搜索 + 日历/订阅

## 4.2 文档先行规则

1. 改数据库结构：先改 `/Users/cc/Desktop/DropKnow/docs/数据库迁移清单.md`
2. 改状态枚举：同步改
   - `/Users/cc/Desktop/DropKnow/落知_状态机与错误码设计_v1.1.md`
   - `/Users/cc/Desktop/DropKnow/docs/Swift enum DTO 对照表.md`
   - `/Users/cc/Desktop/DropKnow/docs/ViewModel 状态映射表.md`
3. 改 provider 输出字段：同步改
   - `/Users/cc/Desktop/DropKnow/落知_Prompt与JSONSchema_FewShot规范_v1.1.md`
   - `/Users/cc/Desktop/DropKnow/docs/Provider 输入输出契约.md`
4. 改页面状态或组件 Props：同步改
   - `/Users/cc/Desktop/DropKnow/落知_SwiftUI组件规格与页面实现指南.md`
   - `/Users/cc/Desktop/DropKnow/docs/ViewModel 状态映射表.md`

## 4.3 输出纪律

每轮结束必须输出：

1. 本轮目标是否完成
2. 实际修改文件
3. 运行过的验证命令和结果
4. 剩余风险
5. 是否可以进入下一阶段

---

# 5. 标准执行顺序

## Phase A：工程收口

### 目标

把仓库从“有骨架”收口到“能稳定 build/test，入口清楚，默认跑 production wiring”。

### 优先改哪些文件

- `/Users/cc/Desktop/DropKnow/Package.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/DropKnowApp.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/MainApp.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/App/DropKnowMainWindowView.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/App/DropKnowV1Container.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/App/Scenes/`
- `/Users/cc/Desktop/DropKnow/README.md`
- `/Users/cc/Desktop/DropKnow/Tests/`

### 方案步骤

1. 先修 `swift build` 和 `swift test` 的基线问题
2. 清理双入口/旧占位入口的歧义，保留一个清楚的 app 启动路径
3. 明确 `DropKnowV1Container` 是 demo 容器还是 production 容器
4. 把主窗口、QuickPanel、Settings、详情 Scene 的装配关系理顺
5. 保证应用启动时至少能初始化配置、数据库、基础 orchestrator
6. README 和启动说明同步到真实现状

### 完成标准

- `swift build` 通过
- `swift test` 通过
- 默认入口不再依赖“旧占位”命名误导
- 启动后能打开主窗口、QuickPanel、Settings

### 本轮验证

```bash
cd /Users/cc/Desktop/DropKnow
swift build
swift test
```

## Phase B：真持久化

### 目标

把运行态从 `InMemoryIngestionPersistence` 主导，迁到 SQLite 主导；重启后数据还能回来。

### 优先改哪些文件

- `/Users/cc/Desktop/DropKnow/docs/数据库迁移清单.md`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Database/schema.sql`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Database/migration_v1.sql`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Database/DatabaseInitializer.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Domain/Entities/DatabaseRows.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Domain/Entities/DatabaseMappers.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Repositories/RepositoryTypes.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Import/InMemoryIngestionPersistence.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/App/DropKnowV1Container.swift`

### 方案步骤

1. 明确 Application Support 下的数据库路径和初始化时机
2. 打通 schema/migration/initializer，保证首启可建表、可建索引
3. 为文档、文本、摘要、事件、parse_jobs 提供 SQLite 实现
4. 把 ingest 关键写入链路放进事务边界
5. 用真实数据库实现替换默认 in-memory 依赖
6. 保留 mock/demo 入口，但不能继续作为默认运行态

### 完成标准

- ingest 一份文件后，`documents`、`document_texts`、`document_summaries`、`document_events`、`parse_jobs` 有真实数据
- 退出重启后 Recent/Detail 能读回
- 测试中至少覆盖 schema 初始化和基础 repository 读写

### 本轮验证

```bash
cd /Users/cc/Desktop/DropKnow
swift test --filter RepositoryLayerTests
swift test --filter IngestionPipelineIntegrationTests
```

## Phase C：真 Provider

### 目标

接通真实网络 provider，但不破坏现有 JSON parse、repair、schema validate、错误码映射链路。

### 优先改哪些文件

- `/Users/cc/Desktop/DropKnow/落知_Prompt与JSONSchema_FewShot规范_v1.1.md`
- `/Users/cc/Desktop/DropKnow/docs/Provider 输入输出契约.md`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Providers/Core/ProviderClient.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Providers/Core/ProviderClientFactory.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Providers/Core/ProviderConfig.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Providers/Core/ProviderExecutionSupport.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Providers/Summary/`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Providers/EventExtraction/`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Providers/SearchQA/`
- `/Users/cc/Desktop/DropKnow/Tests/UnitTests/ProviderParsingTests.swift`

### 方案步骤

1. 先对齐 Summary/Event/QA 三类输入输出契约
2. 实现真实 `ProviderClient`，包括超时、取消、重试、错误映射
3. 保留 `MockProviderClient` 作为测试/回退，不删除
4. 把 Summary、EventExtraction、SearchQA 三条链都切到真实 client
5. 补齐非法 JSON、repair 后成功、schema 校验失败、网络失败测试
6. provider 配置使用受控本地配置，不做开放式 provider 面板

### 完成标准

- Summary 能产出真实结构化结果并落库
- EventExtraction 能生成真实事件候选并落库
- ProviderParsingTests 覆盖 parse/repair/validate 主链路

### 本轮验证

```bash
cd /Users/cc/Desktop/DropKnow
swift test --filter ProviderParsingTests
swift test --filter IngestionPipelineIntegrationTests
```

## Phase D：真监听闭环

### 目标

把 watcher、导入、解析、门禁、摘要、事件、持久化串成真实自动处理闭环。

### 优先改哪些文件

- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Watcher/`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Import/`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Ingestion/`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Parsing/DocumentParsingService.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/PrivacyGate/PrivacyGateService.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Summarization/DocumentSummarizationService.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Events/DocumentEventExtractionService.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/App/DropKnowAppModel.swift`
- `/Users/cc/Desktop/DropKnow/Tests/IntegrationTests/WatcherRenameTests.swift`
- `/Users/cc/Desktop/DropKnow/Tests/IntegrationTests/IngestionPipelineIntegrationTests.swift`

### 方案步骤

1. watcher 只负责发现稳定文件，不吞并下游业务逻辑
2. import 负责去重、建 document、派发后续阶段
3. parsing、privacy、summary、event 各自独立，按状态机推进
4. 每个阶段都写 parse job 和 document status
5. UI 只消费结果，不在 ViewModel 里重做 pipeline 决策
6. 补齐 rename、重复文件、处理中断后的恢复验证

### 完成标准

- 放入或改名稳定文件后，能自动跑完整链路
- 被门禁阻断、摘要成功事件失败、全部成功三条路径都能落状态
- Recent/Detail 能看到真实闭环结果

### 本轮验证

```bash
cd /Users/cc/Desktop/DropKnow
swift test --filter WatcherRenameTests
swift test --filter IngestionPipelineIntegrationTests
```

## Phase E：日历 / 订阅

### 目标

补齐“事件加入日历”和“免费/订阅能力边界”的最小闭环，并落到 Settings 与详情动作里。

### 优先改哪些文件

- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Calendar/`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Calendar/`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Subscription/`
- `/Users/cc/Desktop/DropKnow/DropKnow/App/Scenes/SettingsScene/SettingsScene.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Views/SettingsView.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Views/DocumentDetailView.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/DocumentDetail/ViewModels/DocumentDetailViewModel.swift`
- `/Users/cc/Desktop/DropKnow/docs/ViewModel 状态映射表.md`
- `/Users/cc/Desktop/DropKnow/落知_SwiftUI组件规格与页面实现指南.md`

### 方案步骤

1. 先定义免费版/订阅版能力边界和错误态
2. 日历写入必须是用户触发确认，不做静默自动入历
3. 事件不可入历、权限缺失、额度不足都要有明确状态
4. Settings 展示目录、权限、日历、订阅、配额、诊断
5. Detail 的“加入日历”动作需要真实成功、失败、不可用三态

### 完成标准

- 事件可在详情页触发加入日历
- 无权限、不可入历、额度受限时 UI 可解释
- Settings 不再只是占位表单

### 本轮验证

```bash
cd /Users/cc/Desktop/DropKnow
swift test --filter UISmokeTests
swift test --filter EnumFallbackTests
```

## Phase F：搜索

### 目标

做出可用的搜索/问答闭环：本地召回证据，必要时走 QA provider，最后在 QuickPanel 呈现结果。

### 优先改哪些文件

- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Search/`
- `/Users/cc/Desktop/DropKnow/DropKnow/Features/Search/ViewModels/SearchViewModel.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Infrastructure/Providers/SearchQA/`
- `/Users/cc/Desktop/DropKnow/DropKnow/Domain/Enums/SearchEnums.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/App/Scenes/QuickPanelScene/QuickPanelScene.swift`
- `/Users/cc/Desktop/DropKnow/DropKnow/Views/`
- `/Users/cc/Desktop/DropKnow/docs/ViewModel 状态映射表.md`
- `/Users/cc/Desktop/DropKnow/落知_SwiftUI组件规格与页面实现指南.md`

### 方案步骤

1. 先定义搜索/问答状态：`idle`、`retrieving`、`assembling`、`answering`、`noResult`、`blocked`、`failed`
2. 搜索与问答拆成两个展示层，不要只用一个答案文本框
3. 搜索先做本地召回和证据展示，问答在此基础上补生成回答
4. QuickPanel 必须能解释“无索引”“无结果”“额度不足”“provider 失败”
5. UI 结果要显示答案、证据、来源文档或事件

### 完成标准

- QuickPanel 能区分搜索和问答
- 至少能看到证据列表和答案结果
- 失败、无结果、受限三类状态能清楚表达

### 本轮验证

```bash
cd /Users/cc/Desktop/DropKnow
swift test --filter UISmokeTests
swift test --filter ProviderParsingTests
```

---

# 6. Codex 执行规则

## 6.1 阶段切换规则

1. 执行前先重新确认当前阶段，不自行跳到下一阶段
2. 只有当前阶段完成标准和本轮验证都满足，才允许进入下一阶段
3. 如果当前阶段被真实 blocker 卡住，先汇报 blocker，不绕路去做后续阶段

## 6.2 实施规则

1. 先读文档，再读代码，再编辑
2. 优先最小闭环，不做横跨全仓的大重写
3. 遇到目录不存在时，应回到现有 feature 边界内补实现，不新造分层
4. 保持 `switch` exhaustive，不吞默认分支
5. 测试失败时，先判断是本阶段引入还是历史基线问题，并在汇报中说明

---

# 7. 每一轮都用这份输出模板

```text
本轮阶段：

完成情况：

修改文件：

关键实现：

验证命令与结果：

未解决风险：

是否建议进入下一阶段：
```

---

# 8. 最后提醒

这份清单不是让 Codex “自由发挥大重构”的，而是让它沿着 DropKnow 现有边界做最小闭环推进：

- 不跨阶段抢跑
- 不把多 feature 搓成一个大服务
- 不忽略真集文档
- 不跳过验证

只要按这个顺序推进，仓库会比“先做搜索 UI，再回头补基础设施”稳得多。
