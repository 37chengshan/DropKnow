# Provider 输入输出契约

本文档统一 `SummaryTask`、`EventExtractionTask`、`QATask` 三类模型能力的接入契约。Provider 可以替换，但请求信封、输出校验、错误码语义保持不变。

## 1. 支持 Provider

当前仅受控接入：

- `zhipu`
- `qwen`

不支持用户自填任意 OpenAI-compatible provider。

## 2. 通用契约

### 请求前置条件

1. 文件必须先完成 `parse`
2. `gate` 未放行时不得上云
3. 必须传 `reference_date`
4. 必须传 `user_timezone`
5. 统一要求纯 JSON 输出，不允许 provider 返回额外解释

### 通用输入信封

```json
{
  "document_id": "doc_xxx",
  "file_name": "大学英语期中考试安排.pdf",
  "file_extension": "pdf",
  "reference_date": "2026-04-18",
  "user_timezone": "Asia/Shanghai",
  "plain_text": "...",
  "language_hint": "zh-CN"
}
```

### 通用输出流程

1. 接收 provider 原始文本
2. 标准 JSON parse
3. parse 失败则本地 JSON repair
4. repair 后做 schema validate
5. validate 成功才允许入库
6. validate 失败则记错误码并最多重试一次

### 通用错误处理

| 场景 | 错误码 |
|---|---|
| Provider 超时 | `summary_provider_timeout`, `qa_provider_timeout` |
| 非法 JSON | `summary_invalid_json`, `event_invalid_json`, `qa_invalid_json` |
| 认证失败 | `summary_provider_auth_failed` |
| 限流 | `summary_provider_rate_limited` |
| 服务不可用 | `summary_provider_service_unavailable` |
| 网络离线 | `network_offline` |

## 3. SummaryTask 契约

### 用途

生成通知型摘要，供以下模块消费：

- `document_summaries`
- `SummaryHeroBlock`
- `SummaryCard`
- `RecentDocumentRow.subtitle`

### 输入

使用通用输入信封。

### 输出 Schema

| 字段 | 类型 | 说明 |
|---|---|---|
| `document_type` | enum | 文档分类 |
| `one_line_summary` | string | 一句话摘要 |
| `action_required` | string | 用户要做什么 |
| `key_points` | string[] | 1 到 3 条重点 |
| `time_signals` | object[] | 时间识别结果 |
| `location_signals` | string[] | 地点提示 |
| `supporting_snippets` | string[] | 1 到 2 条证据 |
| `risk_flags` | enum[] | 风险标记 |
| `confidence` | number | 整体置信度 |

### 入库映射

| Output 字段 | 数据库字段 |
|---|---|
| `document_type` | `document_summaries.document_type` |
| `one_line_summary` | `document_summaries.one_line_summary` |
| `action_required` | `document_summaries.action_required` |
| `key_points` | `document_summaries.key_points_json` |
| `time_signals` | `document_summaries.time_signals_json` |
| `location_signals` | `document_summaries.location_signals_json` |
| `supporting_snippets` | `document_summaries.supporting_snippets_json` |
| `risk_flags` | `document_summaries.risk_flags_json` |
| `confidence` | `document_summaries.confidence` |

### 最低成功条件

- `supporting_snippets.count >= 1`
- `risk_flags` 无风险时必须为 `[]`
- `confidence` 在 `0...1`

## 4. EventExtractionTask 契约

### 用途

抽取可进入“重要提醒”与“加入日历”链路的事件候选。

### 输入

使用通用输入信封。

### 输出 Schema

根对象：

```json
{ "event_candidates": [] }
```

单个候选：

| 字段 | 类型 | 说明 |
|---|---|---|
| `event_type` | enum | 事件类型 |
| `title` | string | 标题 |
| `start_time` | string/null | ISO 8601 或空 |
| `end_time` | string/null | ISO 8601 或空 |
| `raw_time_text` | string | 原文时间 |
| `location` | string/null | 地点 |
| `notes` | string/null | 备注 |
| `evidence_snippet` | string | 证据片段 |
| `confidence` | number | 置信度 |
| `calendar_eligible` | boolean | 是否可入历 |

### 入库映射

| Output 字段 | 数据库字段 |
|---|---|
| `event_type` | `document_events.event_type` |
| `title` | `document_events.title` |
| `start_time` | `document_events.start_time` |
| `end_time` | `document_events.end_time` |
| `raw_time_text` | `document_events.raw_time_text` |
| `location` | `document_events.location` |
| `notes` | `document_events.notes` |
| `evidence_snippet` | `document_events.evidence_snippet` |
| `confidence` | `document_events.confidence` |
| `calendar_eligible` | `document_events.calendar_eligible` |

### 业务约束

1. 发布时间、历史时间不抽为候选事件
2. 模糊时间允许低置信输出，但 `calendar_eligible=false`
3. 未识别到候选时返回 `event_candidates=[]`
4. `event_no_candidate` 不是失败，只代表无事件

## 5. QATask 契约

### 用途

基于本地召回结果生成带引用答案，供 `QuickPanelScene` 消费。

### 输入

```json
{
  "question": "高数考试在哪天？",
  "reference_date": "2026-04-18",
  "user_timezone": "Asia/Shanghai",
  "retrieved_items": [
    {
      "document_id": "doc_exam_001",
      "chunk_id": "chunk_002",
      "file_name": "高数考试安排.pdf",
      "snippet": "高等数学期中考试时间为4月26日晚上7点，地点B201。"
    }
  ]
}
```

### 输出 Schema

| 字段 | 类型 | 说明 |
|---|---|---|
| `answer` | string | 回答文本 |
| `answer_type` | enum | `direct_answer`, `summary_answer`, `not_found`, `uncertain` |
| `confidence` | number | 置信度 |
| `citations` | object[] | 引用列表 |

### 引用项

| 字段 | 类型 |
|---|---|
| `document_id` | string |
| `chunk_id` | string |
| `file_name` | string |
| `evidence_snippet` | string |

### 最低成功条件

- 只能引用 `retrieved_items`
- `not_found` 时 `citations=[]`
- 所有结论必须能被 citation 支撑

## 6. Provider Adapter 抽象

建议在 `Infrastructure/Providers` 定义统一协议：

```swift
protocol StructuredGenerationProvider {
    associatedtype Input: Encodable
    associatedtype Output: Decodable

    func generate(
        task: ProviderTask,
        input: Input,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> ProviderRawResponse
}
```

配套职责分层：

- `PromptBuilder`: 生成 system/user prompt
- `ProviderClient`: 发起网络请求
- `JSONRepairService`: 本地修复非法 JSON
- `SchemaValidator`: 校验输出结构
- `ProviderResultMapper`: DTO -> DB Record / Entity

## 7. Provider I/O 生命周期

1. `Parsing` 产出 `plain_text`
2. `PrivacyGate` 放行
3. `SummarizationService` 或 `EventExtractionService` 组装输入
4. `ProviderClient` 请求 `zhipu/qwen`
5. `JSONRepairService` 必要时修复
6. `SchemaValidator` 校验
7. 写入 `document_summaries` / `document_events`
8. 更新 `parse_jobs`
9. 触发 `NotificationPresenter`

QATask 额外步骤：

1. `SearchService` 先查 FTS/向量召回
2. 只把 `retrieved_items` 传给 provider
3. 输出写回 `search_sessions` 与 `QuickPanelViewModel`

## 8. 契约边界

### Provider 负责

- 结构化摘要
- 事件候选抽取
- 基于已召回证据的答案生成

### Provider 不负责

- 文件监听
- 去重
- 敏感门禁决策
- 本地索引构建
- 日历写入
- UI 状态推断

## 9. 实施检查表

1. 每类任务都要有独立 JSON Schema
2. 每类任务都要有本地 validator
3. 所有非法 JSON 都必须经过 repair 再 validate
4. 所有 Provider 错误都必须映射到统一错误码
5. `reference_date` 与 `user_timezone` 必须随请求下发
6. Provider 原始响应建议保留到调试日志，但不要直接作为成功结果入库
