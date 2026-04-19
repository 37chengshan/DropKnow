# 落知（DropKnow）SwiftUI 组件规格与页面实现指南

> 适用范围：MenuBarExtra / Quick Panel / Detail Window / Settings / In-app Cards  
> 目标：把前端设计文档落成可直接切页面的组件规格，不再停留在“有这个页面”的抽象层

---

# 1. 文档目标

本文件用于定义：

1. 场景级页面结构
2. 组件层级与依赖关系
3. 每个组件的 props / state / actions
4. 页面间导航和数据来源
5. 第一版建议的文件级拆分

---

# 2. 场景结构

## 2.1 建议 Scene

- `MenuBarExtraScene`
- `QuickPanelScene`
- `DocumentDetailScene`
- `SettingsScene`
- `CardOverlayPresenter`

## 2.2 场景职责

| Scene | 职责 |
|---|---|
| MenuBarExtraScene | 状态总览、最近入口、快捷操作 |
| QuickPanelScene | 高级搜索 / 问答入口 |
| DocumentDetailScene | 文件详情、证据、事件、操作 |
| SettingsScene | 目录、隐私、通知、订阅设置 |
| CardOverlayPresenter | 普通文件卡片与事件卡片浮层 |

---

# 3. 页面树

```text
MenuBarExtraScene
├─ StatusHeader
├─ ImportantReminderSection
├─ RecentDocumentsSection
└─ QuickActionsSection

QuickPanelScene
├─ QueryInputBar
├─ ModeSegmentedControl
├─ SuggestionList
├─ SearchResultList / AnswerResultView
└─ BottomContextBar

DocumentDetailScene
├─ SidebarDocumentList
├─ DetailContentColumn
│  ├─ DetailHeader
│  ├─ SummaryHeroBlock
│  ├─ KeyPointsSection
│  ├─ ActionRequiredSection
│  ├─ EvidenceSnippetSection
│  └─ ErrorOrEmptyState
└─ InspectorColumn
   ├─ FileMetaInspector
   ├─ EventCandidatesInspector
   ├─ PrivacyInspector
   ├─ QuotaInspector
   └─ ActionButtons

SettingsScene
├─ GeneralSettingsView
├─ DirectorySettingsView
├─ ParsingSettingsView
├─ PrivacySettingsView
├─ NotificationSettingsView
├─ CalendarSettingsView
└─ SubscriptionSettingsView
```

---

# 4. 设计 Tokens 建议

## 4.1 间距

- `spaceXS = 4`
- `spaceS = 8`
- `spaceM = 12`
- `spaceL = 16`
- `spaceXL = 24`
- `spaceXXL = 32`

## 4.2 圆角

- 卡片：12
- 浮层卡片：16
- 输入框：10
- Badge：8

## 4.3 字体层级

- 标题：`.title3` / `.headline`
- 一句话摘要：`.body`
- 重点条目：`.subheadline`
- 元信息：`.caption`
- 状态提示：`.caption2`

---

# 5. 核心组件规格

## 5.1 `StatusHeader`

### 用途
菜单栏顶部状态区，展示 app 名称、今日额度、同步状态。

### Props
```swift
struct StatusHeaderProps {
    let appName: String
    let parseQuotaText: String
    let qaQuotaText: String
    let syncStatus: SyncStatus
}
```

### State
- 无本地 state，纯展示

### Actions
- 点击额度区域 -> 打开订阅页（可选）

---

## 5.2 `ImportantReminderRow`

### 用途
菜单栏与重要提醒页中的单条高优先级提醒。

### Props
```swift
struct ImportantReminderRowProps {
    let eventType: EventType
    let title: String
    let timeText: String?
    let locationText: String?
    let isAddedToCalendar: Bool
    let onOpenDetail: () -> Void
    let onAddCalendar: (() -> Void)?
}
```

### 状态
- hover
- loadingAddCalendar
- added

---

## 5.3 `RecentDocumentRow`

### 用途
菜单栏、最近文件页、侧栏列表中的文档行。

### Props
```swift
struct RecentDocumentRowProps {
    let fileIcon: String
    let fileName: String
    let subtitle: String
    let importedAtText: String
    let statusBadge: DocumentBadgeState
    let onTap: () -> Void
}
```

---

## 5.4 `QueryInputBar`

### 用途
Quick Panel 顶部输入框，支持搜索/问答共用。

### Props
```swift
struct QueryInputBarProps {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    let onClear: () -> Void
}
```

### 行为
- `Enter` 提交
- `Esc` 清空或关闭
- 支持 loading 状态

---

## 5.5 `ModeSegmentedControl`

### 用途
Quick Panel 中切换 `搜索` / `问答`

### Props
```swift
enum QuickMode { case search, qa }

struct ModeSegmentedControlProps {
    @Binding var mode: QuickMode
}
```

---

## 5.6 `SuggestionList`

### 用途
Quick Panel 默认推荐问题列表

### Props
```swift
struct SuggestionListProps {
    let suggestions: [String]
    let onSelect: (String) -> Void
}
```

---

## 5.7 `SearchResultRow`

### 用途
搜索模式下的单条结果

### Props
```swift
struct SearchResultRowProps {
    let title: String
    let subtitle: String
    let evidencePreview: String?
    let badges: [String]
    let onOpenDetail: () -> Void
    let onOpenFile: () -> Void
}
```

---

## 5.8 `AnswerResultView`

### 用途
问答模式下展示答案 + 证据

### Props
```swift
struct AnswerResultViewProps {
    let answer: String
    let citations: [CitationViewData]
    let followUps: [String]
    let onTapCitation: (CitationViewData) -> Void
}
```

---

## 5.9 `SummaryHeroBlock`

### 用途
详情页中心栏顶部，承载一句话摘要与主行动建议。

### Props
```swift
struct SummaryHeroBlockProps {
    let fileName: String
    let documentType: String
    let oneLineSummary: String
    let actionRequired: String
    let importance: ImportanceLevel
}
```

---

## 5.10 `KeyPointsSection`

### 用途
展示 3 条重点

### Props
```swift
struct KeyPointsSectionProps {
    let points: [String]
}
```

### 边界态
- points 为空时隐藏整个 section

---

## 5.11 `EvidenceSnippetSection`

### 用途
展示原文证据片段列表

### Props
```swift
struct EvidenceSnippetSectionProps {
    let snippets: [EvidenceSnippetViewData]
    let onOpenDetailLocation: (EvidenceSnippetViewData) -> Void
}
```

---

## 5.12 `EventCandidatesInspector`

### 用途
详情页右侧事件候选区

### Props
```swift
struct EventCandidatesInspectorProps {
    let events: [EventCandidateViewData]
    let planAllowsCalendar: Bool
    let onAccept: (String) -> Void
    let onDismiss: (String) -> Void
    let onAddCalendar: (String) -> Void
}
```

### 边界态
- 无事件时显示 “未识别到明确事件”
- 免费版显示“升级后可加入日历”

---

## 5.13 `RiskGateSheet`

### 用途
敏感文件门禁弹层

### Props
```swift
struct RiskGateSheetProps {
    let fileName: String
    let riskLevel: RiskLevel
    let ruleHits: [String]
    let onAllowOnce: () -> Void
    let onDeny: () -> Void
    let onAlwaysAsk: () -> Void
    let onTrustDirectory: () -> Void
}
```

---

## 5.14 `QuotaBadge`

### 用途
展示额度状态

### Props
```swift
struct QuotaBadgeProps {
    let parseText: String
    let qaText: String
    let searchText: String
    let isWarning: Bool
}
```

---

## 5.15 `SummaryCard`

### 用途
普通文件应用内卡片

### Props
```swift
struct SummaryCardProps {
    let fileName: String
    let oneLineSummary: String
    let keyPoints: [String]
    let onExpand: () -> Void
    let onDismiss: () -> Void
}
```

### 行为
- 3~5 秒自动消失
- hover 暂停消失

---

## 5.16 `ImportantEventCard`

### 用途
事件型文件应用内卡片

### Props
```swift
struct ImportantEventCardProps {
    let fileName: String
    let eventTypeLabel: String
    let summary: String
    let timeText: String?
    let locationText: String?
    let keyPoints: [String]
    let canAddCalendar: Bool
    let onAddCalendar: (() -> Void)?
    let onOpenDetail: () -> Void
    let onDismiss: () -> Void
}
```

---

# 6. 页面级数据源设计

## 6.1 MenuBarExtraScene

### 依赖 ViewModel
- `MenuBarViewModel`

### 提供数据
- 今日额度
- 最近 3 条文件
- 最近 1 条高优先级提醒
- 快捷操作入口

## 6.2 QuickPanelScene

### 依赖 ViewModel
- `QuickPanelViewModel`

### 提供数据
- 当前 mode
- query text
- suggestions
- search results
- answer result
- loading / empty / no result

## 6.3 DocumentDetailScene

### 依赖 ViewModel
- `DocumentDetailViewModel`
- `DocumentSidebarViewModel`

### 提供数据
- 当前 document
- summary
- events
- evidence snippets
- quota / privacy / file meta

## 6.4 SettingsScene

### 依赖 ViewModel
- `GeneralSettingsViewModel`
- `DirectorySettingsViewModel`
- `PrivacySettingsViewModel`
- `SubscriptionViewModel`

---

# 7. 导航与交互规则

## 7.1 菜单栏
- 点击最近文件 -> 打开 Detail Window 并选中文件
- 点击重要提醒 -> 打开 Detail Window 并滚到事件区
- 点击“打开快速面板” -> 拉起 Quick Panel
- 点击“设置” -> 打开 Settings

## 7.2 Quick Panel
- 输入后自动切换结果态
- 回车默认打开最佳结果详情
- `Cmd+Enter` 打开原文件
- 点击 follow-up suggestion 回填输入框并继续搜索

## 7.3 Detail Window
- 左侧选文件 -> 中间与右侧同步刷新
- 右侧点击加入日历 -> 更新 event 与 document 状态
- 重新解析 -> 显示行内 loading，不阻塞整个窗口

---

# 8. 第一版建议文件结构

```text
Features/UI/
├─ MenuBar/
│  ├─ MenuBarView.swift
│  ├─ StatusHeader.swift
│  ├─ ImportantReminderRow.swift
│  └─ RecentDocumentRow.swift
├─ QuickPanel/
│  ├─ QuickPanelView.swift
│  ├─ QueryInputBar.swift
│  ├─ ModeSegmentedControl.swift
│  ├─ SuggestionList.swift
│  ├─ SearchResultRow.swift
│  └─ AnswerResultView.swift
├─ Detail/
│  ├─ DocumentDetailView.swift
│  ├─ SidebarDocumentList.swift
│  ├─ SummaryHeroBlock.swift
│  ├─ KeyPointsSection.swift
│  ├─ EvidenceSnippetSection.swift
│  ├─ FileMetaInspector.swift
│  ├─ EventCandidatesInspector.swift
│  └─ ActionButtons.swift
├─ Cards/
│  ├─ SummaryCard.swift
│  ├─ ImportantEventCard.swift
│  └─ RiskGateSheet.swift
└─ Settings/
   ├─ SettingsRootView.swift
   ├─ GeneralSettingsView.swift
   ├─ DirectorySettingsView.swift
   ├─ PrivacySettingsView.swift
   ├─ CalendarSettingsView.swift
   └─ SubscriptionSettingsView.swift
```

---

# 9. 边界态清单

每个页面必须覆盖：

- 初始空态
- loading
- 无权限
- 额度耗尽
- 无结果
- 部分失败
- 完全失败

## 9.1 Quick Panel
- 无输入时显示建议
- 无结果时显示引导语
- 额度耗尽时显示升级 CTA

## 9.2 Detail Window
- 文档不存在
- 摘要失败但文本存在
- 事件为空
- 门禁阻止解析

## 9.3 MenuBar
- 最近无文件
- 无重要提醒
- 同步/解析中

---

# 10. 第一版实现顺序

## Step 1
- MenuBarView
- QuickPanelView
- SettingsRootView

## Step 2
- DocumentDetailView
- SummaryHeroBlock
- KeyPointsSection
- EventCandidatesInspector

## Step 3
- SummaryCard
- ImportantEventCard
- RiskGateSheet

## Step 4
- SearchResultRow
- AnswerResultView
- EvidenceSnippetSection

---

# 11. 最终建议

UI 不要一开始就追求复杂炫技。

第一版只要做到：

- 菜单栏轻
- Quick Panel 快
- Detail Window 清
- 卡片准
- 状态明

就已经足够支撑你当前产品主线。
