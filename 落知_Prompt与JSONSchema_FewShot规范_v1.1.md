# 落知（DropKnow）Prompt 与 JSON Schema / Few-shot 规范 v1.1

> 适用阶段：Phase 1 / Phase 2 / Phase 3
> 
> 目标：统一摘要、事件抽取、高级搜索/问答三类模型任务的输入、输出、few-shot、修复策略与时间归一化规则，确保结果稳定、可解释、可调试、可长期扩展。

---

# 1. 设计目标

本文件解决以下问题：

1. 输出必须结构化，避免“好看但不可用”的自然语言漂移。
2. 时间、地点、行动建议、证据片段必须可被前端和数据库稳定消费。
3. 风险标记、事件候选、问答引用必须具备明确字段，不依赖 UI 猜测。
4. 没有足够证据时允许“不确定”，不允许编造。
5. provider 可替换，但 prompt / schema / repair 逻辑保持统一。

---

# 2. 模型任务拆分

本产品内只定义三类主要模型任务：

1. **SummaryTask**：通知型摘要
2. **EventExtractionTask**：事件候选抽取
3. **QATask**：高级搜索 / 问答结果生成

原则：
- Summary 不负责做完整问答。
- EventExtraction 不负责概括全文。
- QA 不直接读取原文件，而是基于召回片段作答。

---

# 3. 通用输入约定

所有任务统一传入以下上下文：

```json
{
  "document_id": "doc_xxx",
  "file_name": "大学英语期中考试安排.pdf",
  "file_extension": "pdf",
  "reference_date": "2026-04-18",
  "user_timezone": "Asia/Taipei",
  "plain_text": "...",
  "language_hint": "zh-CN"
}
```

## 3.1 `reference_date` 规则

必须提供 `reference_date`，用于时间归一化。

### 解释规则
- 文中没有年份时，优先按 `reference_date` 所在年份解释。
- 若文本明确是跨年学期或存在冲突，允许不归一化，只保留 `raw_text` 并降低置信度。
- 对“本周五”“下周一”“今晚 7 点”这类相对时间，必须结合 `reference_date` + `user_timezone` 做归一化。

---

# 4. SummaryTask

## 4.1 目标

把一份文件压缩成：
- 这是什么
- 你要做什么
- 关键时间/地点/对象
- 3 条重点
- 可用于详情页和提醒卡片的证据

## 4.2 System Prompt

```text
你是一个面向大学生与研究生的文件理解助手。
你的任务是把新下载的通知、考试安排、作业说明、活动通知等文件，提炼成“可行动的通知型摘要”。

必须遵守：
1. 只根据输入文本作答，不得补造事实。
2. 输出必须是合法 JSON，不得输出 JSON 之外的任何解释。
3. 摘要重点服务“用户要做什么”，不是泛泛概括。
4. 没有时间或地点时允许留空，不得猜测。
5. 若文本无法支撑明确结论，可降低置信度并在 supporting_snippets 中给出依据。
6. risk_flags 无风险时必须返回空数组 []，不能返回 "none"。
```

## 4.3 User Prompt 模板

```text
请基于下面文件内容，输出通知型摘要。

文件名：{{file_name}}
文件类型：{{file_extension}}
参考日期：{{reference_date}}
时区：{{user_timezone}}
正文：
{{plain_text}}
```

## 4.4 Summary JSON Schema

```json
{
  "type": "object",
  "required": [
    "document_type",
    "one_line_summary",
    "action_required",
    "key_points",
    "time_signals",
    "location_signals",
    "supporting_snippets",
    "risk_flags",
    "confidence"
  ],
  "properties": {
    "document_type": {
      "type": "string",
      "enum": [
        "exam_notice",
        "assignment_notice",
        "registration_notice",
        "payment_notice",
        "class_change_notice",
        "event_notice",
        "general_notice",
        "study_material",
        "unknown"
      ]
    },
    "one_line_summary": {
      "type": "string",
      "maxLength": 120
    },
    "action_required": {
      "type": "string",
      "maxLength": 120
    },
    "key_points": {
      "type": "array",
      "items": { "type": "string", "maxLength": 80 },
      "minItems": 1,
      "maxItems": 3
    },
    "time_signals": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["raw_text", "normalized_time", "precision", "confidence"],
        "properties": {
          "raw_text": { "type": "string" },
          "normalized_time": { "type": ["string", "null"] },
          "precision": {
            "type": "string",
            "enum": ["date", "minute", "time_only", "range", "unknown"]
          },
          "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
        }
      },
      "maxItems": 3
    },
    "location_signals": {
      "type": "array",
      "items": { "type": "string" },
      "maxItems": 3
    },
    "supporting_snippets": {
      "type": "array",
      "items": { "type": "string", "maxLength": 140 },
      "minItems": 1,
      "maxItems": 2
    },
    "risk_flags": {
      "type": "array",
      "items": {
        "type": "string",
        "enum": [
          "contains_personal_info",
          "contains_student_id",
          "contains_phone_number",
          "contains_id_number",
          "contains_financial_info",
          "contains_medical_info"
        ]
      }
    },
    "confidence": {
      "type": "number",
      "minimum": 0,
      "maximum": 1
    }
  }
}
```

## 4.5 Summary Few-shot：正样例

### 样例 A：考试通知

**输入摘要：**
- 文件名：大学英语期中考试安排.pdf
- 参考日期：2026-04-18
- 正文含：4月25日19:00，A302，携带学生证

**理想输出：**

```json
{
  "document_type": "exam_notice",
  "one_line_summary": "这是大学英语期中考试安排通知。",
  "action_required": "按时参加考试并携带学生证。",
  "key_points": [
    "考试时间为 4 月 25 日 19:00",
    "考试地点在 A302",
    "需携带学生证"
  ],
  "time_signals": [
    {
      "raw_text": "4月25日19:00",
      "normalized_time": "2026-04-25T19:00:00+08:00",
      "precision": "minute",
      "confidence": 0.97
    }
  ],
  "location_signals": ["A302"],
  "supporting_snippets": [
    "考试时间：4月25日19:00，地点：A302",
    "请携带学生证参加考试"
  ],
  "risk_flags": [],
  "confidence": 0.95
}
```

### 样例 B：一般通知

```json
{
  "document_type": "general_notice",
  "one_line_summary": "这是课程资料领取通知。",
  "action_required": "按要求领取课程资料。",
  "key_points": [
    "请在本周内到办公室领取",
    "领取对象为本课程学生",
    "逾期可能影响资料发放"
  ],
  "time_signals": [],
  "location_signals": ["学院办公室"],
  "supporting_snippets": [
    "请于本周内到学院办公室领取课程资料"
  ],
  "risk_flags": [],
  "confidence": 0.83
}
```

## 4.6 Summary Few-shot：负样例

### 负样例 A：发布日期不是事件

文本：
- “通知发布时间：4月12日”
- 正文没有任何截止或活动安排

要求：
- 可以保留时间信号
- 不要把它当成需要提醒的事件
- `action_required` 不要编造“请于4月12日完成”

### 负样例 B：历史时间不是当前待办

文本：
- “上周已完成选课”

要求：
- 不要生成正在进行的待办
- 允许输出一般说明，但不生成事件候选倾向

---

# 5. EventExtractionTask

## 5.1 目标

从文件中抽出可进入“重要提醒”与“加入日历”链路的事件候选。

## 5.2 System Prompt

```text
你是一个事件抽取器。
你的任务是从文件内容中抽取考试、DDL、报名、缴费、课程变更、活动通知等可行动事件。

必须遵守：
1. 只输出合法 JSON。
2. 只抽取文本中有明确证据支持的事件。
3. 多个时间存在时，只把真正需要用户行动的时间当成主要事件。
4. 发布日期、历史记录、说明性背景时间，不应被当作事件。
5. “近期”“尽快”“本周内”等模糊时间，不能生成高置信度可入历事件。
6. 若时间不足以精确归一化，可保留 raw_text，并降低 confidence。
```

## 5.3 User Prompt 模板

```text
请从下面文件中抽取事件候选。

文件名：{{file_name}}
参考日期：{{reference_date}}
时区：{{user_timezone}}
正文：
{{plain_text}}
```

## 5.4 Event JSON Schema

```json
{
  "type": "object",
  "required": ["event_candidates"],
  "properties": {
    "event_candidates": {
      "type": "array",
      "items": {
        "type": "object",
        "required": [
          "event_type",
          "title",
          "start_time",
          "end_time",
          "raw_time_text",
          "location",
          "notes",
          "evidence_snippet",
          "confidence",
          "calendar_eligible"
        ],
        "properties": {
          "event_type": {
            "type": "string",
            "enum": [
              "exam",
              "assignment_deadline",
              "registration_deadline",
              "payment_deadline",
              "class_schedule",
              "meeting",
              "interview",
              "campus_activity",
              "other"
            ]
          },
          "title": { "type": "string", "maxLength": 80 },
          "start_time": { "type": ["string", "null"] },
          "end_time": { "type": ["string", "null"] },
          "raw_time_text": { "type": "string" },
          "location": { "type": ["string", "null"] },
          "notes": { "type": ["string", "null"] },
          "evidence_snippet": { "type": "string", "maxLength": 160 },
          "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
          "calendar_eligible": { "type": "boolean" }
        }
      },
      "maxItems": 5
    }
  }
}
```

## 5.5 Event Few-shot：正样例

### 样例 A：作业截止

```json
{
  "event_candidates": [
    {
      "event_type": "assignment_deadline",
      "title": "高等数学作业提交截止",
      "start_time": "2026-04-21T23:59:00+08:00",
      "end_time": null,
      "raw_time_text": "4月21日23:59前",
      "location": "课程平台",
      "notes": "请按要求提交 PDF 版作业。",
      "evidence_snippet": "请于4月21日23:59前在课程平台提交 PDF 版作业。",
      "confidence": 0.96,
      "calendar_eligible": true
    }
  ]
}
```

## 5.6 Event Few-shot：负样例

### 负样例 A：发布时间不抽事件

文本：
- “通知发布时间：4月12日”
- “报名截止：4月20日”

要求：
- 只抽“报名截止”
- 不抽“通知发布时间”

### 负样例 B：模糊时间不应可入历

文本：
- “请近期完成缴费”

理想输出：
- 可输出低置信度候选，也可不输出
- 若输出则 `calendar_eligible = false`

### 负样例 C：多个时间，只有一个是真截止

文本：
- “4月18日答疑，4月21日提交截止”

要求：
- 允许抽两个事件
- 但“提交截止”的优先级更高

---

# 6. QATask

## 6.1 目标

基于本地召回结果，生成带证据的简洁答案。

## 6.2 输入约定

QATask 不直接吃原始全文，而是吃召回结果：

```json
{
  "question": "高数考试在哪天？",
  "reference_date": "2026-04-18",
  "user_timezone": "Asia/Taipei",
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

## 6.3 System Prompt

```text
你是一个基于已召回证据作答的问答助手。

必须遵守：
1. 只能使用 retrieved_items 中的内容回答。
2. 若证据不足，直接回答未找到，不得补造。
3. 输出必须是合法 JSON。
4. 所有结论必须可被 citations 支撑。
```

## 6.4 QA JSON Schema

```json
{
  "type": "object",
  "required": ["answer", "answer_type", "confidence", "citations"],
  "properties": {
    "answer": { "type": "string", "maxLength": 200 },
    "answer_type": {
      "type": "string",
      "enum": ["direct_answer", "summary_answer", "not_found", "uncertain"]
    },
    "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
    "citations": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["document_id", "chunk_id", "file_name", "evidence_snippet"],
        "properties": {
          "document_id": { "type": "string" },
          "chunk_id": { "type": "string" },
          "file_name": { "type": "string" },
          "evidence_snippet": { "type": "string", "maxLength": 160 }
        }
      },
      "maxItems": 3
    }
  }
}
```

## 6.5 QA Few-shot

### 样例 A：直接答案

```json
{
  "answer": "高等数学期中考试在 4 月 26 日晚上 7 点举行，地点是 B201。",
  "answer_type": "direct_answer",
  "confidence": 0.94,
  "citations": [
    {
      "document_id": "doc_exam_001",
      "chunk_id": "chunk_002",
      "file_name": "高数考试安排.pdf",
      "evidence_snippet": "高等数学期中考试时间为4月26日晚上7点，地点B201。"
    }
  ]
}
```

### 样例 B：未找到

```json
{
  "answer": "我没有在已解析文件中找到明确的高数考试时间。",
  "answer_type": "not_found",
  "confidence": 0.18,
  "citations": []
}
```

---

# 7. 风险标记规则

## 7.1 `risk_flags`

只允许以下值：

- `contains_personal_info`
- `contains_student_id`
- `contains_phone_number`
- `contains_id_number`
- `contains_financial_info`
- `contains_medical_info`

## 7.2 约束

- 无风险时必须返回 `[]`
- 严禁返回 `"none"`
- 严禁返回未定义字符串

---

# 8. 时间归一化规则

## 8.1 强制规则

- 若文中有明确日期和时间，则尽量输出 ISO 8601 字符串。
- 若只有日期没有时间，可输出当天 00:00 或保留 `null`，但必须在说明中保持一致。建议对事件抽取：
  - `start_time` 可填 `YYYY-MM-DDT00:00:00+08:00`
  - 若不适合，允许 `null` + `raw_time_text`
- 若只有相对时间，必须结合 `reference_date` 和 `user_timezone`。
- 若无法确定，不得硬猜。

## 8.2 模糊表达处理

| 原文 | 处理方式 |
|---|---|
| 本周五 | 尝试归一化，保留 raw_text |
| 下周一 | 尝试归一化，保留 raw_text |
| 近期 / 尽快 | 不归一化，高置信日历候选为 false |
| 晚上 7 点 | 若无具体日期，不单独作为可入历事件 |

---

# 9. 非法 JSON 修复策略

## 9.1 适用范围

- `summary_invalid_json`
- `event_invalid_json`
- `qa_invalid_json`

## 9.2 修复流程

1. 尝试标准 JSON parse
2. 若失败，进入本地 JSON repair
3. repair 成功则再做 schema validate
4. validate 成功则入库
5. validate 失败则记错误码并最多重试一次模型请求

## 9.3 禁止行为

- 不允许 repair 后擅自补字段值
- 不允许把缺关键字段的结果当成功入库

---

# 10. 字段缺省规则

## SummaryTask

- `time_signals = []`
- `location_signals = []`
- `risk_flags = []`
- `supporting_snippets` 至少 1 条

## EventExtractionTask

- 未抽到事件时：`event_candidates = []`
- `calendar_eligible` 默认取决于时间清晰度 + 置信度

## QATask

- 未命中时：`answer_type = not_found`
- `citations = []`

---

# 11. 实施建议

## 11.1 先定 Schema，再接 Provider

顺序建议：
1. 固化 JSON Schema
2. 写本地 validator
3. 再接 Zhipu / Qwen
4. 再写 prompt 微调与 few-shot 扩样

## 11.2 Few-shot 扩样优先级

优先补以下样本：

1. 考试通知
2. 作业截止
3. 报名截止
4. 缴费截止
5. 活动通知
6. 发布日期 / 历史时间负样例
7. 多时间混合样例
8. 模糊时间样例

## 11.3 评估指标建议

- Schema valid rate
- 时间归一化成功率
- 高置信度事件 precision
- QA 引用完整率
- risk_flags 假阳性 / 假阴性

---

# 12. 最终推荐最小真集

## Summary 输出核心字段
- `document_type`
- `one_line_summary`
- `action_required`
- `key_points`
- `time_signals`
- `location_signals`
- `supporting_snippets`
- `risk_flags`
- `confidence`

## Event 输出核心字段
- `event_type`
- `title`
- `start_time`
- `end_time`
- `raw_time_text`
- `location`
- `notes`
- `evidence_snippet`
- `confidence`
- `calendar_eligible`

## QA 输出核心字段
- `answer`
- `answer_type`
- `confidence`
- `citations[document_id, chunk_id, file_name, evidence_snippet]`
