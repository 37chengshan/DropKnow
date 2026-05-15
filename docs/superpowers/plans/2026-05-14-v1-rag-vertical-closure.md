# DropKnow V1 RAG Vertical Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the DropKnow V1 vertical slice where imported files become queryable through RAG-backed chat, answers show evidence, file details verify evidence, settings diagnose failures, and fixture tests prove the path.

**Architecture:** Keep the existing SwiftUI + `AppStore` + `ProcessingEngine` + `RAGService` + `rag_helper.py` architecture. Add a structured RAG contract, helper diagnostics, focused AppStore routing helpers, chat working-state UI, evidence navigation, and settings diagnostics without a broad rewrite.

**Tech Stack:** SwiftPM, Swift 6 package with Swift 5 language mode, SwiftUI for macOS 14+, XCTest, Python 3 helper script, sqlite, zvec, DashScope-compatible provider config.

---

## File Structure

Create:

- `Tests/DropKnowTests/RAGSearchContractTests.swift`  
  Swift tests for search-result decoding, diagnostics defaults, query mode, and fallback model construction.

- `Tests/DropKnowTests/ChatWorkingStateTests.swift`  
  Swift tests for debounced/active/cancelled search working state and replacement behavior.

- `Tests/fixtures/rag/exam_notice.txt`  
  Fixture with course, exam date, location, and action language.

- `Tests/fixtures/rag/registration_deadline.txt`  
  Fixture with registration cutoff and required action.

- `Tests/fixtures/rag/class_schedule.md`  
  Fixture with class schedule details.

- `Tests/fixtures/rag/lecture_notes.md`  
  Non-urgent lecture fixture for false-positive checks.

- `Tests/fixtures/rag/unrelated.txt`  
  Unrelated fixture for no-hit or low-relevance checks.

- `script/verify_rag_fixtures.py`  
  Repeatable Python verification harness that indexes fixtures into a temporary store and verifies representative questions.

Modify:

- `Sources/DropKnow/Models/DropModels.swift`  
  Extend `SearchHit`, `SearchResult`, add `SearchQueryMode`, `SearchDiagnostics`, `RAGIndexState`, and file helpers.

- `Sources/DropKnow/Services/RAGService.swift`  
  Decode the extended helper response, preserve defaults for backwards compatibility, and surface diagnostics.

- `Sources/DropKnow/Services/RAGServing.swift`  
  No signature change unless tests need a typed diagnostics route; keep the protocol stable.

- `Sources/DropKnow/Scripts/rag_helper.py`  
  Add metadata diagnostics, `diagnostics` mode, richer search hits, query-mode fields, empty-index responses, and test-friendly local embedding fallback.

- `Sources/DropKnow/Stores/AppStore.swift`  
  Extract query routing, fallback result creation, search result binding, chat working state, detail navigation from hits, and RAG diagnostics refresh.

- `Sources/DropKnow/Views/SearchPage.swift`  
  Add chat working status, border-beam container, evidence cards, hit actions, warnings, and reduce-motion fallback.

- `Sources/DropKnow/Views/FileDetailView.swift`  
  Show index state, focused RAG evidence, and highlight evidence opened from chat.

- `Sources/DropKnow/Views/RecentDownloadsView.swift`  
  Display RAG/index queryable state on file cards.

- `Sources/DropKnow/Views/SettingsView.swift`  
  Replace static RAG info with provider, RAG store, zvec, sqlite, index counts, last error, quota, queue, and privacy diagnostics.

- `Sources/DropKnow/Support/GlassSurface.swift`  
  Add reusable border-beam modifier tied to real working state and reduce-motion.

- `Tests/DropKnowTests/AppStoreTests.swift`  
  Update stubs and add route/binding/navigation/fallback tests.

- `Tests/DropKnowTests/RagHelperConfigTests.swift`  
  Add helper diagnostic and empty-index process tests that do not require remote APIs.

---

## Task 1: Extend Swift RAG Contract

**Files:**
- Modify: `Sources/DropKnow/Models/DropModels.swift`
- Modify: `Tests/DropKnowTests/AppStoreTests.swift`
- Create: `Tests/DropKnowTests/RAGSearchContractTests.swift`

- [x] **Step 1: Write decoding/default tests**

Add `Tests/DropKnowTests/RAGSearchContractTests.swift`:

```swift
import XCTest
@testable import DropKnow

final class RAGSearchContractTests: XCTestCase {
    func testSearchResultDefaultsRemainRenderable() {
        let result = SearchResult(answer: "没有找到足够相关的证据。", hits: [], engine: "zvec", warning: nil)

        XCTAssertEqual(result.queryMode, .fileSearch)
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertEqual(result.diagnostics.topK, 0)
        XCTAssertFalse(result.diagnostics.emptyIndex)
        XCTAssertNil(result.warning)
    }

    func testSearchHitCarriesEvidenceLocation() {
        let hit = SearchHit(
            id: "chunk-1",
            fileID: UUID(),
            fileName: "高数考试通知.txt",
            filePath: "/tmp/高数考试通知.txt",
            snippet: "高数考试时间为 5 月 20 日 10:00，地点 A101。",
            score: 0.91,
            chunkIndex: 2,
            revisionID: "rev-1",
            matchReason: "命中考试时间"
        )

        XCTAssertEqual(hit.chunkIndex, 2)
        XCTAssertEqual(hit.revisionID, "rev-1")
        XCTAssertEqual(hit.matchReason, "命中考试时间")
    }

    func testDiagnosticsDescribeFallbackAndIndexState() {
        let diagnostics = SearchDiagnostics(
            embeddingEngine: "local-hash",
            embeddingModel: "test-local",
            chatModel: "qwen3.5-flash",
            topK: 6,
            chatUsed: false,
            fallbackReason: "MISSING_API_KEY",
            indexedFileCount: 3,
            chunkCount: 9,
            activeRevisionCount: 3,
            emptyIndex: false,
            providerConfigured: false
        )

        XCTAssertEqual(diagnostics.fallbackReason, "MISSING_API_KEY")
        XCTAssertEqual(diagnostics.indexedFileCount, 3)
        XCTAssertFalse(diagnostics.providerConfigured)
    }
}
```

- [x] **Step 2: Run the focused tests and verify failure**

Run:

```bash
swift test --filter RAGSearchContractTests
```

Expected: compile failure because `SearchQueryMode`, `SearchDiagnostics`, and extended `SearchHit` fields do not exist.

- [x] **Step 3: Add the Swift data types**

In `Sources/DropKnow/Models/DropModels.swift`, replace the existing `SearchHit` and `SearchResult` block with:

```swift
enum SearchQueryMode: String, Codable, Hashable {
    case fileSearch
    case generalChat
    case localFallback
    case quotaBlocked
    case errorFallback
}

struct SearchDiagnostics: Codable, Hashable {
    var embeddingEngine: String?
    var embeddingModel: String?
    var chatModel: String?
    var topK: Int
    var chatUsed: Bool
    var fallbackReason: String?
    var indexedFileCount: Int
    var chunkCount: Int
    var activeRevisionCount: Int
    var emptyIndex: Bool
    var providerConfigured: Bool

    static let empty = SearchDiagnostics(
        embeddingEngine: nil,
        embeddingModel: nil,
        chatModel: nil,
        topK: 0,
        chatUsed: false,
        fallbackReason: nil,
        indexedFileCount: 0,
        chunkCount: 0,
        activeRevisionCount: 0,
        emptyIndex: false,
        providerConfigured: false
    )
}

enum RAGIndexState: String, Codable, Hashable {
    case notIndexed = "未索引"
    case indexing = "索引中"
    case indexed = "可问"
    case stale = "索引过期"
    case failed = "索引失败"
    case blocked = "不可索引"
}

struct SearchHit: Identifiable, Codable, Hashable {
    var id: String
    var fileID: UUID?
    var fileName: String
    var filePath: String
    var snippet: String
    var score: Double
    var chunkIndex: Int?
    var revisionID: String?
    var matchReason: String?

    init(
        id: String,
        fileID: UUID?,
        fileName: String,
        filePath: String,
        snippet: String,
        score: Double,
        chunkIndex: Int? = nil,
        revisionID: String? = nil,
        matchReason: String? = nil
    ) {
        self.id = id
        self.fileID = fileID
        self.fileName = fileName
        self.filePath = filePath
        self.snippet = snippet
        self.score = score
        self.chunkIndex = chunkIndex
        self.revisionID = revisionID
        self.matchReason = matchReason
    }
}

struct SearchResult: Codable, Hashable {
    var answer: String
    var hits: [SearchHit]
    var engine: String
    var warning: String?
    var queryMode: SearchQueryMode
    var diagnostics: SearchDiagnostics

    init(
        answer: String,
        hits: [SearchHit],
        engine: String,
        warning: String?,
        queryMode: SearchQueryMode = .fileSearch,
        diagnostics: SearchDiagnostics = .empty
    ) {
        self.answer = answer
        self.hits = hits
        self.engine = engine
        self.warning = warning
        self.queryMode = queryMode
        self.diagnostics = diagnostics
    }
}
```

Add this helper near `DropFile`:

```swift
extension DropFile {
    var ragIndexState: RAGIndexState {
        if parsedStatus == .sensitiveGate || parsedStatus == .ignored {
            return .blocked
        }
        if parsedStatus == .failed {
            return .failed
        }
        guard parsedStatus == .parsed else {
            return .notIndexed
        }
        guard let contentHash, let indexedContentHash, indexedAt != nil else {
            return .notIndexed
        }
        if contentHash != indexedContentHash {
            return .stale
        }
        return .indexed
    }
}
```

- [x] **Step 4: Run focused tests**

Run:

```bash
swift test --filter RAGSearchContractTests
```

Expected: pass.

- [x] **Step 5: Run existing AppStore tests for compile fallout**

Run:

```bash
swift test --filter AppStoreTests
```

Expected: pass after the `SearchResult` initializer preserves existing call sites.

- [x] **Step 6: Commit**

```bash
git add Sources/DropKnow/Models/DropModels.swift Tests/DropKnowTests/RAGSearchContractTests.swift Tests/DropKnowTests/AppStoreTests.swift
git commit -m "feat: extend rag search result contract"
```

---

## Task 2: Add RAG Fixture Verification Harness

**Files:**
- Create: `Tests/fixtures/rag/exam_notice.txt`
- Create: `Tests/fixtures/rag/registration_deadline.txt`
- Create: `Tests/fixtures/rag/class_schedule.md`
- Create: `Tests/fixtures/rag/lecture_notes.md`
- Create: `Tests/fixtures/rag/unrelated.txt`
- Create: `script/verify_rag_fixtures.py`

- [ ] **Step 1: Add deterministic fixtures**

Create `Tests/fixtures/rag/exam_notice.txt`:

```text
高等数学期末考试通知

高等数学期末考试安排在 2026 年 6 月 18 日 10:00-12:00。
考试地点为 A101 教室。请携带学生证、身份证和黑色签字笔。
缺考学生需要在考试前向教务办公室提交书面说明。
```

Create `Tests/fixtures/rag/registration_deadline.txt`:

```text
大学生创新创业训练计划报名通知

报名系统开放时间为 2026 年 5 月 20 日至 2026 年 5 月 28 日 18:00。
学生需要提交项目申请书、指导教师确认表和团队成员名单。
逾期未提交材料视为放弃本次报名。
```

Create `Tests/fixtures/rag/class_schedule.md`:

```markdown
# 计算机网络课程调课说明

原定周三第 3-4 节的计算机网络课程调整到周五第 7-8 节。
上课地点改为 B203。调整从 2026 年 5 月 22 日开始执行。
```

Create `Tests/fixtures/rag/lecture_notes.md`:

```markdown
# 线性代数复习讲义

本讲义介绍矩阵乘法、行列式、特征值和向量空间的基本概念。
材料用于课后复习，不包含考试安排、报名截止或缴费要求。
```

Create `Tests/fixtures/rag/unrelated.txt`:

```text
图书馆开放空间介绍

图书馆二楼提供安静阅读区域，三楼提供小组讨论室。
本文档不包含课程、考试、报名或截止日期安排。
```

- [ ] **Step 2: Add the verification harness**

Create `script/verify_rag_fixtures.py`:

```python
#!/usr/bin/env python3
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "Sources" / "DropKnow" / "Scripts" / "rag_helper.py"
FIXTURE_DIR = ROOT / "Tests" / "fixtures" / "rag"


def run_helper(mode, store, payload):
    process = subprocess.run(
        [sys.executable, str(HELPER), mode, "--store", str(store)],
        input=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if process.stderr:
        sys.stderr.write(process.stderr.decode("utf-8", errors="replace"))
    try:
        return json.loads(process.stdout.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise AssertionError(f"helper returned non-json output: {process.stdout!r}") from exc


def chunk_text(text):
    paragraphs = [line.strip() for line in text.splitlines() if line.strip()]
    return ["\n".join(paragraphs)]


def fixture_file_payload(path):
    text = path.read_text(encoding="utf-8")
    file_id = hashlib.sha1(str(path).encode("utf-8")).hexdigest()
    revision_id = hashlib.sha1(text.encode("utf-8")).hexdigest()
    return {
        "fileID": file_id,
        "fileName": path.name,
        "filePath": str(path),
        "contentHash": revision_id,
        "revisionID": revision_id,
        "chunks": chunk_text(text),
    }


def assert_hit(response, expected_file, expected_phrase):
    assert response.get("ok") is True, response
    hits = response.get("hits") or []
    names = [hit.get("fileName") for hit in hits]
    assert expected_file in names, f"expected {expected_file} in hits, got {names}"
    joined = "\n".join(hit.get("snippet", "") for hit in hits if hit.get("fileName") == expected_file)
    assert expected_phrase in joined, f"expected phrase {expected_phrase!r} in evidence for {expected_file}: {joined}"


def main():
    with tempfile.TemporaryDirectory(prefix="dropknow-rag-fixtures-") as tmp:
        store = Path(tmp) / "rag_store"
        files = [fixture_file_payload(path) for path in sorted(FIXTURE_DIR.iterdir()) if path.is_file()]
        index_response = run_helper("index_batch", store, {"files": files})
        assert index_response.get("ok") is True, index_response

        cases = [
            ("高等数学考试在哪天", "exam_notice.txt", "2026 年 6 月 18 日"),
            ("报名截止是什么时候", "registration_deadline.txt", "2026 年 5 月 28 日 18:00"),
            ("计算机网络调到哪个教室", "class_schedule.md", "B203"),
        ]
        for query, expected_file, expected_phrase in cases:
            response = run_helper("search", store, {"query": query, "topK": 6})
            assert_hit(response, expected_file, expected_phrase)

        print("RAG fixture verification passed: indexed fixtures and matched expected evidence.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run harness and record environment-dependent result**

Run:

```bash
python3 script/verify_rag_fixtures.py
```

Expected on a machine with zvec and embedding provider configured: prints `RAG fixture verification passed: indexed fixtures and matched expected evidence.`

Expected without zvec/provider: fails with a classified helper JSON error. Do not hide this failure; Task 3 makes missing dependencies diagnosable.

- [ ] **Step 4: Commit fixtures and harness**

```bash
git add Tests/fixtures/rag script/verify_rag_fixtures.py
git commit -m "test: add rag fixture verification harness"
```

---

## Task 3: Extend Python Helper Diagnostics and Search Output

**Files:**
- Modify: `Sources/DropKnow/Scripts/rag_helper.py`
- Modify: `Tests/DropKnowTests/RagHelperConfigTests.swift`

- [ ] **Step 1: Add process tests for empty index and diagnostics mode**

In `Tests/DropKnowTests/RagHelperConfigTests.swift`, add:

```swift
func testRagHelperDiagnosticsModeReturnsMetadataCounts() throws {
    let script = try ragHelperScriptURL()
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let object = try runHelper(script: script, mode: "diagnostics", store: base.appendingPathComponent("rag_store"), payload: "{}")

    XCTAssertEqual(object["ok"] as? Bool, true)
    XCTAssertNotNil(object["diagnostics"] as? [String: Any])
}

private func ragHelperScriptURL() throws -> URL {
    let fileURL = URL(fileURLWithPath: #file)
    let root = fileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let script = root.appendingPathComponent("Sources").appendingPathComponent("DropKnow").appendingPathComponent("Scripts").appendingPathComponent("rag_helper.py")
    XCTAssertTrue(FileManager.default.fileExists(atPath: script.path))
    return script
}

private func runHelper(script: URL, mode: String, store: URL, payload: String) throws -> [String: Any] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [script.path, mode, "--store", store.path]
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    input.fileHandleForWriting.write(Data(payload.utf8))
    input.fileHandleForWriting.closeFile()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return object ?? [:]
}
```

If the existing `testInvalidProvidersConfigReturnsConfigInvalidErrorCode` duplicates script lookup logic, refactor it to use `ragHelperScriptURL()` and `runHelper(...)` in the same file.

- [ ] **Step 2: Run focused test and verify failure**

Run:

```bash
swift test --filter RagHelperConfigTests
```

Expected: failure because helper mode `diagnostics` is not accepted.

- [ ] **Step 3: Add helper diagnostics functions**

In `Sources/DropKnow/Scripts/rag_helper.py`, add after `connect_metadata`:

```python
def metadata_diagnostics(store, config=None, api=None):
    db = connect_metadata(store)
    indexed_file_count = db.execute("select count(distinct file_id) from chunks").fetchone()[0]
    chunk_count = db.execute("select count(*) from chunks").fetchone()[0]
    active_revision_count = db.execute("select count(*) from active_revisions").fetchone()[0]
    embedding_model = (config or {}).get("embedding_model")
    chat_model = (config or {}).get("chat_model")
    return {
        "embeddingEngine": None,
        "embeddingModel": embedding_model,
        "chatModel": chat_model,
        "topK": 0,
        "chatUsed": False,
        "fallbackReason": None,
        "indexedFileCount": int(indexed_file_count),
        "chunkCount": int(chunk_count),
        "activeRevisionCount": int(active_revision_count),
        "emptyIndex": int(chunk_count) == 0,
        "providerConfigured": bool((config or {}).get("api_key", "")),
        "zvecAvailable": not (api and "error" in api),
    }
```

Add a new mode function:

```python
def diagnostics(payload, store):
    try:
        config = load_provider_config(store)
    except UserVisibleError as exc:
        config = {}
        config_error = {"code": exc.code, "message": str(exc)}
    else:
        config_error = None
    api = load_zvec()
    result = metadata_diagnostics(store, config=config, api=api)
    if "error" in api:
        result["fallbackReason"] = "MISSING_ZVEC"
        result["zvecError"] = api["error"]
    if config_error:
        result["fallbackReason"] = config_error["code"]
        result["providerError"] = config_error["message"]
    emit({"ok": True, "engine": "diagnostics", "diagnostics": result})
    return 0
```

Update `main()` choices:

```python
parser.add_argument("mode", choices=["index", "index_batch", "search", "refine", "chat", "diagnostics"])
```

Add dispatch before search:

```python
if args.mode == "diagnostics":
    return diagnostics(payload, args.store)
```

- [ ] **Step 4: Extend search hit output**

In `search(payload, store)`, change the metadata query to select revision/chunk index:

```python
select c.file_id, c.file_name, c.file_path, c.text, c.chunk_index, c.revision_id
```

Change each hit dictionary to:

```python
{
    "id": doc.id,
    "fileID": row[0],
    "fileName": row[1],
    "filePath": row[2],
    "snippet": row[3][:700],
    "score": float(doc.score),
    "chunkIndex": int(row[4]),
    "revisionID": row[5],
    "matchReason": "命中文件片段",
}
```

Before `emit(...)`, build diagnostics:

```python
diag = metadata_diagnostics(store, config=config, api=api)
diag["embeddingEngine"] = embedding_engine
diag["topK"] = top_k
diag["chatUsed"] = chat_used
if warning:
    diag["fallbackReason"] = "LOCAL_FALLBACK" if not chat_used else "CHAT_WARNING"
```

Change the emitted search object:

```python
emit(
    {
        "ok": True,
        "queryMode": "fileSearch" if chat_used else "localFallback",
        "engine": f"zvec + {embedding_engine}" + (f" + {config['chat_model']}" if chat_used else " + local-answer"),
        "answer": answer,
        "hits": hits,
        "warning": warning,
        "diagnostics": diag,
    }
)
```

- [ ] **Step 5: Run helper config tests**

Run:

```bash
swift test --filter RagHelperConfigTests
```

Expected: pass.

- [ ] **Step 6: Run fixture harness**

Run:

```bash
python3 script/verify_rag_fixtures.py
```

Expected: pass when zvec and embedding config are available; otherwise emit a classified missing dependency and proceed to Task 4 to surface it in Swift/UI.

- [ ] **Step 7: Commit**

```bash
git add Sources/DropKnow/Scripts/rag_helper.py Tests/DropKnowTests/RagHelperConfigTests.swift
git commit -m "feat: add rag helper diagnostics"
```

---

## Task 4: Decode Extended RAG Responses in Swift

**Files:**
- Modify: `Sources/DropKnow/Services/RAGService.swift`
- Modify: `Sources/DropKnow/Services/RAGServing.swift`
- Modify: `Tests/DropKnowTests/AppStoreTests.swift`

- [ ] **Step 1: Add diagnostics to response models**

In `RAGProcessResponse`, add:

```swift
var queryMode: SearchQueryMode?
var diagnostics: SearchDiagnostics?
```

If `RAGBatchIndexResponse` does not need diagnostics, leave it unchanged.

- [ ] **Step 2: Update `RAGService.search`**

Replace the successful return in `search(query:topK:)` with:

```swift
return SearchResult(
    answer: response.answer ?? "没有找到足够相关的证据。",
    hits: response.hits ?? [],
    engine: response.engine ?? "zvec",
    warning: response.warning,
    queryMode: response.queryMode ?? .fileSearch,
    diagnostics: response.diagnostics ?? .empty
)
```

- [ ] **Step 3: Update `RAGService.chat`**

Replace the successful return in `chat(query:)` with:

```swift
return SearchResult(
    answer: response.answer ?? "",
    hits: [],
    engine: response.engine ?? "qwen3.5-flash",
    warning: response.warning,
    queryMode: response.queryMode ?? .generalChat,
    diagnostics: response.diagnostics ?? .empty
)
```

- [ ] **Step 4: Add diagnostics API**

In `RAGServing`, add:

```swift
func diagnostics() async throws -> SearchDiagnostics
```

In `RAGService`, add:

```swift
func diagnostics() async throws -> SearchDiagnostics {
    struct EmptyPayload: Codable {}
    let response: RAGProcessResponse = try await run(mode: "diagnostics", payload: EmptyPayload())
    return response.diagnostics ?? .empty
}
```

Update `StubRAGService` in `AppStoreTests.swift`:

```swift
func diagnostics() async throws -> SearchDiagnostics {
    .empty
}
```

- [ ] **Step 5: Run compile-focused tests**

Run:

```bash
swift test --filter AppStoreTests
swift test --filter RAGSearchContractTests
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DropKnow/Services/RAGService.swift Sources/DropKnow/Services/RAGServing.swift Tests/DropKnowTests/AppStoreTests.swift
git commit -m "feat: decode rag diagnostics in swift"
```

---

## Task 5: Refine AppStore Query Routing, Binding, Fallback, and Diagnostics

**Files:**
- Modify: `Sources/DropKnow/Stores/AppStore.swift`
- Modify: `Tests/DropKnowTests/AppStoreTests.swift`

- [ ] **Step 1: Add route and binding tests**

In `AppStoreTests.swift`, add:

```swift
func testFileQuestionRoutesToRAGWithoutPrefix() async throws {
    let rag = StubRAGService(delayNanoseconds: 0)
    let store = makeStore(rag: rag)
    store.searchQuery = "高数考试在哪天"

    await store.performSearch()

    let calls = await rag.searchQueries
    XCTAssertEqual(calls, ["高数考试在哪天"])
    XCTAssertEqual(store.searchResult?.queryMode, .fileSearch)
}

func testSearchResultBindsFileIDByPathWhenHelperOmitsUUID() async throws {
    let file = makeFile(filePath: "/tmp/高数考试通知.txt")
    let rag = StubRAGService(
        delayNanoseconds: 0,
        result: SearchResult(
            answer: "高数考试在 6 月 18 日。",
            hits: [
                SearchHit(
                    id: "chunk-1",
                    fileID: nil,
                    fileName: file.fileName,
                    filePath: file.filePath,
                    snippet: "考试安排在 2026 年 6 月 18 日",
                    score: 0.9,
                    chunkIndex: 0,
                    revisionID: "rev-1",
                    matchReason: "命中考试时间"
                )
            ],
            engine: "stub",
            warning: nil
        )
    )
    let store = makeStore(files: [file], rag: rag)
    store.searchQuery = "考试在哪天"

    await store.performSearch()

    XCTAssertEqual(store.searchResult?.hits.first?.fileID, file.id)
}

func testNavigateToSearchHitFocusesSnippets() {
    let file = makeFile(filePath: "/tmp/notice.txt")
    let store = makeStore(files: [file])
    let hit = SearchHit(id: "chunk-1", fileID: file.id, fileName: file.fileName, filePath: file.filePath, snippet: "证据", score: 0.8)

    store.navigateToSearchHit(hit)

    XCTAssertEqual(store.selectedFileID, file.id)
    XCTAssertEqual(store.pendingNavigation?.section, .recent)
    XCTAssertEqual(store.detailFocusRequest?.anchor, .snippets)
}
```

Update `StubRAGService` initializer to accept an optional `result`:

```swift
let result: SearchResult?

init(delayNanoseconds: UInt64, result: SearchResult? = nil) {
    self.delayNanoseconds = delayNanoseconds
    self.result = result
}
```

Return `result ?? SearchResult(...)` from `search`.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter AppStoreTests
```

Expected: failure because routing/binding/navigation helpers are not implemented.

- [ ] **Step 3: Add route helper**

In `AppStore.swift`, add:

```swift
func shouldRouteToFileSearch(_ query: String) -> Bool {
    shouldSearchFiles(for: query)
}
```

Then expand the existing private `shouldSearchFiles(for:)` keywords to include:

```swift
let fileQuestionSignals = [
    "考试", "报名", "截止", "ddl", "DDL", "作业", "通知", "课程", "调课",
    "地点", "教室", "缴费", "活动", "面试", "宣讲", "下载", "文件",
    "上周", "昨天", "今天", "什么时候", "在哪", "讲了什么", "要我做什么"
]
```

Return true when any signal appears or when files are already indexed and the question contains date/action words.

- [ ] **Step 4: Add result binding helper**

Update `bindFileIDs(_:)` or create it if private:

```swift
private func bindFileIDs(_ hits: [SearchHit]) -> [SearchHit] {
    hits.map { hit in
        var bound = hit
        if bound.fileID == nil {
            bound.fileID = files.first { file in
                URL(fileURLWithPath: file.filePath).standardizedFileURL.path ==
                    URL(fileURLWithPath: hit.filePath).standardizedFileURL.path
            }?.id
        }
        return bound
    }
}
```

- [ ] **Step 5: Add hit navigation**

In `AppStore.swift`, add:

```swift
func navigateToSearchHit(_ hit: SearchHit) {
    let resolvedID = hit.fileID ?? files.first { file in
        URL(fileURLWithPath: file.filePath).standardizedFileURL.path ==
            URL(fileURLWithPath: hit.filePath).standardizedFileURL.path
    }?.id
    guard let resolvedID else {
        toastMessage = "未找到关联文件：\(hit.fileName)"
        return
    }
    navigateToFile(fileID: resolvedID, anchor: .snippets)
}
```

- [ ] **Step 6: Refresh RAG diagnostics**

Add state:

```swift
@Published var ragDiagnostics: SearchDiagnostics = .empty
@Published var lastRAGErrorMessage: String?
```

Add method:

```swift
func refreshRAGDiagnostics() async {
    do {
        ragDiagnostics = try await rag.diagnostics()
        lastRAGErrorMessage = nil
    } catch {
        lastRAGErrorMessage = error.localizedDescription
    }
}
```

Call `Task { await refreshRAGDiagnostics() }` from initialization only when it does not slow launch, or from Settings `.task`.

- [ ] **Step 7: Run focused tests**

Run:

```bash
swift test --filter AppStoreTests
```

Expected: pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/DropKnow/Stores/AppStore.swift Tests/DropKnowTests/AppStoreTests.swift
git commit -m "feat: route file questions through rag"
```

---

## Task 6: Add Chat Working State and Border-Beam UI

**Files:**
- Modify: `Sources/DropKnow/Stores/AppStore.swift`
- Modify: `Sources/DropKnow/Views/SearchPage.swift`
- Modify: `Sources/DropKnow/Support/GlassSurface.swift`
- Create: `Tests/DropKnowTests/ChatWorkingStateTests.swift`

- [ ] **Step 1: Add working-state tests**

Create `Tests/DropKnowTests/ChatWorkingStateTests.swift`:

```swift
import XCTest
@testable import DropKnow

@MainActor
final class ChatWorkingStateTests: XCTestCase {
    func testChatWorkingDuringDebounceAndSearch() async throws {
        let rag = WorkingStateRAGService(delayNanoseconds: 120_000_000)
        let store = AppStore(rag: rag, environment: .temporary(baseURL: try makeTempDirectory()))
        store.searchQuery = "高数考试在哪天"

        store.submitSearch(debounceNanoseconds: 80_000_000)
        XCTAssertTrue(store.isChatWorking)

        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(store.isChatWorking)

        try await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertFalse(store.isChatWorking)
    }

    func testCancelStopsChatWorking() async throws {
        let rag = WorkingStateRAGService(delayNanoseconds: 300_000_000)
        let store = AppStore(rag: rag, environment: .temporary(baseURL: try makeTempDirectory()))
        store.searchQuery = "报名截止是什么时候"
        store.submitSearch(debounceNanoseconds: 0)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(store.isChatWorking)

        store.cancelSearch()
        XCTAssertFalse(store.isChatWorking)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor WorkingStateRAGService: RAGServing {
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func indexBatch(files: [RAGBatchIndexFile]) async -> RAGIndexOutcome {
        RAGIndexOutcome(succeeded: true, warning: nil, results: [])
    }

    func search(query: String, topK: Int) async throws -> SearchResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return SearchResult(answer: "answer", hits: [], engine: "stub", warning: nil)
    }

    func chat(query: String) async throws -> SearchResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return SearchResult(answer: "answer", hits: [], engine: "stub", warning: nil, queryMode: .generalChat)
    }

    func refine(fileName: String, text: String, summary: FileSummary, priority: PriorityLevel, events: [EventCandidate]) async -> RAGProcessResponse? {
        nil
    }

    func diagnostics() async throws -> SearchDiagnostics {
        .empty
    }
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
swift test --filter ChatWorkingStateTests
```

Expected: compile failure because `isChatWorking` is not defined.

- [ ] **Step 3: Add working state to AppStore**

In `AppStore.swift`, add:

```swift
@Published var isSearchDebouncing = false

var isChatWorking: Bool {
    isSearchDebouncing || isSearching
}
```

In `submitSearch`, set `isSearchDebouncing = true` before creating the pending task, then set it to false immediately before starting `activeSearchTask`. In `cancelSearch`, set it false. In the pending task cancellation path, guard with `Task.isCancelled` and clear on main actor before return.

- [ ] **Step 4: Add border-beam modifier**

In `GlassSurface.swift`, add:

```swift
extension View {
    func dropWorkingBorderBeam(isActive: Bool, cornerRadius: CGFloat = 16) -> some View {
        modifier(DropWorkingBorderBeamModifier(isActive: isActive, cornerRadius: cornerRadius))
    }
}

private struct DropWorkingBorderBeamModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var rotation: Double = 0
    var isActive: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let palette = theme.palette(for: colorScheme)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay {
                if isActive {
                    if reduceMotion {
                        shape.stroke(palette.accentOrange.opacity(0.7), lineWidth: 1.5)
                    } else {
                        AngularGradient(
                            colors: [
                                palette.accentOrange.opacity(0.15),
                                palette.accentOrange.opacity(0.85),
                                palette.accentBlue.opacity(0.65),
                                palette.accentOrange.opacity(0.15)
                            ],
                            center: .center,
                            angle: .degrees(rotation)
                        )
                        .mask(shape.stroke(lineWidth: 1.5))
                        .onAppear {
                            rotation = 360
                        }
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: rotation)
                    }
                }
            }
    }
}
```

- [ ] **Step 5: Apply working UI in SearchPage**

Wrap the `ScrollViewReader` chat area in `SearchPage.swift` with:

```swift
VStack(spacing: 0) {
    ChatWorkingStatusBar(isWorking: store.isChatWorking)
    ScrollViewReader { proxy in
        ...
    }
}
.dropWorkingBorderBeam(isActive: store.isChatWorking, cornerRadius: 16)
```

Add:

```swift
private struct ChatWorkingStatusBar: View {
    var isWorking: Bool

    var body: some View {
        if isWorking {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检索文件并整理证据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
swift test --filter ChatWorkingStateTests
```

Expected: pass.

- [ ] **Step 7: Run visual compile tests**

Run:

```bash
swift test --filter AppStoreTests
```

Expected: pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/DropKnow/Stores/AppStore.swift Sources/DropKnow/Views/SearchPage.swift Sources/DropKnow/Support/GlassSurface.swift Tests/DropKnowTests/ChatWorkingStateTests.swift
git commit -m "feat: show chat working border beam"
```

---

## Task 7: Render Evidence Cards and Navigate to File Details

**Files:**
- Modify: `Sources/DropKnow/Views/SearchPage.swift`
- Modify: `Sources/DropKnow/Views/FileDetailView.swift`
- Modify: `Sources/DropKnow/Stores/AppStore.swift`
- Modify: `Tests/DropKnowTests/AppStoreTests.swift`

- [ ] **Step 1: Add navigation test for file path fallback**

In `AppStoreTests.swift`, add:

```swift
func testNavigateToSearchHitResolvesByFilePathWhenIDMissing() {
    let file = makeFile(filePath: "/tmp/path-fallback.txt")
    let store = makeStore(files: [file])
    let hit = SearchHit(id: "chunk-1", fileID: nil, fileName: file.fileName, filePath: file.filePath, snippet: "证据", score: 0.7)

    store.navigateToSearchHit(hit)

    XCTAssertEqual(store.selectedFileID, file.id)
    XCTAssertEqual(store.detailFocusRequest?.anchor, .snippets)
}
```

- [ ] **Step 2: Run focused test**

Run:

```bash
swift test --filter AppStoreTests/testNavigateToSearchHitResolvesByFilePathWhenIDMissing
```

Expected: pass if Task 5 path resolution is complete.

- [ ] **Step 3: Replace hit grid with evidence cards**

In `SearchPage.swift`, inside the `if !result.hits.isEmpty` block in `ChatBubble`, render `EvidenceHitCard`:

```swift
ForEach(result.hits) { hit in
    EvidenceHitCard(hit: hit, selectedSection: $selectedSection)
}
```

Add:

```swift
private struct EvidenceHitCard: View {
    @EnvironmentObject private var store: AppStore
    var hit: SearchHit
    @Binding var selectedSection: AppSection

    var body: some View {
        Button {
            store.navigateToSearchHit(hit)
            selectedSection = .recent
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(hit.fileName, systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.2f", hit.score))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(hit.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                if let matchReason = hit.matchReason {
                    Text(matchReason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .dropGlass(cornerRadius: 10, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Show warning and diagnostics in chat bubble**

In `ChatBubble`, after result status pills, add:

```swift
if let warning = result.warning, !warning.isEmpty {
    WarningSection(message: warning)
}

if result.diagnostics.emptyIndex {
    Text("当前索引为空，请先导入文件或补齐索引。")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 5: Ensure FileDetail snippets are focusable**

In `FileDetailView.swift`, keep `.id(FileDetailSectionAnchor.snippets)` on `SemanticSnippetsSection`. If there is no snippet but a search hit navigates to the file, display:

```swift
if file.snippets.isEmpty, file.ragIndexState == .indexed {
    WarningSection(message: "该文件已索引，但当前详情没有保存可展示片段。你仍可打开原文件核验。")
        .id(FileDetailSectionAnchor.snippets)
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --filter AppStoreTests
```

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/DropKnow/Views/SearchPage.swift Sources/DropKnow/Views/FileDetailView.swift Sources/DropKnow/Stores/AppStore.swift Tests/DropKnowTests/AppStoreTests.swift
git commit -m "feat: link chat evidence to file detail"
```

---

## Task 8: Improve File Cards and Detail Index State

**Files:**
- Modify: `Sources/DropKnow/Views/RecentDownloadsView.swift`
- Modify: `Sources/DropKnow/Views/FileDetailView.swift`
- Modify: `Sources/DropKnow/Models/DropModels.swift`
- Modify: `Tests/DropKnowTests/RAGSearchContractTests.swift`

- [ ] **Step 1: Add index-state tests**

In `RAGSearchContractTests.swift`, add:

```swift
func testDropFileRAGIndexStateDetectsIndexedAndStaleFiles() {
    var file = DropFile(
        fileName: "notice.txt",
        filePath: "/tmp/notice.txt",
        sourceDirectory: "/tmp",
        fileKind: .text,
        importedAt: Date(),
        modifiedAt: Date(),
        fileSize: 10,
        textLength: 10,
        parsedStatus: .parsed,
        sensitivityStatus: .clear,
        priorityLevel: .normal,
        summary: nil,
        events: [],
        snippets: [],
        errorMessage: nil,
        contentHash: "hash-a",
        fingerprintComputedAt: Date(),
        parserVersion: "parser",
        summaryVersion: "summary",
        refineModel: nil,
        embeddingProvider: "dashscope",
        embeddingModel: "embedding",
        embeddingDimension: 768,
        indexedContentHash: "hash-a",
        indexedAt: Date(),
        refinedContentHash: nil,
        refinedAt: nil,
        activeIndexRevision: "rev-a"
    )

    XCTAssertEqual(file.ragIndexState, .indexed)
    file.contentHash = "hash-b"
    XCTAssertEqual(file.ragIndexState, .stale)
}
```

- [ ] **Step 2: Run test**

Run:

```bash
swift test --filter RAGSearchContractTests
```

Expected: pass if Task 1 helper exists.

- [ ] **Step 3: Add file card RAG state pill**

In `FileGridCard`, add a pill or text in the metadata row:

```swift
Text("· \(item.file.ragIndexState.rawValue)")
    .foregroundStyle(item.file.ragIndexState == .indexed ? palette.success : palette.textSecondary)
```

Keep the row single-line and avoid layout shift.

- [ ] **Step 4: Add detail header index state**

In `DetailHeader`, add:

```swift
StatusPill(
    text: file.ragIndexState.rawValue,
    systemImage: file.ragIndexState == .indexed ? "checkmark.seal" : "magnifyingglass.circle",
    prominent: file.ragIndexState != .indexed
)
```

- [ ] **Step 5: Add action guidance for non-queryable states**

In `FileDetailView`, below `DetailHeader`, add:

```swift
if file.ragIndexState != .indexed, file.parsedStatus != .sensitiveGate {
    WarningSection(message: "该文件当前状态为“\(file.ragIndexState.rawValue)”。完成索引后才能在 AI 问答中稳定命中。")
}
```

- [ ] **Step 6: Run compile/tests**

Run:

```bash
swift test --filter RAGSearchContractTests
swift test --filter AppStoreTests
```

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/DropKnow/Views/RecentDownloadsView.swift Sources/DropKnow/Views/FileDetailView.swift Sources/DropKnow/Models/DropModels.swift Tests/DropKnowTests/RAGSearchContractTests.swift
git commit -m "feat: show rag queryable file states"
```

---

## Task 9: Expand Settings RAG Diagnostics

**Files:**
- Modify: `Sources/DropKnow/Views/SettingsView.swift`
- Modify: `Sources/DropKnow/Stores/AppStore.swift`
- Modify: `Sources/DropKnow/Support/ProviderConfiguration.swift`
- Modify: `Tests/DropKnowTests/ProviderConfigurationTests.swift`

- [x] **Step 1: Add provider source model**

In `ProviderConfiguration.swift`, extend the struct:

```swift
enum ProviderConfigurationSource: String, Hashable {
    case environment = "环境变量"
    case file = "配置文件"
    case missing = "未配置"
}

struct ProviderConfiguration: Hashable {
    var apiKey: String
    var configURL: URL
    var source: ProviderConfigurationSource
    ...
}
```

In `load(...)`, set:

```swift
let source: ProviderConfigurationSource
if !envKey.isEmpty {
    source = .environment
} else if !fileKey.isEmpty {
    source = .file
} else {
    source = .missing
}
return ProviderConfiguration(apiKey: resolved, configURL: configURL, source: source)
```

- [x] **Step 2: Add provider source tests**

In `ProviderConfigurationTests.swift`, add tests for env, file, and missing source. Example:

```swift
func testProviderConfigurationReportsMissingSource() {
    let config = ProviderConfiguration.load(environment: [:], fileManager: .default, configURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    XCTAssertEqual(config.source, .missing)
    XCTAssertFalse(config.hasAPIKey)
}
```

- [x] **Step 3: Run provider tests**

Run:

```bash
swift test --filter ProviderConfigurationTests
```

Expected: pass after source implementation.

- [x] **Step 4: Refresh diagnostics from Settings**

In `SettingsView`, add:

```swift
.task {
    await store.refreshRAGDiagnostics()
}
```

In the RAG section, display:

```swift
LabeledContent("已索引文件", value: "\(store.ragDiagnostics.indexedFileCount)")
LabeledContent("Chunk 数", value: "\(store.ragDiagnostics.chunkCount)")
LabeledContent("Active Revision", value: "\(store.ragDiagnostics.activeRevisionCount)")
LabeledContent("索引状态", value: store.ragDiagnostics.emptyIndex ? "空索引" : "已有索引")
if let lastRAGErrorMessage = store.lastRAGErrorMessage {
    Text(lastRAGErrorMessage)
        .font(theme.typography.body(.caption))
        .foregroundStyle(palette.danger)
}
```

In the Provider section, display config source:

```swift
let providerConfig = ProviderConfiguration.load()
LabeledContent("配置来源", value: providerConfig.source.rawValue)
```

- [x] **Step 5: Add retry/refresh action**

Add a Settings button:

```swift
Button {
    Task { await store.refreshRAGDiagnostics() }
} label: {
    Label("刷新 RAG 诊断", systemImage: "arrow.clockwise")
}
.buttonStyle(DropSecondaryButtonStyle())
```

- [x] **Step 6: Run tests**

Run:

```bash
swift test --filter ProviderConfigurationTests
swift test --filter AppStoreTests
```

Expected: pass.

- [x] **Step 7: Commit**

```bash
git add Sources/DropKnow/Views/SettingsView.swift Sources/DropKnow/Stores/AppStore.swift Sources/DropKnow/Support/ProviderConfiguration.swift Tests/DropKnowTests/ProviderConfigurationTests.swift
git commit -m "feat: expand rag settings diagnostics"
```

---

## Task 10: Final Verification and Documentation Sync

**Files:**
- Modify: `docs/superpowers/specs/2026-05-14-v1-rag-vertical-closure-design.md`
- Modify: `docs/code_wiki.md`

- [x] **Step 1: Run Swift tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [x] **Step 2: Run RAG fixture verification**

Run:

```bash
python3 script/verify_rag_fixtures.py
```

Expected with local RAG dependencies configured: fixture verification passes.

If the local machine lacks zvec or provider config, capture the exact classified failure from the helper and verify Settings diagnostics surfaces the same category. Do not mark the RAG fixture verification as passed in the final report unless it actually passes.

- [x] **Step 3: Update design spec status**

In `docs/superpowers/specs/2026-05-14-v1-rag-vertical-closure-design.md`, change:

```markdown
Status: Draft for user review
```

to:

```markdown
Status: Implemented
```

Only do this after Tasks 1-9 are implemented and verification has run.

- [x] **Step 4: Update code wiki**

In `docs/code_wiki.md`, update the RAG/Search section to mention:

```markdown
- Search results now include structured diagnostics, query mode, evidence hit metadata, and active-revision chunk information.
- Settings exposes RAG metadata counts and provider configuration state for internal testing.
- `script/verify_rag_fixtures.py` is the repeatable fixture verification command for the V1 RAG path.
```

- [x] **Step 5: Commit verification/docs**

```bash
git add docs/superpowers/specs/2026-05-14-v1-rag-vertical-closure-design.md docs/code_wiki.md
git commit -m "docs: record v1 rag closure verification"
```

---

## Plan Self-Review

Spec coverage:

- RAG data contract: Tasks 1, 3, 4.
- Real RAG fixture tests: Tasks 2, 3, 10.
- Query routing and tool-like actions: Tasks 5, 7.
- Chat working state and border-beam: Task 6.
- File display and evidence detail: Tasks 7, 8.
- Settings diagnostics: Task 9.
- User workflow and failure recovery: Tasks 5, 7, 8, 9, 10.
- Verification gates: Tasks 2, 3, 6, 10.

The plan avoids deferred filler work. Type names introduced in early tasks are reused consistently in later tasks: `SearchQueryMode`, `SearchDiagnostics`, `RAGIndexState`, `isChatWorking`, `navigateToSearchHit(_:)`, and `refreshRAGDiagnostics()`.
