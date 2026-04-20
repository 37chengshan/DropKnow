---
phase: 02-event-calendar-freemium
plan: 02
type: execute
wave: 1
depends_on: []
---

# EP-002 执行计划

作者：glm5.1+37chengshan
日期：2026-04-20

## 目标

完成 Phase 2 最小闭环：事件候选可在详情页触发真实日历写入，并执行 Freemium 边界与配额展示。

## Task 02-01：实现日历桥接服务

### files
- `DropKnow/Features/Calendar/CalendarBridge.swift`（新建）
- `DropKnow/Features/Calendar/CalendarFeatureService.swift`（新建）

### acceptance_criteria
- AC-02-01-1
  - Given 事件可入历且标题非空
  - When 调用 `CalendarFeatureService.addEvent` 
  - Then 返回 `CalendarAddResult.added` 且包含 `eventIdentifier`
- AC-02-01-2
  - Given 事件不可入历或标题为空
  - When 调用 `CalendarFeatureService.addEvent`
  - Then 返回 `CalendarAddResult.notEligible`

### action
1. 定义 `CalendarAddRequest`、`CalendarAddResult`。
2. 定义 `CalendarBridging` 协议，增加一个默认内存实现（测试可控）。
3. `CalendarFeatureService` 封装 eligibility 检查与错误映射。

### boundaries
DO NOT CHANGE:
- `DropKnow/Features/Search/**`
- `DropKnow/Infrastructure/Providers/**`

### verify
- `swift test --filter RepositoryLayerTests`

## Task 02-01b：先补测试基线（前置）

### files
- `Tests/UnitTests/CalendarAndSubscriptionFlowTests.swift`（新建）

### acceptance_criteria
- AC-02-01b-1
  - Given 日历能力成功、功能锁、不可入历三类场景
  - When 运行单测
  - Then 三类行为可被断言

### action
1. 先新增服务层测试 Double。
2. 先写失败断言，再补实现。

### boundaries
DO NOT CHANGE:
- `DropKnow/Infrastructure/Database/**`

### verify
- `swift test --filter CalendarAndSubscriptionFlowTests`

## Task 02-02：实现订阅策略与配额读取

### files
- `DropKnow/Features/Subscription/SubscriptionFeatureService.swift`（新建）
- `DropKnow/Features/UIBridge/UIBridgeServices.swift`
- `DropKnow/App/DropKnowV1Container.swift`

### acceptance_criteria
- AC-02-02-1
  - Given 免费计划
  - When 调用“加入日历”能力检查
  - Then 返回 `feature_locked`
- AC-02-02-2
  - Given 免费计划且问答已达上限
  - When 执行 QA 模式查询
  - Then 返回 `SearchBlockReason.quota_exceeded`

### action
1. 在 `SubscriptionFeatureService` 内提供 `canUseCalendar` 与 `canUseSearch` 判定。
2. 在 `DocumentDetailService.markEventAddedToCalendar` 接入订阅与日历服务。
3. 在 `SearchService.ask` 接入订阅/配额判定。

### boundaries
DO NOT CHANGE:
- `DropKnow/Infrastructure/Database/schema.sql`
- `DropKnow/Features/Import/**`

### verify
- `swift test --filter CalendarAndSubscriptionFlowTests`

## Task 02-03：Settings 接入真实配额

### files
- `DropKnow/App/DropKnowAppModel.swift`
- `DropKnow/Views/SettingsView.swift`
- `Tests/UnitTests/CalendarAndSubscriptionFlowTests.swift`

### acceptance_criteria
- AC-02-03-1
  - Given `quotaRepository` 有当天额度记录
  - When 打开设置页
  - Then 显示真实 `used/limit` 数值

### action
1. `DropKnowAppModel` 增加 `quotaSnapshot` 与加载逻辑。
2. `SettingsView` 改为绑定模型额度，不再硬编码。

### boundaries
DO NOT CHANGE:
- `DropKnow/Features/DocumentDetail/**`

### verify
- `swift test --filter CalendarAndSubscriptionFlowTests`
- `swift test --filter UISmokeTests`

## Task 02-04：提醒优先级规则升级（高/普通/可忽略）

### files
- `DropKnow/Features/UIBridge/UIBridgeServices.swift`

### acceptance_criteria
- AC-02-04-1
  - Given 考试/DDL 且时间信号明确
  - When 生成重要提醒列表
  - Then 进入高优先级排序
- AC-02-04-2
  - Given 低置信度或缺少时间信号
  - When 生成重要提醒列表
  - Then 降级为普通或可忽略

### action
1. 在 `DashboardService.fetchImportantReminders` 中加入基于 `event_type`/`raw_time_text`/`confidence` 的评分。
2. 保持提醒列表返回结构不变，只调排序与过滤策略。

### boundaries
DO NOT CHANGE:
- `DropKnow/Views/**`

### verify
- `swift test --filter CalendarAndSubscriptionFlowTests`

## 风险

1. 当前不直接接 EventKit，先以可注入桥接保证测试稳定。
2. 若后续接系统日历权限，需要单独补 UI 权限引导。
