# Swift enum / DTO 对照表

本文档把数据库状态、Provider Schema 与 UI 组件规格统一映射为 Swift 可落地类型。建议所有枚举都采用 `String, Codable, Sendable`，所有 Provider DTO 都采用 `Codable`。

## 1. Domain Enums

### 文档与流水线

| Swift 类型 | 原始来源 | Raw Value |
|---|---|---|
| `DocumentLifecycleStatus` | `documents.lifecycle_status` | `detected`, `processing`, `waiting_user_confirmation`, `ready`, `blocked`, `failed` |
| `DocumentPipelineStage` | `documents.current_stage`, `parse_jobs.stage` | `import`, `parse`, `gate`, `summary`, `event_extract`, `index`, `notify`, `done` |
| `DocumentBlockReason` | `documents.block_reason` | `none`, `privacy_confirmation_required`, `quota_exceeded`, `feature_locked`, `unsupported_type`, `permission_denied`, `policy_blocked` |
| `DocumentParseStatus` | `documents.parse_status` | `success`, `partial`, `failed`, `unsupported` |
| `DocumentParseQuality` | `documents.parse_quality` | `good`, `medium`, `poor` |
| `SummaryStatus` | `documents.summary_status` | `pending`, `success`, `failed` |
| `DocumentEventStatus` | `documents.event_status` | `none`, `has_candidate`, `has_accepted_event`, `has_calendar_event`, `all_dismissed` |

### 事件与日历

| Swift 类型 | 原始来源 | Raw Value |
|---|---|---|
| `EventDecisionStatus` | `document_events.decision_status` | `suggested`, `accepted`, `dismissed`, `expired` |
| `EventCalendarStatus` | `document_events.calendar_status` | `not_added`, `adding`, `added`, `failed`, `feature_locked` |
| `EventType` | `document_events.event_type`, `EventExtractionTask` | `exam`, `assignment_deadline`, `registration_deadline`, `payment_deadline`, `class_schedule`, `meeting`, `interview`, `campus_activity`, `other` |

### 搜索与额度

| Swift 类型 | 原始来源 | Raw Value |
|---|---|---|
| `QuickMode` | `ModeSegmentedControl`、`search_sessions.mode` | `search`, `qa` |
| `SearchSessionStatus` | `search_sessions.status` | `idle`, `retrieving`, `assembling`, `answering`, `success`, `no_result`, `blocked`, `failed` |
| `SearchBlockReason` | `search_sessions.block_reason` | `none`, `quota_exceeded`, `feature_locked`, `empty_index` |
| `PlanType` | `subscriptions.plan_type` | `free`, `pro` |
| `SubscriptionStatus` | `subscriptions.status` | `active`, `expired`, `cancelled` |

### 隐私、风险与 Provider

| Swift 类型 | 原始来源 | Raw Value |
|---|---|---|
| `PrivacyStatus` | `documents.privacy_status` | `safe`, `flagged`, `blocked`, `user_allowed` |
| `RiskLevel` | `privacy_decisions.risk_level` | `low`, `medium`, `high` |
| `PrivacyDecision` | `privacy_decisions.decision` | `allow_once`, `deny`, `always_ask`, `trust_directory` |
| `ProviderType` | `providers.provider_type` | `zhipu`, `qwen` |
| `ProviderUsageRole` | `providers.usage_role` | `summary`, `event_extract`, `qa`, `embedding` |

## 2. Provider DTOs

### 通用输入 DTO

```swift
struct ProviderDocumentContextDTO: Codable, Sendable {
    let documentID: String
    let fileName: String
    let fileExtension: String
    let referenceDate: String
    let userTimezone: String
    let plainText: String
    let languageHint: String?
}
```

### SummaryTask

| Swift DTO | 对应 JSON |
|---|---|
| `SummaryTaskInputDTO` | 通用输入上下文 |
| `SummaryTaskOutputDTO` | Summary JSON Schema |
| `SummaryTimeSignalDTO` | `time_signals[]` |

```swift
struct SummaryTaskOutputDTO: Codable, Sendable {
    let documentType: SummaryDocumentType
    let oneLineSummary: String
    let actionRequired: String
    let keyPoints: [String]
    let timeSignals: [SummaryTimeSignalDTO]
    let locationSignals: [String]
    let supportingSnippets: [String]
    let riskFlags: [RiskFlag]
    let confidence: Double
}
```

### EventExtractionTask

| Swift DTO | 对应 JSON |
|---|---|
| `EventExtractionTaskInputDTO` | 通用输入上下文 |
| `EventExtractionTaskOutputDTO` | `event_candidates[]` 包装 |
| `EventCandidateDTO` | 单个事件候选 |

```swift
struct EventCandidateDTO: Codable, Sendable {
    let eventType: EventType
    let title: String
    let startTime: String?
    let endTime: String?
    let rawTimeText: String
    let location: String?
    let notes: String?
    let evidenceSnippet: String
    let confidence: Double
    let calendarEligible: Bool
}
```

### QATask

| Swift DTO | 对应 JSON |
|---|---|
| `QATaskInputDTO` | `question + retrieved_items` |
| `RetrievedItemDTO` | `retrieved_items[]` |
| `QAResponseDTO` | QA JSON Schema |
| `CitationDTO` | `citations[]` |

```swift
struct QAResponseDTO: Codable, Sendable {
    let answer: String
    let answerType: QAAnswerType
    let confidence: Double
    let citations: [CitationDTO]
}
```

## 3. 数据库 Record DTO

这些 DTO 用于 `Infrastructure/Database` 与 `Features/*` 之间传递扁平记录。

| Swift 类型 | 对应表 |
|---|---|
| `WatchDirectoryRecord` | `watch_directories` |
| `DocumentRecord` | `documents` |
| `DocumentTextRecord` | `document_texts` |
| `DocumentChunkRecord` | `document_chunks` |
| `DocumentSummaryRecord` | `document_summaries` |
| `DocumentEventRecord` | `document_events` |
| `PrivacyDecisionRecord` | `privacy_decisions` |
| `NotificationRecord` | `notifications` |
| `DocumentActionRecord` | `document_actions` |
| `ParseJobRecord` | `parse_jobs` |
| `ProviderRecord` | `providers` |
| `SubscriptionRecord` | `subscriptions` |
| `UsageQuotaRecord` | `usage_quotas` |
| `SearchSessionRecord` | `search_sessions` |

推荐最小结构：

```swift
struct DocumentRecord: Sendable {
    let id: String
    let watchDirectoryID: String?
    let fileName: String
    let fileExtension: String
    let absolutePath: String
    let fileHash: String
    let fileSize: Int64
    let importedAt: Date
    let sourceType: DocumentSourceType
    let lifecycleStatus: DocumentLifecycleStatus
    let currentStage: DocumentPipelineStage
    let blockReason: DocumentBlockReason
    let parseStatus: DocumentParseStatus?
    let parseQuality: DocumentParseQuality?
    let summaryStatus: SummaryStatus?
    let eventStatus: DocumentEventStatus
    let privacyStatus: PrivacyStatus?
    let readinessFlags: DocumentReadinessFlags
    let importanceScore: Double
    let lastErrorCode: String?
    let lastErrorMessage: String?
}
```

## 4. 聚合实体

这些类型适合放在 `Domain/Entities`，供 ViewModel 直接消费。

| 聚合实体 | 组成 |
|---|---|
| `DocumentAggregate` | `DocumentRecord + DocumentTextRecord? + DocumentSummaryRecord? + [DocumentEventRecord] + [ParseJobRecord]` |
| `SearchAnswerAggregate` | `SearchSessionRecord + QAResponseDTO? + [DocumentChunkRecord]` |
| `QuotaAggregate` | `SubscriptionRecord + UsageQuotaRecord` |

## 5. UI ViewData / Props 映射

### 组件 Props 对应 ViewData

| 组件 Props | 推荐 ViewData | 主要来源 |
|---|---|---|
| `StatusHeaderProps` | `StatusHeaderViewData` | 订阅 + quota + 同步状态 |
| `ImportantReminderRowProps` | `ReminderItemViewData` | `DocumentEventRecord + DocumentRecord` |
| `RecentDocumentRowProps` | `RecentDocumentItemViewData` | `DocumentRecord + DocumentSummaryRecord?` |
| `SearchResultRowProps` | `SearchResultItemViewData` | 搜索召回结果 |
| `AnswerResultViewProps` | `AnswerResultViewData` | `QAResponseDTO` |
| `SummaryHeroBlockProps` | `DocumentSummaryHeroViewData` | `DocumentRecord + DocumentSummaryRecord` |
| `EvidenceSnippetSectionProps` | `EvidenceSnippetListViewData` | `DocumentSummaryRecord + CitationDTO + chunk` |
| `EventCandidatesInspectorProps` | `EventCandidatesInspectorViewData` | `[DocumentEventRecord] + plan/quota` |
| `QuotaBadgeProps` | `QuotaBadgeViewData` | `UsageQuotaRecord + SubscriptionRecord` |

### UI 专用枚举

| Swift 类型 | 用途 |
|---|---|
| `DocumentBadgeState` | 菜单栏/侧栏文档状态 badge |
| `SyncStatus` | 顶部同步状态 |
| `ImportanceLevel` | `SummaryHeroBlock` 视觉强度 |
| `QAAnswerType` | 问答答案类型 |

建议 `DocumentBadgeState` 真集：

- `pending`
- `processing`
- `needsConfirmation`
- `summarized`
- `hasEvent`
- `addedToCalendar`
- `blocked`
- `failed`

## 6. 文件建议落位

| 文件路径 | 内容 |
|---|---|
| `DropKnow/Domain/Enums/DocumentEnums.swift` | 文档、阶段、阻断、事件聚合态 |
| `DropKnow/Domain/Enums/EventEnums.swift` | 事件、日历、风险、隐私 |
| `DropKnow/Domain/Enums/SearchEnums.swift` | 搜索、问答、QuickMode |
| `DropKnow/Domain/Enums/SubscriptionEnums.swift` | 套餐、额度、功能锁 |
| `DropKnow/Infrastructure/Providers/DTOs/SummaryDTOs.swift` | Summary 输入输出 |
| `DropKnow/Infrastructure/Providers/DTOs/EventDTOs.swift` | Event 输入输出 |
| `DropKnow/Infrastructure/Providers/DTOs/QADTOs.swift` | QA 输入输出 |
| `DropKnow/Infrastructure/Database/Records/*.swift` | 各表 Record |
| `DropKnow/Features/*/ViewData/*.swift` | 页面与组件 ViewData |

## 7. 关键约束

1. 所有状态枚举必须 exhaustive switch，不允许 `default`
2. 数据库 raw value、Provider JSON value、UI ViewData 枚举值必须一一对应
3. `DocumentAggregate` 允许部分结果缺失，不能把“事件抽取失败”硬转成“文档失败”
4. `DTO` 负责传输结构，`Entity` 负责业务语义，`ViewData` 负责展示裁剪
