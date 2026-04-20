# Phase 2/3 Plan 审核记录

作者：glm5.1+37chengshan
日期：2026-04-20

## 审核范围

- `docs/exec-plans/active/EP-002-event-calendar-freemium/plans/02-PLAN.md`
- `docs/exec-plans/active/EP-003-search-qa/plans/03-PLAN.md`

## 审核结论

结论：通过，可执行。

## 审核清单

1. 目标是否与 roadmap 对齐：通过
- Phase 2 聚焦日历与 Freemium 边界。
- Phase 3 聚焦搜索/问答与证据返回。

2. 是否存在跨阶段扩张：通过
- 未引入 OCR、PPT、全局弹窗等 Phase 4/5 内容。

3. 任务是否可验证：通过
- 每个任务都绑定了 `swift test --filter` 验证命令。

4. 边界是否清晰：通过
- 每个任务都列出 `DO NOT CHANGE` 范围。

5. 风险是否显式：通过
- 已标注 EventKit 接入策略与后续权限风险。

## 审核建议（已采纳）

1. 先实现可注入 Calendar Bridge，避免测试依赖系统权限。
2. 在 `SearchService` 前置能力判断，避免 UI 层重复判定。
3. 设置页额度先接仓库读模型，避免硬编码误导。

## 审核修订记录

1. 已修复验证依赖倒置：把 `SearchServiceQATests` 前置到 Phase 3 开始任务，把 `CalendarAndSubscriptionFlowTests` 前置到 Phase 2。
2. 已补 Phase 2 优先级任务：新增 `Task 02-04`，覆盖高/普通/可忽略排序策略。
3. 已修复 Task 02-03 可测性不足：将验证命令改为以业务单测为主，`UISmokeTests` 为补充。
