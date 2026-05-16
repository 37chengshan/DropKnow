# DropKnow 项目审查与下一步迭代建议

审查日期：2026-04-26  
审查范围：`Package.swift`、`Sources/DropKnow`、`script/build_and_run.sh`、PRD v1  
验证结果：`swift build` 通过；`swift test` 失败，原因是当前项目没有 `Tests` target。

## 1. 执行摘要

当前项目已经具备一个可运行的 SwiftPM macOS 原生应用骨架：监听目录、解析 PDF/DOCX/TXT/MD、生成本地摘要和事件候选、调用 Python helper 建 zvec 向量索引、提供问答与文件卡片联动。整体方向和 PRD 的 V1 目标一致。

但现在的最大风险是成本控制和状态账本缺失。应用没有文件内容指纹、没有“已解析版本 / 已索引版本 / 已远端精修版本”的稳定记录，也没有额度执行逻辑。任何一次状态丢失、模型变更导致 JSON 解码失败、手动重建索引、或自动监听在重启后发现“未 seen”的文件，都可能把目录里的文件重新走完整流程：本地解析、LLM refine、embedding、zvec 写入。这正是“每构建一次就反复一次性把所有文件上传解析”的核心风险来源。

优先级最高的下一步不是继续加 UI，而是先把导入和索引管线改成增量、可恢复、可计费、可观测。

## 2. 当前系统路径

### 2.1 应用启动

- `DropKnowApp` 创建单例 `AppStore`。
- `AppStore.init()` 加载 settings 和 files，调用 `monitor.markSeen(files.map(\.filePath))`，然后启动 8 秒轮询。
- 轮询触发 `scanForNewFiles()`，若 `autoParseNewFiles == true`，就枚举监听目录中新出现的稳定文件并调用 `processFile()`。

相关代码：

- `Sources/DropKnow/App/DropKnowApp.swift:6`
- `Sources/DropKnow/Stores/AppStore.swift:25`
- `Sources/DropKnow/Stores/AppStore.swift:29`
- `Sources/DropKnow/Stores/AppStore.swift:89`
- `Sources/DropKnow/Services/DirectoryMonitor.swift:8`

### 2.2 文件处理

`processFile()` 是所有高成本路径的共同入口：

1. 生成 `DropFile` skeleton，状态设为 `.parsing`。
2. 调用 `DocumentParser.parse()` 提取全文、分块、敏感判断、事件抽取、本地摘要。
3. 如果不触发敏感门禁，调用 `rag.refine()`，把最多 5000 字正文发给 chat model 做分类/摘要修正。
4. 继续调用 `rag.index()`，把所有 chunks 发给 embedding endpoint，再写入 zvec 和 sqlite metadata。
5. 保存 `dropknow_state.json`。

相关代码：

- `Sources/DropKnow/Stores/AppStore.swift:228`
- `Sources/DropKnow/Stores/AppStore.swift:274`
- `Sources/DropKnow/Stores/AppStore.swift:298`
- `Sources/DropKnow/Services/RAGService.swift:40`
- `Sources/DropKnow/Scripts/rag_helper.py:83`
- `Sources/DropKnow/Scripts/rag_helper.py:304`

### 2.3 手动重建索引

`rebuildSemanticIndex()` 会筛出所有 `.parsed` 文件，然后逐个调用 `processFile()`。这不是“只重建向量索引”，而是重新跑完整解析、LLM refine、embedding。

相关代码：

- `Sources/DropKnow/Stores/AppStore.swift:102`
- `Sources/DropKnow/Stores/AppStore.swift:114`

这会直接导致一次“重建索引”等于再次付费解析所有已解析文件。

## 3. 高成本重复解析的根因

### P0-1：自动监听在状态为空或解码失败时会扫描整个监听目录

`DirectoryMonitor` 的 `seen` 只存在内存中。重启后靠 `loadFiles()` 读出的文件路径恢复 seen。如果 `dropknow_state.json` 不存在、被清空、或因为模型字段变更解码失败，`loadFiles()` 直接返回空数组。随后默认 `autoParseNewFiles` 为 true，8 秒轮询会递归扫描整个监听目录，并把所有支持格式文件视为新文件处理。

触发链：

- `loadFiles()` 解码失败返回 `[]`：`Sources/DropKnow/Stores/AppStore.swift:416`
- `markSeen(files.map(\.filePath))` 在空状态下没有任何保护：`Sources/DropKnow/Stores/AppStore.swift:29`
- 默认自动解析开启：`Sources/DropKnow/Models/DropModels.swift:163`
- `newStableFiles()` 没有最近天数 cutoff，只看“路径未 seen”：`Sources/DropKnow/Services/DirectoryMonitor.swift:22`

这非常符合开发期“每构建一次打开 app，就又开始全量处理”的现象，尤其是在模型结构频繁变化、状态文件解码失败、或者 Application Support 数据被清掉时。

### P0-2：没有内容指纹，所以无法判断“文件未变化，跳过远端调用”

`DropFile` 当前保存了 `filePath`、`modifiedAt`、`fileSize`、`textLength`，但没有 `contentHash`、`parserVersion`、`embeddingModel`、`embeddingDimension`、`indexedAt`、`indexedContentHash` 这类索引账本字段。

结果是：

- 相同路径文件只靠 `importRecentFiles()` 的 `filePath` 去重，不能判断内容是否变化。
- `reparseSelection()` 必然重跑完整链路。
- `rebuildSemanticIndex()` 对所有 parsed 文件重跑完整链路。
- 更换 embedding model 或 parser 版本时，只能全量重算，没有可控迁移计划。

相关代码：

- `Sources/DropKnow/Models/DropModels.swift:95`
- `Sources/DropKnow/Stores/AppStore.swift:80`
- `Sources/DropKnow/Stores/AppStore.swift:97`
- `Sources/DropKnow/Stores/AppStore.swift:102`

### P0-3：额度字段只是展示，没有执行

PRD 规定免费版每日自动解析、问答、高级搜索有限额。代码里 `DropSettings` 有 `dailyParseLimit`、`dailyChatLimit`、`dailySearchLimit`，设置页也展示了这些值，但导入、自动解析、搜索、聊天、重建索引都没有计数、扣减、拦截。

相关代码：

- `Sources/DropKnow/Models/DropModels.swift:153`
- `Sources/DropKnow/Views/SettingsView.swift:36`
- `Sources/DropKnow/Stores/AppStore.swift:72`
- `Sources/DropKnow/Stores/AppStore.swift:89`
- `Sources/DropKnow/Stores/AppStore.swift:192`

这意味着真实成本完全不受产品层保护。

### P0-4：`refine` 对每个非敏感文件默认调用一次 chat model

当前不是只有搜索/问答会花钱。每个被解析文件在 embedding 前还会调用一次 `rag.refine()`，传入最多 5000 字正文。即使文件明显是低价值资料、README、讲义，也会先尝试远端 refine，失败才静默回退。

相关代码：

- `Sources/DropKnow/Stores/AppStore.swift:274`
- `Sources/DropKnow/Services/RAGService.swift:78`
- `Sources/DropKnow/Scripts/rag_helper.py:162`

建议把远端 refine 改成“只对高置信待办候选调用”，低价值文件只做本地摘要和本地索引，或者等用户打开详情时再懒加载精修。

### P1-1：zvec 索引缺少删除/版本管理，可能产生陈旧向量

`rag_helper.index()` 会按 `file_id` 删除 sqlite metadata，再按当前 chunks 生成固定 chunk id 并 upsert 到 zvec。但它没有删除 zvec collection 中该文件旧版本的多余 chunk。如果新版 chunks 数量减少，旧 chunk 仍可能留在 zvec 里，搜索时查到后再因为 sqlite 找不到 row 被跳过。长期会造成索引膨胀和召回质量下降。

相关代码：

- `Sources/DropKnow/Scripts/rag_helper.py:315`
- `Sources/DropKnow/Scripts/rag_helper.py:316`
- `Sources/DropKnow/Scripts/rag_helper.py:345`

### P1-2：每个文件都启动一次 Python 进程并重新打开 collection

Swift 侧 `RAGService.run()` 每次 index/search/refine/chat 都创建一个 Python process。批量导入 100 个文件时，至少会有 100 次 index helper 进程，且每个文件还可能有一次 refine helper 进程。这会放大启动成本、zvec 初始化成本、失败面和超时概率。

相关代码：

- `Sources/DropKnow/Services/RAGService.swift:94`
- `Sources/DropKnow/Services/RAGService.swift:109`

### P1-3：状态文件是单一 JSON，缺少迁移和损坏恢复

`loadFiles()` 对 JSON 解码失败没有迁移、备份、错误提示或“进入只读保护模式”，直接返回空数组。随后自动监听会把目录视为新目录处理。

相关代码：

- `Sources/DropKnow/Stores/AppStore.swift:416`

这在开发期尤其危险：只要 `DropFile` 增加非 optional 字段，旧状态就可能无法解码。

### P1-4：保存的文本上下文太少，启动后会用摘要片段重新分类

成功解析后只保存 `snippets = Array(parsed.chunks.prefix(5))`，没有保存全文路径、全文 hash 或完整 parse artifact。`loadFiles()` 后又用 `persistedText()` 由文件名、摘要、keyPoints、前 5 个 snippets 拼接出的文本重新跑敏感检测和低价值判断。这会产生与原始全文不同的二次分类结果。

相关代码：

- `Sources/DropKnow/Stores/AppStore.swift:295`
- `Sources/DropKnow/Stores/AppStore.swift:428`
- `Sources/DropKnow/Stores/AppStore.swift:497`

## 4. 产品与工程差距

### 4.1 与 PRD 的差距

- PRD 说“用户不需要配置 API Key”，当前 helper 依赖 `DASHSCOPE_API_KEY` 或 `providers.local.json`。
- PRD 说免费版限制 1 个目录，当前可添加多个目录，没有套餐拦截。
- PRD 说免费版不支持日历，当前代码没有按 plan 禁用日历。
- PRD 强调首次导入最近 7 天，当前手动导入有 cutoff，但自动监听在状态为空时会扫描整个目录。
- PRD 的成本边界还没有落到执行层。

### 4.2 可维护性风险

- `AppStore` 同时承担 UI 状态、导入队列、解析、RAG、搜索、日历、持久化，职责过重。
- `DocumentParser.swift` 聚合了解析、敏感检测、优先级、摘要、事件抽取，后续测试和迭代会困难。
- 没有单元测试 target。日期抽取、敏感检测、低价值判断、导入去重、额度扣减都应该优先补测试。
- `zvec-main` vendored 目录很大，当前仓库未提交状态下会干扰搜索、review 和未来提交管理。

## 5. 建议的下一步迭代路线

### Sprint 1：先止血，阻止重复远端花费

目标：即使反复构建、重启、状态部分损坏，也不会全量上传解析。

1. 新增文件指纹和索引账本。
   - `contentHash`
   - `fingerprintComputedAt`
   - `parserVersion`
   - `summaryVersion`
   - `embeddingProvider`
   - `embeddingModel`
   - `embeddingDimension`
   - `indexedContentHash`
   - `indexedAt`
   - `refinedContentHash`
   - `refinedAt`

2. 在 `processFile()` 开头加跳过逻辑。
   - 文件存在且 `contentHash == indexedContentHash`
   - parser/model/version 未变化
   - 非强制 reparse
   - 则直接返回，不调用 refine/index。

3. 自动监听增加安全阀。
   - 首次启动或状态解码失败时，不自动处理整个目录。
   - 自动监听只处理 `modifiedAt >= appFirstSeenAt` 或最近 N 分钟落地的文件。
   - 一轮最多处理 `dailyParseRemaining` 和 `maxAutoBatchSize`。
   - 空状态时弹出“发现 X 个历史文件，是否导入最近 7 天”，不能静默全量跑。

4. `rebuildSemanticIndex()` 改名并拆分。
   - “补齐缺失索引”：只处理 hash 未索引的文件。
   - “强制重建索引”：必须二次确认，并显示预计文件数/chunk 数/可能成本。

5. `rag.refine()` 改成条件触发。
   - 本地判断为 `.high` 或事件候选置信度超过阈值才调用。
   - 低价值文件只做本地摘要，不调用 chat refine。

### Sprint 2：建立可靠队列和额度

目标：成本、失败、重试都可控。

1. 新增 `ParseJob` / `IndexJob` 队列表。
   - 状态：queued / parsing / parsed / indexing / indexed / failed / blockedSensitive / skippedUnchanged
   - 重试次数、错误类型、上次尝试时间。

2. 每日额度真正执行。
   - Parse、Search、Chat、Refine、Embedding 分开记账。
   - 本地解析不计远端额度，远端 refine 和 embedding 计成本额度。
   - 设置页显示“已用/剩余”，不是只显示套餐上限。

3. 批量 index API。
   - Swift 一次把多个文件的 chunks 发给 Python helper。
   - Python helper 批量 embedding、批量 upsert、单次 flush。
   - 每批设置 chunk 数和 token 上限。

4. 失败恢复。
   - embedding 失败不覆盖已成功索引版本。
   - 索引写入采用临时版本，完成后再切换 active revision。
   - 状态 JSON 解码失败时保留 `.bak` 并进入保护模式。

### Sprint 3：质量、隐私、测试

目标：能稳定验证核心逻辑。

1. 拆出模块并补测试。
   - `FileFingerprintService`
   - `ImportPlanner`
   - `QuotaService`
   - `IndexLedger`
   - `DocumentClassifier`
   - `EventExtractor`

2. 增加测试 target。
   - 导入相同文件不重复远端调用。
   - 文件内容变化才重新索引。
   - 状态解码失败不会自动全量扫描。
   - daily limit 用尽后自动解析停止。
   - `rebuildSemanticIndex()` 只补缺失，不全量 refine。

3. 隐私边界明确化。
   - 设置页展示“哪些内容会发送到模型”。
   - 敏感文件在本地检测后默认不 refine、不 embedding。
   - 对疑似敏感但用户允许的文件，记录用户授权粒度。

## 6. 推荐的数据模型草案

建议不要继续把所有状态塞进单个 `DropFile`。可以保留 UI 用的 `DropFile`，但底层状态拆成三类。

### 6.1 FileRecord

```swift
struct FileRecord: Codable, Identifiable {
    var id: UUID
    var filePath: String
    var fileName: String
    var sourceDirectory: String
    var fileKind: FileKind
    var fileSize: Int64
    var modifiedAt: Date
    var contentHash: String
    var firstSeenAt: Date
    var lastSeenAt: Date
    var sensitivityStatus: SensitivityStatus
}
```

### 6.2 ParseArtifact

```swift
struct ParseArtifact: Codable {
    var fileID: UUID
    var contentHash: String
    var parserVersion: Int
    var textLength: Int
    var chunksHash: String
    var chunkCount: Int
    var snippets: [String]
    var summary: FileSummary
    var events: [EventCandidate]
    var priorityLevel: PriorityLevel
    var createdAt: Date
}
```

### 6.3 IndexRecord

```swift
struct IndexRecord: Codable {
    var fileID: UUID
    var contentHash: String
    var chunksHash: String
    var embeddingProvider: String
    var embeddingModel: String
    var embeddingDimension: Int
    var indexRevision: String
    var chunkIDs: [String]
    var indexedAt: Date
}
```

这三个结构能让应用回答一个关键问题：这个文件内容、解析产物、向量索引是否一致。如果一致，就不能再发起远端调用。

## 7. 推荐的导入决策逻辑

伪代码如下：

```swift
func planImport(url: URL, reason: ImportReason) -> ImportPlan {
    let fingerprint = fingerprint(url)
    let existing = fileStore.find(path: url.path)

    if existing?.contentHash == fingerprint.hash,
       indexStore.hasActiveIndex(fileID: existing.id, contentHash: fingerprint.hash, model: currentEmbeddingModel),
       reason != .forceReparse {
        return .skip(.unchangedAndIndexed)
    }

    if quota.remoteParseRemaining == 0 {
        return .defer(.quotaExceeded)
    }

    if reason == .autoScan, batchGuard.wouldExceedLimit {
        return .defer(.batchLimit)
    }

    return .enqueueParse(fileID: existing?.id ?? UUID(), fingerprint: fingerprint)
}
```

关键点：先判断是否需要远端成本，再进入解析队列。

## 8. 具体代码修改建议

### 8.1 `AppStore.importRecentFiles`

当前只用 `filePath` 去重。建议改成：

- 枚举 URL 后先计算轻量 fingerprint。
- 已存在且 hash 未变化：只更新 `lastSeenAt`，不 `processFile()`。
- 已存在但 hash 变化：入队解析。
- 新文件：遵守额度和批大小。

### 8.2 `DirectoryMonitor.newStableFiles`

建议增加参数：

- `notBefore: Date`
- `maxCount: Int`
- `knownFingerprints: Set<String>`

并且在 app 状态为空或解码失败时默认不扫描历史文件。

### 8.3 `AppStore.rebuildSemanticIndex`

建议拆成：

- `repairMissingIndex()`：只处理没有 active index 的文件。
- `forceReindexAll()`：需要确认，并且不调用 `refine`，只复用已有 parse artifacts/chunks。

### 8.4 `RAGService`

建议新增 batch index：

```swift
struct RAGBatchIndexRequest: Codable {
    var files: [RAGIndexRequest]
    var embeddingModel: String
    var embeddingDimension: Int
}
```

并把 Python helper 的 `index` 改成支持多文件事务。

### 8.5 `rag_helper.py`

建议新增：

- `file_indexes` 表：记录 file_id、content_hash、model、dimension、active_revision。
- `chunks` 表增加 content_hash、chunk_hash、embedding_model。
- zvec doc id 改成 `sha1(file_id + content_hash + chunk_index)`，避免旧内容覆盖新内容。
- 成功写入所有 chunks 后再把 revision 标记为 active。
- 搜索时只返回 active revision 的 chunks。

## 9. 验收标准

下一轮迭代完成后，至少满足这些验收：

1. 连续运行 `script/build_and_run.sh` 3 次，不会产生任何新的 refine/embedding 调用。
2. 修改一个已入库文件后，只重新处理这个文件。
3. 删除或破坏 `dropknow_state.json` 后，应用不会自动全量解析 Downloads，而是提示用户恢复或手动导入。
4. 点击“补齐索引”只处理缺失索引文件。
5. 点击“强制重建”会显示预计文件数、chunk 数，并要求确认。
6. 免费额度用尽后，自动解析停止，用户能看到剩余额度。
7. `swift test` 有覆盖导入去重、指纹判断、额度拦截、状态解码失败保护。

## 10. 建议优先级

P0 必做：

- 内容指纹与索引账本
- 自动监听全量扫描保护
- `rebuildSemanticIndex()` 改为增量补齐
- 远端 refine 条件触发
- 额度执行

P1 紧接着做：

- 批量 index
- zvec active revision
- 状态迁移和损坏恢复
- 单元测试 target

P2 后续做：

- 更完整 DOCX 解析
- PDF OCR / PPT / Excel
- Provider 管理产品化
- 更细的应用内日志和成本统计

## 11. 结论

DropKnow 当前最像一个功能原型，而不是成本可控的可发布版本。核心体验已经跑通，但“下载即理解”这条链路没有增量边界，一旦状态不可靠就会变成“重启即全量付费处理”。下一步应先把导入、解析、精修、索引四个阶段做成有账本的 pipeline，再继续扩展文件类型和 UI。

