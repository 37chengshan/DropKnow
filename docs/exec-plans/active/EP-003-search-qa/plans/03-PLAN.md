---
phase: 03-search-qa
plan: 03
type: execute
wave: 1
depends_on: ["02"]
---

# EP-003 执行计划

作者：glm5.1+37chengshan
日期：2026-04-20

## 目标

完成 Phase 3 最小闭环：自然语言提问可返回可解释答案与证据，并正确执行搜索/问答能力边界。

## Task 03-00：先补测试基线（前置）

### files
- `Tests/UnitTests/SearchServiceQATests.swift`（新建）

### acceptance_criteria
- AC-03-00-1
  - Given QA 成功、QA 失败、功能锁、额度限制四类场景
  - When 运行单测
  - Then 每类状态均可断言

### action
1. 先写失败测试（red）。
2. 再进行实现使测试通过（green）。

### boundaries
DO NOT CHANGE:
- `DropKnow/Infrastructure/Database/**`

### verify
- `swift test --filter SearchServiceQATests`

## Task 03-01：引入 QA Provider 主链路

### files
- `DropKnow/Features/UIBridge/UIBridgeServices.swift`
- `DropKnow/App/DropKnowV1Container.swift`

### acceptance_criteria
- AC-03-01-1
  - Given `mode == .qa` 且存在召回证据
  - When 调用 `SearchService.ask`
  - Then 使用 `SearchQAProvider` 生成答案并返回 citations
- AC-03-01-2
  - Given QA Provider 失败
  - When 调用 `SearchService.ask`
  - Then 返回 `SearchStatus.failed` 且消息可解释

### action
1. 给 `SearchService` 注入 `SearchQAProviding`。
2. 构造 `SearchQAProviderRequest`（question + retrieved_items + date/timezone）。
3. 将 provider 结果映射到 `SearchSnapshot`。

### boundaries
DO NOT CHANGE:
- `DropKnow/Features/Import/**`
- `DropKnow/Features/Watcher/**`

### verify
- `swift test --filter SearchServiceQATests`
- `swift test --filter ProviderParsingTests`

## Task 03-02：补齐 blocked 原因（配额与功能锁）

### files
- `DropKnow/Features/UIBridge/UIBridgeServices.swift`
- `DropKnow/Features/Search/ViewModels/SearchViewModel.swift`

### acceptance_criteria
- AC-03-02-1
  - Given 免费计划禁止高级问答
  - When QA 模式调用搜索
  - Then 返回 `SearchStatus.blocked` + `SearchBlockReason.feature_locked`
- AC-03-02-2
  - Given 当日额度用尽
  - When search/qa 请求执行
  - Then 返回 `SearchStatus.blocked` + `SearchBlockReason.quota_exceeded`

### action
1. 复用 Phase 2 订阅策略服务。
2. 在 `SearchService.ask` 前置校验策略与额度。

### boundaries
DO NOT CHANGE:
- `DropKnow/Views/**`

### verify
- `swift test --filter SearchServiceQATests`

## Task 03-03：增加最小测试覆盖

### files
- `Tests/UnitTests/CalendarAndSubscriptionFlowTests.swift`（新建）

### acceptance_criteria
- AC-03-03-1
  - Given 关键成功路径与受限路径
  - When 运行单测
  - Then 覆盖 QA 成功、QA 失败、功能锁、额度限制、日历能力锁

### action
1. 新增测试 Double，覆盖服务层关键行为。
2. 不依赖 UI，优先验证领域逻辑。

### boundaries
DO NOT CHANGE:
- `Tests/IntegrationTests/**`

### verify
- `swift test --filter SearchServiceQATests`
- `swift test --filter CalendarAndSubscriptionFlowTests`
