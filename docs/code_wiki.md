# DropKnow Code Wiki

> 本文面向工程视角，覆盖仓库整体架构、主要模块职责、关键类型/函数、依赖关系与运行方式。  
> 仓库包含两部分：`DropKnow`（macOS Swift 应用）与 `zvec-main`（向量数据库引擎子仓，C++/Python 绑定）。

## 1. 仓库概览

### 1.1 顶层目录结构

- `Sources/DropKnow/`：macOS 应用主体（SwiftUI + AppKit）
- `Tests/DropKnowTests/`：单元测试
- `script/build_and_run.sh`：一键构建与运行脚本（同时准备 Python venv）
- `docs/`：文档（包含本 Code Wiki）
- `zvec-main/`：zvec 向量数据库源码子仓（超大；DropKnow 运行时通常使用 `pip install zvec` 的已编译包）

### 1.2 产品/技术目标（一句话）

“自动监听下载目录 → 解析文件（PDF/DOCX/TXT/MD）→ 本地启发式摘要/事件候选/敏感识别 →（可选）远端精修 → 建立本地向量索引 → 提供语义搜索与问答，并在用户确认后写入系统日历。”

核心入口文件：
- [DropKnowApp.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/App/DropKnowApp.swift)：应用入口
- [AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift)：全局状态与业务编排中心
- [DocumentParser.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/DocumentParser.swift)：解析与本地启发式理解
- [RAGService.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/RAGService.swift)：Swift ↔ Python RAG 桥接
- [rag_helper.py](file:///Users/cc/Desktop/dk/Sources/DropKnow/Scripts/rag_helper.py)：Python 侧 embedding/zvec/检索/精修实现

## 2. 总体架构

### 2.1 运行时组件与数据流

```text
macOS App (SwiftUI)
  |
  | 8s 轮询触发扫描
  v
DirectoryMonitor  ──>  AppStore.scanForNewFiles()
                          |
                          | enqueue ParseJob
                          v
                     ProcessingEngine (actor 队列/额度/重试/批处理)
                          |
                          | nextWorkItem() -> parse / refine / indexBatch
                          v
  parse: DocumentParser.parse()
        |-> SensitiveFileDetector / PriorityClassifier / EventExtractor / SummaryBuilder
        v
  refine(可选): RAGService.refine() -> Python rag_helper.py (DashScope Chat)
        v
  indexBatch: RAGService.indexBatch() -> Python rag_helper.py
        |-> DashScope Embeddings -> zvec collection + sqlite chunks.sqlite3
        v
  UI 展示：Recent/Reminders/Search/Queue
  外部动作：NotificationService 通知；CalendarService 写入日历
```

### 2.2 关键状态与持久化

应用将状态写入用户目录 `Application Support/DropKnow/`（见 [Paths.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Support/Paths.swift)）：

- `dropknow_state.json`：文件列表与每个文件的解析/索引账本（`[DropFile]`）
- `dropknow_runtime.json`：后台队列状态（`RuntimeState`，含 parse/index jobs 与每日 usage）
- `settings.json`：用户设置（监听目录、额度、敏感策略等）
- `RAG/`：RAG 本地存储目录
  - `chunks.sqlite3`：chunk 元数据表
  - `zvec_collection_{model}_{dim}/`：zvec collection 存储（每个 embedding model/dim 一套）
- `providers.local.json`：Python 侧模型/端点配置覆盖文件（位于 `Application Support/DropKnow/` 根目录；由 Python 逻辑决定）

## 3. DropKnow（Swift 应用）模块说明

### 3.1 App 层（入口与生命周期）

- [DropKnowApp](file:///Users/cc/Desktop/dk/Sources/DropKnow/App/DropKnowApp.swift#L1-L46)
  - `@main` 入口：创建 `AppStore`，注入到 `ContentView` 和菜单栏/设置页
  - Command 快捷键：
    - 导入最近 7 天：`store.importRecentFiles(...)`
    - 重新解析所选：`store.reparseSelection()`
    - 补齐缺失索引：`store.rebuildSemanticIndex()`
- [AppDelegate](file:///Users/cc/Desktop/dk/Sources/DropKnow/App/AppDelegate.swift#L1-L9)
  - 启动时将应用激活策略设为 `.regular` 并请求通知权限

### 3.2 Store 层（全局状态与业务编排）

#### AppStore：系统“大脑”

文件：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift)

职责：
- 持有并连接所有服务：`DirectoryMonitor / ProcessingEngine / RAGService / CalendarService / NotificationService`
- 管理 UI 状态：文件列表、选中项、队列摘要、搜索与聊天消息、Toast/Alert 等
- 触发“导入/监听/重解析/索引回填/搜索/写日历”等动作
- 驱动后台处理循环：`runProcessingLoop()` 按 `ProcessingEngine.nextWorkItem()` 拉取任务执行

关键方法：
- 监听与导入
  - `scanForNewFiles()`：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift#L509-L521)  
    基于 `DirectoryMonitor.newStableFiles()` 找到新增稳定文件并入队（受日配额限制）。
  - `importRecentFiles(showToast:)`：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift#L486-L503)  
    枚举监听目录内最近 N 天支持格式文件，并入队。
  - `enqueueParse(url:trigger:...)`：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift#L802-L870)  
    创建/更新 `DropFile` skeleton，入队 `ParseJob`，并触发处理循环。
- 处理循环
  - `runProcessingLoop()`：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift#L886-L903)  
    循环拉取 `ProcessingWorkItem`（parse/refine/indexBatch）并执行。
  - `handleParse(_:)`：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift#L927-L1045)  
    指纹计算 → 增量跳过判断 → DocumentParser.parse → 敏感门禁 → 产出 `ProcessingIndexSeed`。
  - `handleRefine(_:)`：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift#L1047-L1072)  
    调用 Python helper（LLM）精修摘要/优先级/是否保留事件。
  - `handleIndexBatch(_:)`：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift#L1074-L1149)  
    批量写入向量索引（embedding + zvec + sqlite metadata），回填 `DropFile` 的索引账本字段，更新通知与配额计数。
- 搜索与问答
  - `performSearch()`：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift#L738-L789)
    - “查文件类问题”：走 `rag.search()`（语义检索 + 基于证据的回答）
    - “通用问题”：走 `rag.chat()`（纯聊天）
    - 两者均受 `ProcessingEngine` 的每日额度控制（search/chat）
- 日历写入
  - `addEventToCalendar(eventID:in:)`：[AppStore.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Stores/AppStore.swift#L625-L649)  
    Pro 计划才允许写入（`PlanCapabilities.canUseCalendarWrite`）。

### 3.3 Models 层（核心数据结构）

文件：[DropModels.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Models/DropModels.swift)

核心类型（建议从这些类型理解全链路）：
- `DropFile`：单个文件的“业务实体 + 处理账本”
  - 文件属性：`fileName/filePath/fileKind/importedAt/modifiedAt/fileSize/textLength`
  - 状态字段：`parsedStatus/sensitivityStatus/priorityLevel/summary/events/snippets/errorMessage`
  - 增量账本：`contentHash/parserVersion/summaryVersion/refineModel/embeddingModel/indexedContentHash/indexedAt/refinedContentHash/refinedAt/activeIndexRevision`
- `FileSummary`：UI 展示的结构化摘要（类型标签、行动提示、关键时间/地点、要点、单行总结）
- `EventCandidate`：可加入日历的事件候选（类型/标题/时间/地点/证据/置信度）
- `SearchResult/SearchHit`：语义搜索结果与命中片段。搜索结果现在包含结构化 diagnostics、query mode、evidence hit metadata、chunk index 和 active revision 信息，供聊天证据卡与文件详情定位使用。
- `DropSettings/SubscriptionPlan/PlanCapabilities`：监听目录/敏感策略/额度与订阅能力开关

### 3.4 Services 层（基础能力）

#### DirectoryMonitor：目录扫描与“稳定文件”判断

文件：[DirectoryMonitor.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/DirectoryMonitor.swift)

- `start()`：8 秒定时触发 `onTick`
- `newStableFiles(...)`：
  - 递归枚举目录，过滤隐藏/包内容
  - 跳过临时下载文件（`.download/.crdownload/.tmp/~$`）
  - 通过 `modifiedAt` 距离当前时间 > 2s 判断写入稳定
  - 依赖 `seen` 集合做一次性去重（仅内存态；重启后由 `AppStore` 用已保存文件路径补齐）

#### DocumentParser：解析 + 启发式理解（本地、低成本）

文件：[DocumentParser.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/DocumentParser.swift)

能力拆分：
- 格式解析
  - `parsePDF(_:)`：PDFKit 逐页提取文本
  - `parseDOCX(_:)`：`/usr/bin/unzip -p` 抽取 `word/document.xml` 再正则清洗标签
  - `TXT/MD`：直接按 UTF-8 读文件
- 文本处理
  - `normalize(_:)`：空白/换行规整
  - `makeChunks(from:)`：按段落聚合 chunk（约 900 字符阈值）
- 语义启发式
  - `SensitiveFileDetector.detect(...)`：命中关键字/正则（手机号、身份证、key/token 等）判定疑似敏感
  - `EventExtractor.extract(...)`：日期抽取（NSDataDetector + 中文日期 regex），生成最多 3 个候选事件
  - `PriorityClassifier.classify(...)`：根据“低价值信号/行动关键字/事件置信度”粗分重要等级
  - `SummaryBuilder.build(...)`：构造 `FileSummary`（含行动提示与单行摘要）

单测覆盖示例：
- [DocumentParserHeuristicsTests.swift](file:///Users/cc/Desktop/dk/Tests/DropKnowTests/DocumentParserHeuristicsTests.swift)

#### ProcessingEngine：后台队列/重试/额度/批处理（actor）

文件：[ProcessingEngine.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/ProcessingEngine.swift)

核心职责：
- 维护 `RuntimeState`（解析队列、索引队列、每日 usage）并持久化到 `dropknow_runtime.json`
- 控制入队与去重
  - `enqueueParse(...)`：同路径且 queued/parsing 视为重复
  - `canEnqueueParse(...)`：检查每日解析额度 + 已排队任务的“预占位”
- 任务调度与批处理
  - `nextWorkItem(...)`：
    - parse 优先
    - 然后 refine（仅 `requiresRefine == true` 的 index job）
    - 最后 indexBatch（将多个 index job 合并，受 max files/chunks/chars 限制）
- 重试与退避
  - `failParse/failIndex`：按 attemptCount 设置 `nextRetryAt`（30s、300s…）
  - `earliestRetryDate()`：供 `AppStore` 做“定时唤醒”
- 配额计数
  - `consumeUserQuota(.parse/.search/.chat)`：用户触发型额度
  - `recordInternalUsage(.refine/.embeddingFiles/.embeddingChunks)`：内部成本指标（refine、embedding 文件/chunk 数）

#### ProcessingPolicy：增量账本与“是否跳过”逻辑

文件：[ProcessingPolicy.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/ProcessingPolicy.swift)

- `FileFingerprintService.fingerprint(...)`：SHA-256 内容指纹（同时读出 modifiedAt/fileSize）
- `FileProcessingPolicy.shouldSkipProcessing(...)`：
  - 在 `DropFile` 已索引且 content hash/version/model 全匹配时跳过
  - 若该文件按策略需要远端精修（高优先级或高置信事件），则额外检查 refined 账本字段

#### RAGService：Swift ↔ Python helper 的进程边界

文件：[RAGService.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/RAGService.swift)

接口（对上层 AppStore 暴露）：
- `indexBatch(files:)`：批量索引（embedding + 入库）
- `search(query:topK:)`：语义检索（命中 chunks）并返回基于证据的回答
- `chat(query:)`：通用聊天（与文件无关）
- `diagnostics()`：读取 RAG store 元数据统计、provider/zvec 状态、chunk 数和 active revision 数，供 Settings 诊断区展示。
- `refine(fileName:text:summary:priority:events:)`：精修摘要/优先级/是否保留事件

实现要点：
- Python 脚本打包为 SwiftPM resource：见 [Package.swift](file:///Users/cc/Desktop/dk/Package.swift#L4-L27)
- 进程调用：`Process()` 执行 `python rag_helper.py <mode> --store <path>`，通过 stdin/stdout 传 JSON
- Python 解释器选择：优先 `.venv/bin/python`，否则退回 `/usr/bin/python3`
- 超时策略：索引 75s，搜索/聊天 35s
- Settings 暴露 RAG metadata counts、空索引状态、RAG store 路径、provider 配置来源和最近 RAG 错误，方便内部测试与环境排查。
- `script/verify_rag_fixtures.py` 是 V1 RAG 路径的可重复 fixture 验证命令；当前机器若缺少 zvec，会得到分类错误 `MISSING_ZVEC`，不能当作 fixture 通过。

#### NotificationService：本地通知与点击回跳

文件：[NotificationService.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/NotificationService.swift)

- `requestAuthorization()`：申请通知权限
- `notifyParsedFile(...)`：解析完成后发通知（15 分钟内按 fileID 去重）
- `didReceive response`：点击通知后通过 `onOpenFile(fileID, anchor)` 让 `AppStore` 导航到对应文件详情位置

#### CalendarService：写入系统日历（EventKit）

文件：[CalendarService.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/CalendarService.swift)

- `add(event:file:)`：请求权限 → 选择可写 calendar → 写入 `EKEvent`
- 写入策略：
  - 无具体时刻则 `isAllDay = true`
  - notes 中附带来源文件路径与证据片段

### 3.5 Views 层（UI 组织）

目录：[Sources/DropKnow/Views](file:///Users/cc/Desktop/dk/Sources/DropKnow/Views)

页面结构由 [AppSection.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Models/AppSection.swift) 定义：
- `最近下载`：浏览已导入/已解析文件
- `处理队列`：查看 parse/index jobs 的排队与失败重试
- `重要提醒`：聚合高价值/可行动文件
- `AI 问答`：语义搜索 + 通用聊天
- `升级订阅`、`设置`

## 4. Python RAG Helper（rag_helper.py）

文件：[rag_helper.py](file:///Users/cc/Desktop/dk/Sources/DropKnow/Scripts/rag_helper.py)

### 4.1 主要职责

- 统一提供 5 个子命令模式：`index / index_batch / search / refine / chat`
- 依赖外部 embedding/chat 服务（默认 DashScope），并将向量写入本地 zvec collection
- 同步维护 sqlite 元数据（chunk_text、file 信息、active revision）

### 4.2 配置与环境变量

默认配置来源（优先级从高到低）：
1. `Application Support/DropKnow/providers.local.json`（存在则覆盖）
2. 环境变量
3. 代码默认值

关键项（见 `load_provider_config`）：
- `DASHSCOPE_API_KEY`：DashScope API Key（必需，用于 embedding/chat；缺失将导致 index/search/chat/refine 失败）
- `DROPKNOW_EMBEDDING_MODEL`：embedding 模型名（默认 `tongyi-embedding-vision-flash-2026-03-06`）
- `DROPKNOW_EMBEDDING_DIMENSION`：向量维度（默认 768）
- `DROPKNOW_EMBEDDING_ENDPOINT`：embedding endpoint
- `DROPKNOW_CHAT_MODEL`：chat/refine 模型名（默认 `qwen3.5-flash`）
- `DROPKNOW_CHAT_ENDPOINT`：chat endpoint

### 4.3 本地存储与索引组织

- 元数据 SQLite：`<store>/chunks.sqlite3`
  - `chunks(chunk_id, file_id, revision_id, file_name, file_path, chunk_index, text)`
  - `active_revisions(file_id, revision_id, activated_at)`：用于“同一 file_id 多 revision 并存时只激活一版”
- zvec collection：`<store>/zvec_collection_{embedding_model}_{dimension}/`
  - schema 字段：`file_id/file_name/file_path/chunk_index`，向量列 `embedding`

### 4.4 关键流程（函数级）

- `index_batch(payload, store)`：
  - 批量对所有 chunks 做 embedding（`dashscope_embeddings`）
  - upsert 到 sqlite `chunks` 并更新 `active_revisions`
  - 使用 zvec `collection.upsert(docs); flush()`
- `search(payload, store)`：
  - query embedding → zvec `collection.query(...)`
  - 通过 sqlite 回表拿到 active revision 的 chunk 文本作为 `snippet`
  - 如命中则用 `chat_answer(query, hits)` 给出“基于证据的回答”，否则回退“最相关 chunk 片段”
- `refine(payload, store)`：
  - `chat_classify` 调用 chat endpoint，严格输出 JSON
  - 返回修正后的 `summary/priorityLevel/keepEvents`
- `chat(payload, store)`：
  - `general_chat_answer` 直接调用 chat endpoint

## 5. zvec-main（向量数据库子仓）定位说明

`zvec-main/` 是 zvec 的完整源码树（C++/CMake + Python 绑定），在本仓库中主要作为：
- 研究/调试：需要时可从源码构建 zvec 或阅读内部实现
- 对照依赖：DropKnow 的 Python helper 运行时通常使用 `pip install zvec` 获取 wheel（见 `script/build_and_run.sh`）

建议优先阅读：
- [zvec-main/README.md](file:///Users/cc/Desktop/dk/zvec-main/README.md)：zvec 产品/能力介绍与安装方式
- [zvec-main/pyproject.toml](file:///Users/cc/Desktop/dk/zvec-main/pyproject.toml)：Python wheel 构建方式（scikit-build-core + pybind11）

## 6. 依赖关系（跨语言与外部服务）

### 6.1 DropKnow（Swift）依赖

- Apple Frameworks（系统自带）：
  - SwiftUI / AppKit：UI 与应用生命周期
  - PDFKit：PDF 解析（[DocumentParser.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/DocumentParser.swift#L1-L58)）
  - CryptoKit：SHA-256 文件指纹（[ProcessingPolicy.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/ProcessingPolicy.swift#L1-L45)）
  - EventKit：写入系统日历（[CalendarService.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/CalendarService.swift)）
  - UserNotifications：通知（[NotificationService.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/NotificationService.swift)）
- SwiftPM：当前 `Package.swift` 未声明外部三方依赖（[Package.swift](file:///Users/cc/Desktop/dk/Package.swift)）

### 6.2 Python RAG 侧依赖

- `zvec` Python 包（通常来自 PyPI wheel）：由 [build_and_run.sh](file:///Users/cc/Desktop/dk/script/build_and_run.sh#L21-L28) 自动安装
- 标准库：`sqlite3/urllib/json/re/hashlib/...`
- 外部云服务（默认 DashScope）：
  - Embeddings：用于把 chunks/query 转为向量
  - Chat：用于“基于证据回答”和“精修分类”

## 7. 构建与运行

### 7.1 一键运行（推荐）

脚本：[build_and_run.sh](file:///Users/cc/Desktop/dk/script/build_and_run.sh)

```bash
./script/build_and_run.sh run
```

脚本会自动：
- 创建 `.venv/` 并安装 `zvec`
- `swift build` 构建可执行文件
- 打包 `dist/DropKnow.app` 并运行（`open -n`）

其他模式：
- `./script/build_and_run.sh --debug`：lldb 启动
- `./script/build_and_run.sh --logs`：实时输出进程日志
- `./script/build_and_run.sh --telemetry`：按 subsystem 过滤日志
- `./script/build_and_run.sh --verify`：启动后检查进程是否存活

### 7.2 运行前配置（DashScope）

如需真实 embedding + 基于证据回答 + refine，需要配置：

```bash
export DASHSCOPE_API_KEY="***"
```

或在 `Application Support/DropKnow/providers.local.json` 写入（示例）：

```json
{
  "api_key": "***",
  "embedding_model": "tongyi-embedding-vision-flash-2026-03-06",
  "embedding_dimension": 768,
  "chat_model": "qwen3.5-flash"
}
```

### 7.3 Swift 单元测试

```bash
swift test
```

测试目录：`Tests/DropKnowTests/`（重点覆盖 parser heuristics、队列策略、配额逻辑、状态持久化等）。

## 8. 常见问题（Troubleshooting）

- Python 提示缺少 zvec
  - 现象：索引/搜索返回 `"Python 环境缺少 zvec：..."`（见 [rag_helper.py](file:///Users/cc/Desktop/dk/Sources/DropKnow/Scripts/rag_helper.py#L284-L365)）
  - 处理：使用脚本启动确保 `.venv` 安装成功，或手动 `pip install zvec`
- 未配置 DashScope API Key
  - 现象：embedding/search/chat/refine 报错“未配置 DashScope API Key”
  - 处理：设置 `DASHSCOPE_API_KEY` 或写 `providers.local.json`
- 文件被识别为敏感而阻塞
  - 现象：`DropFile.parsedStatus == .sensitiveGate`，通知提示需要确认
  - 处理：在应用内选择“仅本次允许”或“信任目录”（见 `AppStore.sensitiveRemoteDecision`）
- 索引/问答超时
  - 现象：`RAGService` 抛出 `问答超时...`（见 [RAGService.swift](file:///Users/cc/Desktop/dk/Sources/DropKnow/Services/RAGService.swift#L144-L191)）
  - 处理：检查网络与 DashScope 可用性；减少一次批量索引的文件/文本规模（当前已做 batch 限制）
