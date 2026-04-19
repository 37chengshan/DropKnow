# ViewModel 状态映射表

本文档把数据库状态、搜索状态、额度状态与 SwiftUI 组件规格映射到页面级 ViewModel。目标是避免 UI 自己猜状态。

## 1. 总原则

1. UI 主标签优先看 `documents.lifecycle_status`
2. 阶段进度和调试信息看 `documents.current_stage` / `parse_jobs`
3. 事件入口看 `documents.event_status` + `document_events`
4. 搜索页状态看 `search_sessions.status`
5. 升级 CTA 看 `block_reason`、`search_sessions.block_reason`、套餐与额度

## 2. MenuBarViewModel

### 输入源

- `UsageQuotaRecord`
- 最近 3 条 `DocumentRecord`
- 最近 1 条高优先级 `DocumentEventRecord`
- 同步中任务的 `parse_jobs`

### 输出状态

| ViewModel 字段/状态 | 数据来源 | 映射规则 |
|---|---|---|
| `statusHeader.parseQuotaText` | `usage_quotas` | `parse_used / parse_limit` 格式化 |
| `statusHeader.qaQuotaText` | `usage_quotas` | `qa_used / qa_limit` 格式化 |
| `statusHeader.syncStatus` | `documents.current_stage`, `parse_jobs.status` | 有 `running` 则 `.syncing`，否则 `.idle` |
| `recentDocuments[]` | `documents + summaries` | `subtitle` 优先用 `one_line_summary`，没有则回退文件时间/状态 |
| `importantReminder` | `document_events + documents` | 仅取 `decision_status in (suggested, accepted)` 且未过期的高优先级事件 |

### `RecentDocumentRow.statusBadge` 映射

| 条件 | `DocumentBadgeState` |
|---|---|
| `lifecycle_status=detected` | `pending` |
| `lifecycle_status=processing` | `processing` |
| `lifecycle_status=waiting_user_confirmation` | `needsConfirmation` |
| `lifecycle_status=ready` 且 `event_status=has_candidate/has_accepted_event` | `hasEvent` |
| `lifecycle_status=ready` 且 `event_status=has_calendar_event` | `addedToCalendar` |
| `lifecycle_status=ready` 且 `has_summary=true` | `summarized` |
| `lifecycle_status=blocked` | `blocked` |
| `lifecycle_status=failed` | `failed` |

### 空态/边界态

| 条件 | UI |
|---|---|
| 最近无文件 | “最近还没有已导入文件” |
| 无重要提醒 | 隐藏提醒区或显示轻提示 |
| 有任务运行中 | 顶部显示“解析中” |

## 3. QuickPanelViewModel

### 输入源

- `search_sessions`
- 本地建议问题
- 搜索结果列表 / QA 输出
- 套餐与 quota

### 建议状态枚举

```swift
enum QuickPanelState {
    case idle(suggestions: [String])
    case retrieving
    case assembling
    case answering
    case searchResults([SearchResultItemViewData])
    case answer(AnswerResultViewData)
    case noResult(message: String)
    case blocked(reason: SearchBlockReason)
    case failed(message: String)
}
```

### 映射表

| `search_sessions.status` | ViewModel 状态 | UI 呈现 |
|---|---|---|
| `idle` | `.idle` | 显示 `SuggestionList` |
| `retrieving` | `.retrieving` | 输入框 loading + 骨架屏 |
| `assembling` | `.assembling` | 搜索模式中间态 |
| `answering` | `.answering` | QA 模式 loading |
| `success` 且 `mode=search` | `.searchResults` | `SearchResultList` |
| `success` 且 `mode=qa` | `.answer` | `AnswerResultView` |
| `no_result` | `.noResult` | 引导语 + follow-up 建议 |
| `blocked` | `.blocked` | 升级 CTA 或额度提示 |
| `failed` | `.failed` | 行内错误态，可重试 |

### `blocked` 文案映射

| `search_sessions.block_reason` | UI 文案 |
|---|---|
| `quota_exceeded` | 今日高级搜索/问答次数已用尽 |
| `feature_locked` | 当前套餐暂不支持此功能 |
| `empty_index` | 还没有可搜索的已解析文件 |

## 4. DocumentDetailViewModel

### 输入源

- `DocumentAggregate`
- `UsageQuotaRecord`
- `SubscriptionRecord`

### 建议状态拆分

不要做成单一大状态，建议拆成 5 个 section state：

- `headerState`
- `summaryState`
- `eventsState`
- `evidenceState`
- `sidebarActionsState`

### 详情主状态映射

| 条件 | `summaryState` | `eventsState` | `evidenceState` |
|---|---|---|---|
| `lifecycle_status=detected` | placeholder | hidden | hidden |
| `lifecycle_status=processing` | loading | loading/hidden | hidden |
| `waiting_user_confirmation` | gated | hidden | hidden |
| `ready` 且有 summary | content | 按事件聚合态渲染 | content |
| `ready` 但 summary 缺失 | failedInline | 按事件结果独立展示 | 若有 snippets 则 content |
| `blocked` | blocked(reason) | hidden | hidden |
| `failed` | failedInline | hidden | hidden |

### `SummaryHeroBlockProps` 映射

| Props 字段 | 来源 |
|---|---|
| `fileName` | `documents.file_name` |
| `documentType` | `document_summaries.document_type` |
| `oneLineSummary` | `document_summaries.one_line_summary` |
| `actionRequired` | `document_summaries.action_required` |
| `importance` | `documents.importance_score` 映射 `ImportanceLevel` |

### `EventCandidatesInspectorProps` 映射

| Props 字段 | 来源/规则 |
|---|---|
| `events` | `document_events` 过滤过期后映射成 `EventCandidateViewData` |
| `planAllowsCalendar` | `subscription.plan_type == pro` |
| `onAccept/onDismiss/onAddCalendar` | 调用 `EventsFeature` / `CalendarFeature` |

### 事件区状态映射

| 条件 | UI |
|---|---|
| 无事件 | “未识别到明确事件” |
| `decision_status=suggested` | 展示接受/忽略按钮 |
| `decision_status=accepted` 且 `calendar_status=not_added` | 展示加入日历按钮 |
| `calendar_status=adding` | 按钮 loading |
| `calendar_status=added` | 显示已入历 |
| `calendar_status=feature_locked` | 显示升级提示 |
| `calendar_status=failed` | 显示重试按钮 |

### 门禁状态映射

| 条件 | UI |
|---|---|
| `lifecycle_status=waiting_user_confirmation` | 展示 `RiskGateSheet` |
| `block_reason=privacy_confirmation_required` | 文案强调需确认后继续 |
| `privacy_status=blocked` | 详情页显示“该文件已按隐私策略跳过” |

## 5. DocumentSidebarViewModel

### 输入源

- 最近文档列表
- 当前选中的 `document_id`

### 输出映射

| 字段 | 规则 |
|---|---|
| `items[]` | 与 `RecentDocumentRow` 同一份 `RecentDocumentItemViewData` |
| `selectedID` | 当前详情页文档 ID |
| `filter` | 可按目录/状态扩展，但 MVP 可不做 |

## 6. Settings ViewModels

### GeneralSettingsViewModel

| 数据来源 | UI 输出 |
|---|---|
| App 配置 | 启动项、快捷键、默认行为 |

### DirectorySettingsViewModel

| 数据来源 | UI 输出 |
|---|---|
| `watch_directories` | 已授权目录列表、默认下载目录开关 |
| 权限错误 | 重新授权 CTA |

### PrivacySettingsViewModel

| 数据来源 | UI 输出 |
|---|---|
| 默认门禁策略 | 是否总是询问、是否信任目录 |
| 最近 `privacy_decisions` | 最近命中情况 |

### SubscriptionViewModel

| 数据来源 | UI 输出 |
|---|---|
| `subscriptions` | 当前套餐、到期状态 |
| `usage_quotas` | 解析/问答/搜索剩余额度 |

## 7. UI 标签与状态真集

| UI 标签 | 领域条件 |
|---|---|
| 待解析 | `lifecycle_status=detected` |
| 处理中 | `lifecycle_status=processing` |
| 需确认 | `lifecycle_status=waiting_user_confirmation` |
| 已摘要 | `lifecycle_status=ready && readiness_flags.has_summary=true` |
| 有事件 | `event_status=has_candidate || event_status=has_accepted_event` |
| 已入历 | `event_status=has_calendar_event` |
| 已阻断 | `lifecycle_status=blocked` |
| 失败 | `lifecycle_status=failed` |

## 8. 实现注意事项

1. ViewModel 不直接拼接数据库 raw value，先映射到 Domain enum
2. Quick Panel 的 loading 态必须区分 `retrieving`、`assembling`、`answering`
3. Detail Window 要允许“摘要成功但事件失败”的部分成功态
4. 升级 CTA 只在 `quota_exceeded`、`feature_locked` 等阻断原因下出现
5. 菜单栏与侧栏共用 `RecentDocumentItemViewData`，避免两套 badge 逻辑
