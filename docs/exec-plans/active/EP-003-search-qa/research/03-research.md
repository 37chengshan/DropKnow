# EP-003 研究记录（高级搜索/问答）

作者：glm5.1+37chengshan
日期：2026-04-20

## 结论摘要

1. QuickPanel 与 `SearchViewModel` 状态机已具备主框架。
2. 搜索服务当前是本地关键词拼接，QA 模式未接入 `SearchQAProvider`。
3. `SearchBlockReason` 已定义但目前主要只用到 `empty_index`，`quota_exceeded` 与 `feature_locked` 未真实触发。

## 证据文件

- `DropKnow/App/Scenes/QuickPanelScene/QuickPanelScene.swift`
- `DropKnow/Features/Search/ViewModels/SearchViewModel.swift`
- `DropKnow/Features/UIBridge/UIBridgeServices.swift`
- `DropKnow/Infrastructure/Providers/SearchQA/SearchQAProvider.swift`
- `DropKnow/Domain/Enums/SearchEnums.swift`

## 约束与边界

1. 保持轻量：不引入复杂多轮对话历史。
2. 问答仅在已有本地召回结果基础上调用 provider。
3. 结果页先保留现有结构，仅补能力正确性。
