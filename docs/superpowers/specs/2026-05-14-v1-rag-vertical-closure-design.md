# DropKnow V1 RAG Vertical Closure Design

Date: 2026-05-14
Status: Implemented
Scope: V1 main-path completion for RAG search, chat flow, file display, settings diagnostics, user workflow, and real RAG verification.

## 1. Product Goal

DropKnow is a macOS menu bar app for students. Its V1 promise is not to be a generic chatbot or Spotlight replacement. It is the layer between file download and user reading: when a file lands, the user should quickly know what it is, what matters, what action is required, whether there is a date to track, and how to ask about it later.

This milestone turns the current rough implementation into a testable V1 vertical slice:

1. Import or observe supported files from authorized directories.
2. Parse PDF, DOCX, TXT, and Markdown content.
3. Produce notification-oriented summaries and event candidates.
4. Build a local searchable RAG index with traceable metadata.
5. Let users ask natural-language questions about downloaded files.
6. Return evidence-bound answers with related files and snippets.
7. Let users jump from chat results to the relevant file detail evidence.
8. Explain provider, quota, privacy, queue, and RAG health in settings.
9. Prove the path with repeatable fixture-based RAG tests.

The milestone is complete only when the end-to-end user path works, not when each page receives isolated polish.

## 2. Current Baseline

The existing code already has useful foundations:

- SwiftPM macOS app targeting macOS 14.
- SwiftUI shell with Recent Downloads, Queue, Reminders, AI Search, Subscription, and Settings pages.
- `ProcessingEngine` actor for parse/index queues, retry state, and user-facing quotas.
- `RAGService` bridge from Swift to `rag_helper.py`.
- Python helper with DashScope embeddings/chat, zvec collection storage, sqlite chunk metadata, and active revision filtering.
- File detail sections for summaries, event candidates, explanations, and snippets.
- Unit tests for parser heuristics, processing policy, queue behavior, configuration, quotas, and state recovery.

The current implementation is still too shallow for V1:

- `SearchResult` and `SearchHit` do not carry enough structure for evidence inspection, diagnostics, or precise detail focus.
- Search quality is not proven with real fixture files.
- Chat routing can fall back to generic chat when the user really asked about files.
- File cards do not clearly distinguish parsed, indexed, index-stale, failed, sensitive-gated, and RAG-queryable states.
- File detail is not yet the evidence verification surface for chat hits.
- Settings shows some RAG fields, but it does not function as an actionable diagnostic console.
- There is no repeatable real RAG test that indexes known files and verifies expected questions, hits, and fallback behavior.

## 3. Non-Goals

This milestone does not include:

- PPT, Excel, or image OCR support.
- Global shortcut overlay or full-screen assistant.
- Complex multi-turn autonomous agents.
- Payment/subscription backend integration.
- Production cloud-provider routing where users never configure keys.
- Large-scale `AppStore` architectural rewrite.
- Full visual redesign of every screen.

The implementation should improve boundaries where needed, but only to serve the V1 vertical slice.

## 4. Architecture

### 4.1 Runtime Path

The primary runtime path is:

```text
Authorized directory
  -> DirectoryMonitor
  -> AppStore import/enqueue
  -> ProcessingEngine parse/index queues
  -> DocumentParser
  -> optional refine
  -> RAGService.indexBatch
  -> rag_helper.py embeddings + zvec + sqlite metadata
  -> SearchPage chat query
  -> AppStore query routing
  -> RAGService.search
  -> rag_helper.py retrieval + evidence answer
  -> SearchResult UI
  -> FileDetailView evidence focus
```

### 4.2 Component Responsibilities

`ProcessingEngine`

- Own parse, refine, and index job lifecycle.
- Own quota checks and consumption for parse, search, and chat.
- Expose queue state suitable for Recent Downloads, Queue Page, Settings, and diagnostics.

`RAGService`

- Remain the stable Swift boundary for Python helper calls.
- Decode structured search, answer, diagnostics, and error responses.
- Normalize helper failures into product-level states.

`rag_helper.py`

- Own provider config loading, embeddings, zvec collection access, sqlite metadata, indexing, search, and evidence-bound answer generation.
- Emit enough diagnostics for settings and tests.
- Keep active revision filtering as a hard rule.

`AppStore`

- Continue as the short-term orchestrator.
- Split query routing, fallback construction, result binding, and detail navigation into focused methods.
- Keep UI state consistent on cancellation, replacement requests, quota blocks, and RAG errors.

`SearchPage`

- Become the primary file-question surface.
- Display answer, related files, evidence snippets, warnings, and working state.
- Show a border-beam working affordance while chat/RAG work is active.

`FileDetailView`

- Become the evidence verification page.
- Show parse/index state, notification summary, event candidates, RAG snippets, and focused evidence from chat hits.

`SettingsView`

- Become the internal V1 diagnostic console for directories, provider configuration, quotas, privacy, queues, and RAG health.

## 5. RAG Data Contract

The search response contract should become explicit enough for UI and tests.

`SearchResult` should represent:

- `queryMode`: `fileSearch`, `generalChat`, `localFallback`, `quotaBlocked`, or `errorFallback`.
- `answer`: the user-facing direct answer.
- `hits`: ordered evidence hits.
- `engine`: concise engine label.
- `warning`: optional user-facing warning.
- `diagnostics`: structured runtime details.

Each `SearchHit` should represent:

- `id`: stable chunk id.
- `fileID`: bound Swift file id when available.
- `fileName`.
- `filePath`.
- `snippet`.
- `score`.
- `chunkIndex`.
- `revisionID`.
- `matchReason`: short explanation for UI when useful.

`SearchDiagnostics` should represent:

- `embeddingEngine`.
- `embeddingModel`.
- `chatModel`.
- `topK`.
- `chatUsed`.
- `fallbackReason`.
- `indexedFileCount`.
- `chunkCount`.
- `activeRevisionCount`.
- `emptyIndex`.
- `providerConfigured`.

The first implementation may omit fields that are expensive to compute, but every omitted field must have a deliberate default and must not break UI rendering or tests.

## 6. RAG Retrieval Behavior

### 6.1 Indexing

Indexing must preserve current active-revision semantics:

- Every indexed file has `fileID`, `revisionID`, `contentHash`, file metadata, and chunk text.
- Only active revisions are eligible for search answers.
- Re-indexing a file should not let stale chunks appear in answers.
- Helper diagnostics should report indexed file count, chunk count, and active revision count from sqlite.

### 6.2 Search

Search must support PRD-style questions:

- "高数考试在哪天"
- "报名截止是什么时候"
- "上周那个报名通知讲了什么"
- "这份通知要我做什么"
- "哪个文件提到了地点"

Rules:

- If evidence is insufficient, the answer must say so clearly.
- If hits exist but chat generation is unavailable, return a local fallback answer using the top hit and evidence snippet.
- If the index is empty, return an actionable empty-index message instead of a generic error.
- If zvec or provider config is missing, return a classified error that Settings can explain.
- Top hits must be tied back to the app's `DropFile` records where possible.

### 6.3 Answer Generation

When chat generation is available:

- The model prompt must require answers only from supplied evidence.
- The answer should mention relevant files naturally.
- The answer should not invent dates, locations, or actions.
- Evidence insufficiency must be an acceptable final answer.

When chat generation is unavailable:

- The local answer should state that it is a fallback.
- It should name the top related file and include a short evidence excerpt.
- It should still render file cards and snippets.

## 7. Chat Flow and Tool Actions

This milestone does not require LLM function calling. It does require product-level tool actions expressed through structured app state.

### 7.1 Query Routing

The default route should favor file search when the query appears to ask about downloaded files, notices, dates, deadlines, exams, registration, payment, class schedules, assignments, locations, or previously downloaded content.

Generic chat remains available, but it should not steal common DropKnow use cases. The user should not need to prefix every product query with "查文件".

### 7.2 Tool Actions

Supported app actions:

- `searchFiles(query)`: run RAG search and return structured hits.
- `openFileDetail(fileID, anchor)`: navigate to a file and focus the relevant section.
- `explainEvidence(hit)`: show why an answer used a file/snippet.
- `recoverFromRAGFailure(reason)`: show next steps for missing index, missing zvec, missing provider config, quota block, no hits, or cancellation.

These actions may be implemented as Swift methods and UI interactions, not LLM tool calls.

### 7.3 Conversation State

The chat flow must handle:

- Debounced submit.
- Active search.
- User cancellation.
- Replacement by a newer query.
- Quota exhaustion.
- Missing API key.
- Missing zvec.
- Empty index.
- No hits.
- Chat generation failure after retrieval succeeds.

The UI must never keep showing a working state after cancellation or replacement.

## 8. Chat Working State and Border-Beam

The chat page should communicate active work with both motion and text.

### 8.1 Working State

The chat surface enters `working` while any of these are active:

- Submit debounce is waiting.
- RAG retrieval is running.
- Chat answer generation is running.
- Tool action is resolving.
- Retry is running.

It exits `working` when:

- A final answer or fallback result is appended.
- The request is cancelled.
- A newer request replaces it.
- A quota/provider/index error is converted to a final message.

### 8.2 Border-Beam Visual

While `working`, the main chat conversation container should display a subtle animated border-beam:

- Thin border around the active chat work area.
- Low-saturation accent, consistent with existing DropKnow styling.
- No full-screen glow and no decorative blobs.
- It should frame the workspace rather than individual text bubbles.
- It should not resize content or cause layout shift.

The border-beam is a working indicator, not a decorative effect. It must be tied to real state.

### 8.3 Accessible Fallback

If the system reduce-motion setting is active:

- Disable animated beam movement.
- Show a static accent border plus existing `ProgressView`.
- Preserve text status such as "正在检索文件", "正在整理证据", or "正在生成回答".

### 8.4 Testing

The implementation should test or otherwise verify:

- `working` is true during active/debounced searches.
- `working` turns false on cancellation.
- `working` turns false when a fallback result is produced.
- Newer queries stop the older query's working affordance.

## 9. File Display

File display should answer one user question: can this file be understood, trusted, and asked about?

### 9.1 Recent Downloads Cards

Each card should show:

- File name and type.
- One-line summary when available.
- Parse status.
- RAG/index state: not indexed, indexing, indexed, index stale, or index failed.
- Priority level.
- Event count or high-confidence event marker.
- Error/sensitive gate marker when relevant.

The card should not imply that a file is searchable until indexing actually succeeded.

### 9.2 File Detail

The detail page should show:

- Header with file metadata, parse status, and index status.
- Sensitive-gate controls when needed.
- Notification summary in the PRD structure.
- Importance explanation.
- Event candidates with confidence and calendar action availability.
- RAG evidence snippets.
- Chat-focused evidence section when opened from a hit.
- Error section with concrete next action.

### 9.3 Evidence Navigation

From a chat hit:

- Clicking the related file should select the file in Recent Downloads.
- The detail pane should focus the evidence/snippet section.
- The target evidence should be visually highlighted long enough to confirm navigation.
- If the exact snippet is unavailable, focus the snippets section and show a warning.

## 10. Settings and Diagnostics

Settings should support real internal testing and user recovery.

### 10.1 Basic Settings

Include:

- Auto-parse new files.
- First import limited to recent 7 days for V1.
- Sensitive files always ask.

### 10.2 Directory Settings

Include:

- Current watched directories.
- Add/remove directory.
- Free-plan one-directory limit.
- Clear message when a directory cannot be added.

### 10.3 Provider Status

Include:

- Whether provider config is detected.
- Config source: environment or `providers.local.json`.
- Chat model.
- Embedding model and dimension.
- Last provider error.
- Button to open config location.

The UI should make clear that the current local development build may need provider configuration, while the PRD production target is app-managed provider calls.

### 10.4 RAG Diagnostics

Include:

- zvec availability.
- RAG store path.
- sqlite metadata path.
- Indexed file count.
- Chunk count.
- Active revision count.
- Last index error.
- Last search error.
- Empty-index state.

### 10.5 Quotas and Queue

Include:

- Parse/search/chat daily usage and remaining count.
- Parse queue summary.
- Index queue summary.
- Failed job retry action.
- Upgrade entry when quota or plan limits block the workflow.

### 10.6 Privacy

Include:

- Sensitive-file policy.
- Trusted directories.
- Files ignored forever.
- Explanation that suspected sensitive files do not go to remote refine by default.

## 11. User Workflows

### 11.1 First Use

1. User opens app.
2. App recommends Downloads or lets user choose one custom directory.
3. App imports only recent 7-day files.
4. Files enter queue without notification spam.
5. User sees import and queue progress.
6. Indexed files become queryable.

### 11.2 New File

1. User downloads a supported file.
2. Directory monitor waits for file stability.
3. Processing queue parses the file.
4. Sensitive file gates before remote refine.
5. Summary, event candidates, and index state update.
6. High-priority files surface with actionable UI.

### 11.3 Ask About Files

1. User asks a natural question in chat.
2. Chat enters working state with border-beam.
3. App routes to file search when appropriate.
4. RAG retrieves active-revision chunks.
5. Answer is generated from evidence or falls back locally.
6. Chat shows answer, related files, snippets, diagnostics warning if needed.
7. User clicks a file and lands on evidence in detail.

### 11.4 Recover From Failure

Failures must end in visible, actionable states:

- Empty index: prompt to import or rebuild missing indexes.
- Missing provider: show config path and explain local fallback.
- Missing zvec: explain Python environment problem.
- Quota exhausted: show remaining/used count and upgrade entry.
- No hits: say evidence is insufficient and suggest checking indexed files.
- Parse/index failed: link to queue retry.

## 12. Testing Strategy

### 12.1 Fixture Set

Create a small deterministic fixture set for RAG tests:

- Exam notice with date, location, and course name.
- Registration deadline notice with action and cutoff.
- Class schedule notice.
- Plain lecture material that should not be treated as urgent.
- Unrelated document to test false positives.
- TXT/MD fixtures first; DOCX/PDF can be added when test tooling is stable.

### 12.2 Python Helper Tests

Verify:

- `index_batch` writes chunk metadata and active revisions.
- `search` returns the expected file for known questions.
- Search ignores inactive revisions.
- Empty index returns a classified empty result.
- Missing API key still allows local fallback when embeddings are available.
- Missing zvec returns a classified error.

### 12.3 Swift Tests

Verify:

- Query routing chooses file search for PRD-style questions.
- Search result binding maps helper `fileID`/path to app files.
- Fallback results preserve warnings and hits.
- Detail focus request targets the snippet/evidence section.
- Working state maps correctly to debounce, active search, cancellation, and fallback.
- Quota blocks produce final messages and stop working state.

### 12.4 Integration Verification

Add a repo-local verification command or script that:

1. Creates a temporary RAG store.
2. Indexes fixture files through the helper.
3. Runs representative questions.
4. Asserts expected file names and evidence substrings.
5. Prints a compact pass/fail report.

The milestone should not be considered complete unless `swift test` and the RAG fixture verification pass.

### 12.5 Final Verification Result

Verification run on 2026-05-15:

- `swift test` passed: 96 XCTest tests, 0 failures.
- `python3 script/verify_rag_fixtures.py` did not pass on this machine because the Python environment is missing zvec. The helper classified the failure as `MISSING_ZVEC` with error `Python 环境缺少 zvec：No module named 'zvec'`.

The fixture harness is present and repeatable, but real fixture pass remains environment-dependent until zvec is installed/configured locally.

## 13. Acceptance Criteria

The milestone is accepted when:

- A user can import supported files and see parse/index progress.
- Indexed files are clearly marked as queryable.
- PRD-style file questions route to RAG without requiring a special prefix.
- Chat working state displays a border-beam and text status while work is real.
- Border-beam stops on success, fallback, cancellation, and replacement.
- Answers include related files and evidence snippets.
- Clicking a chat hit opens file detail and focuses evidence.
- Settings explains provider, RAG store, zvec, metadata, quotas, queues, and privacy state.
- Empty index, no hit, missing provider, missing zvec, quota block, and failed job states are recoverable from the UI.
- Fixture-based RAG verification proves index/search/evidence behavior.
- `swift test` passes.

## 14. Implementation Order

1. Add RAG fixture and verification harness.
2. Extend RAG helper output contract and diagnostics.
3. Extend Swift RAG models and `RAGService` decoding.
4. Refine AppStore query routing, fallback, result binding, and working state.
5. Implement chat result UI and border-beam working state.
6. Add evidence navigation from chat hits to file detail.
7. Improve Recent Downloads cards and file detail index/evidence state.
8. Improve Settings diagnostics for provider, RAG, quotas, queues, and privacy.
9. Add Swift tests for routing, binding, navigation, fallback, and working state.
10. Run full verification and fix vertical-slice breaks.

## 15. Risks

- Real RAG tests may be flaky if they depend on remote embeddings. The harness should separate local contract tests from remote-provider tests when needed.
- zvec availability may differ across developer machines. Missing-zvec behavior must be classified and testable.
- Adding too much UI polish before the RAG contract stabilizes can create rework. The data contract should land first.
- AppStore is already large. Edits should extract small helpers where useful, but avoid a broad refactor during this milestone.
