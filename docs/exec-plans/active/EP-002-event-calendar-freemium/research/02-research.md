# EP-002 研究记录（事件、日历、Freemium）

作者：glm5.1+37chengshan
日期：2026-04-20

## 结论摘要

1. 事件抽取主链路已存在并可落库，核心缺口在“日历真实桥接”和“订阅/额度真实判定”。
2. 详情页已有“加入日历/忽略”入口，但当前加入日历仅修改本地状态，尚未写入 Apple Calendar。
3. 设置页额度为静态文案，尚未接入 `quotaRepository` 的真实数据。

## 证据文件

- `DropKnow/Features/Import/IngestionCoordinator.swift`
- `DropKnow/Infrastructure/Providers/EventExtraction/EventExtractionProvider.swift`
- `DropKnow/Features/UIBridge/UIBridgeServices.swift`
- `DropKnow/Views/SettingsView.swift`
- `DropKnow/Domain/Enums/EventEnums.swift`
- `DropKnow/Shared/Errors/ErrorCode.swift`

## 约束与边界

1. 不做跨阶段扩张：本阶段不做 OCR、PPT、新平台联动。
2. 保持现有分层：`Features/Calendar` 和 `Features/Subscription` 新增能力，不把逻辑塞进 View。
3. 优先最小闭环：先让“可入历事件->可写入日历/可解释失败->状态回写”跑通。
