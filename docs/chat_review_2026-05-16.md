# DropKnow Chat 页面多维度审查报告

> 审查日期：2026-05-16
> 审查范围：Chat 页面体验、流式传输、Markdown 排版、光圈特效、整体架构

---

## 一、核心体验问题（P0）

### 1.1 非流式传输 — 体验致命缺陷

**现状分析：**

当前数据流路径：
```
用户发送 → submitSearch() → performSearch()
  → rag.chat(query:) → RAGService.run(mode: "chat")
    → 启动 Python 子进程 → general_chat_answer()
      → urllib.request.urlopen() 同步等待完整响应
    → 子进程退出，stdout 一次性返回 JSON
  → 解析 JSON → chatMessages.append(完整消息)
```

用户体验：发送后等待 5-30 秒，期间只有 spinner + "正在检索文件并整理证据"，然后突然出现完整回答。

**根因：**
1. `rag_helper.py` 的 `general_chat_answer()` 使用同步 HTTP 请求，不支持 SSE
2. `RAGService.runProcess()` 等待子进程完全退出后才读取 stdout
3. 没有增量更新 `ChatMessage.text` 的机制

**重构方案（根本解决）：**

Python 侧改造：
```python
def chat_stream(payload, store):
    config = load_provider_config(store)
    payload_body = {
        "model": config["chat_model"],
        "messages": [...],
        "stream": True,  # 关键：启用 SSE
    }
    request = urllib.request.Request(url, data=..., headers=...)
    with urllib.request.urlopen(request, timeout=60) as response:
        for line in response:
            line = line.decode("utf-8").strip()
            if line.startswith("data: ") and line != "data: [DONE]":
                chunk = json.loads(line[6:])
                delta = chunk["choices"][0]["delta"].get("content", "")
                if delta:
                    # 每个 token 立即输出一行
                    print(json.dumps({"type": "delta", "text": delta}), flush=True)
        print(json.dumps({"type": "done"}), flush=True)
```

Swift 侧改造：
```swift
// RAGServing 协议新增
func chatStream(query: String) -> AsyncThrowingStream<String, Error>

// RAGService 实现
func chatStream(query: String) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task.detached {
            let process = Process()
            // ... 配置子进程 ...
            let outputPipe = Pipe()
            process.standardOutput = outputPipe

            try process.run()
            inputPipe.fileHandleForWriting.write(inputData)
            inputPipe.fileHandleForWriting.closeFile()

            // 逐行读取 stdout
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                guard let data = line.data(using: .utf8),
                      let msg = try? JSONDecoder().decode(StreamDelta.self, from: data)
                else { continue }
                switch msg.type {
                case "delta": continuation.yield(msg.text ?? "")
                case "done": continuation.finish()
                default: break
                }
            }
        }
    }
}
```

AppStore 侧改造：
```swift
func performStreamingChat() async {
    let assistantMessage = ChatMessage(role: .assistant, text: "", isStreaming: true)
    chatMessages.append(assistantMessage)

    do {
        for try await delta in rag.chatStream(query: query) {
            if let index = chatMessages.lastIndex(where: { $0.id == assistantMessage.id }) {
                chatMessages[index].text += delta
            }
        }
        // 标记流式结束
        if let index = chatMessages.lastIndex(where: { $0.id == assistantMessage.id }) {
            chatMessages[index].isStreaming = false
        }
    } catch { ... }
}
```

---

### 1.2 Markdown 排版全部挤在一起

**现状分析：**

`SearchPage.swift:322-340` 的 `MarkdownText`：
```swift
private struct MarkdownText: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(.body)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
```

`AttributedString(markdown:)` 只支持 **inline** 标记（粗体、斜体、链接、代码 span）。
**不支持**：标题层级、段落间距、代码块、列表缩进、引用块、表格。

LLM 返回的结构化回答（标题、列表、代码块）全部被压平成一段纯文本。

**重构方案（根本解决）：**

方案 A — 引入 swift-markdown-ui（推荐）：
```swift
// Package.swift 添加依赖
.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")

// 替换 MarkdownText
import MarkdownUI

struct ChatMarkdownView: View {
    let content: String

    var body: some View {
        Markdown(content)
            .markdownTheme(.dropKnow) // 自定义主题
            .textSelection(.enabled)
    }
}
```

方案 B — 自建轻量渲染器（无外部依赖）：
```swift
import SwiftUI

struct BlockMarkdownView: View {
    let source: String
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let blocks = MarkdownParser.parse(source)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let level):
                    Text(block.text)
                        .font(headingFont(level))
                        .padding(.top, level == 1 ? 8 : 4)
                case .paragraph:
                    Text(inlineMarkdown(block.text))
                        .font(.body)
                case .codeBlock(let lang):
                    CodeBlockView(code: block.text, language: lang)
                case .listItem(let ordered, let index):
                    ListItemView(text: block.text, ordered: ordered, index: index)
                case .blockquote:
                    BlockquoteView(text: block.text)
                }
            }
        }
        .textSelection(.enabled)
    }
}
```

推荐方案 A，成熟度高、维护活跃、支持自定义主题。

---

## 二、光圈特效优化（P1）

### 2.1 当前实现问题

`GlassSurface.swift:56-116` 的 `DropWorkingBorderBeamModifier`：

```swift
AngularGradient(
    colors: [
        palette.accentOrange.opacity(0.06),
        palette.accentOrange,
        palette.accentBlue,
        palette.accentOrange.opacity(0.06)
    ],
    center: .center
)
.rotationEffect(.degrees(rotation))
.mask(shape.stroke(lineWidth: max(theme.metrics.borderWidth * 3, 2.5)))
.shadow(color: palette.accentOrange.opacity(0.18), radius: 10)
```

**性能问题：**
1. `AngularGradient` 每帧重新计算渐变颜色插值
2. `.rotationEffect` 触发整个 overlay 层重绘
3. `.shadow(radius: 10)` 叠加在旋转动画上，每帧做高斯模糊
4. 动画 duration 2.2s + repeatForever = 持续高 GPU 占用

**优化方案：**

```swift
private struct DropWorkingBorderBeamModifier: ViewModifier {
    @State private var rotation = 0.0
    var isActive: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    // 方案：用 drawingGroup() 光栅化渐变层
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                        let angle = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 2.2) / 2.2 * 360

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                AngularGradient(
                                    colors: beamColors,
                                    center: .center,
                                    angle: .degrees(angle)
                                ),
                                lineWidth: 2.5
                            )
                            .drawingGroup() // 关键：光栅化，避免每帧重算
                    }
                    // 静态 glow，不随旋转变化
                    .shadow(color: .orange.opacity(0.15), radius: 8)
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
    }
}
```

**关键改进：**
- `drawingGroup()` 将渐变光栅化为位图，GPU 只做旋转变换
- `TimelineView` 限制 30fps（思考动画不需要 120fps）
- shadow 改为静态，不参与旋转
- 流式传输期间光圈持续，完成后 opacity 渐隐

---

## 三、架构问题（P1-P2）

### 3.1 AppStore God Object（2139 行）

**问题：** 单个类承担 10+ 职责，任何改动都可能影响全局。

**拆分建议：**

| 新模块 | 职责 | 从 AppStore 提取的方法 |
|--------|------|----------------------|
| `ChatStore` | 聊天消息、流式状态、搜索路由 | performSearch, submitSearch, cancelSearch, chatMessages |
| `FileStore` | 文件 CRUD、导入、扫描 | importRecentFiles, scanForNewFiles, upsert, saveFiles |
| `ProcessingCoordinator` | 队列调度、重试 | startProcessingIfNeeded, handleParse/Refine/IndexBatch |
| `NavigationStore` | 导航状态、焦点 | navigateToFile, pendingNavigation, detailFocusRequest |
| `SettingsStore` | 设置读写、订阅计划 | saveSettings, normalizedSettings |

### 3.2 Python 子进程冷启动开销

**现状：** 每次请求都 fork 新进程，加载 Python 解释器 + import 链 + 连接 SQLite。

**优化路径：**

阶段 1（配合流式传输）：
- Python 改为 stdin/stdout JSON-RPC 长驻进程
- Swift 侧维护一个 `actor PythonBridge`，管理进程生命周期
- 首次调用时启动，idle 5 分钟后自动退出

阶段 2（长期）：
- 将 embedding + 向量搜索迁移到 Swift 原生（用 Accelerate 框架）
- 只保留 DashScope API 调用在 Python 侧（或直接用 URLSession）

---

## 四、用户体验问题（P2）

### 4.1 输入框交互不符合 Mac 习惯

**现状：** `onSubmit` 拦截 Enter 键发送。多行 TextField 中用户无法换行。

**修复：**
```swift
TextField("...", text: $store.searchQuery, axis: .vertical)
    .lineLimit(1...4)
    .onKeyPress(.return, modifiers: .command) {
        store.submitSearch()
        return .handled
    }
    // 移除 .onSubmit
```

### 4.2 错误信息位置不合理

错误显示在页面顶部 banner，用户可能已滚动到底部。应改为在 chat 流中内联显示：
```swift
ChatMessage(role: .assistant, text: errorText, isError: true)
```

### 4.3 无消息时间戳和操作菜单

建议添加：
- hover 时显示时间戳
- 右键菜单：复制、重新生成、删除

### 4.4 思考状态文案不准确

通用 chat 时显示"正在检索文件并整理证据"，应根据 `shouldRouteToFileSearch` 结果动态切换：
- 文件搜索："正在检索文件并整理证据"
- 通用问答："正在思考..."

---

## 五、性能问题（P2-P3）

### 5.1 ChatBubble 不必要的重绘

`MarkdownText` 每次 body 调用都重新解析 markdown。流式传输时每个 delta 都触发解析。

**优化：**
- 将解析结果缓存（`@State` 或 model 层预计算）
- 流式期间用纯 `Text` 显示，流式结束后切换为 Markdown 渲染

### 5.2 滚动逻辑不适配流式

```swift
.onChange(of: store.chatMessages.count) { ... }
```

流式传输时 count 不变（只是 last message 的 text 在更新），不会触发自动滚动。

**修复：**
```swift
.onChange(of: store.chatMessages.last?.text.count) {
    if let last = store.chatMessages.last?.id {
        proxy.scrollTo(last, anchor: .bottom)
    }
}
```

### 5.3 文件扫描 I/O 阻塞

`recentSupportedFiles()` 中 `FileManager.enumerator` 是同步 I/O。大目录（如 Downloads 有数千文件）会阻塞。

**修复：** 移到 `Task.detached` 中执行。

---

## 六、实施路线图

```
Phase 1（1-2 天）— 流式传输 + Markdown
├── Python: 新增 chat_stream mode，DashScope stream=true
├── Swift: RAGService.chatStream() → AsyncThrowingStream
├── AppStore: performStreamingChat() 逐 delta 更新
├── Package.swift: 添加 swift-markdown-ui 依赖
├── 替换 MarkdownText → Markdown (swift-markdown-ui)
└── 修复滚动逻辑适配流式

Phase 2（0.5 天）— 光圈优化
├── TimelineView + drawingGroup() 替换当前实现
├── 静态 shadow 替换旋转 shadow
└── 流式结束渐隐动画

Phase 3（1 天）— 交互打磨
├── Cmd+Enter 发送
├── 动态思考文案
├── 错误内联显示
└── 消息时间戳 + 右键菜单

Phase 4（后续）— 架构优化
├── 提取 ChatStore
├── Python 长驻进程
└── 消息持久化
```

---

## 七、总结

当前 Chat 页面的三个致命体验问题：
1. **非流式** — 用户等待焦虑，无中间反馈
2. **Markdown 不渲染** — 结构化内容变成一坨文字
3. **光圈性能** — 低端机卡顿

这三个问题都需要**根本重构**而非补丁修复。流式传输需要改造整个数据通路（Python SSE → Swift AsyncStream → UI 增量更新），Markdown 需要替换渲染引擎，光圈需要换用 GPU 友好的实现方式。

建议 Phase 1 优先实施，它带来的体验提升是质变级别的。
