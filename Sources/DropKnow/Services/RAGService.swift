import Foundation

struct RAGIndexRequest: Codable {
    var fileID: String
    var fileName: String
    var filePath: String
    var chunks: [String]
}

struct RAGBatchIndexFile: Codable {
    var fileID: String
    var fileName: String
    var filePath: String
    var contentHash: String
    var revisionID: String
    var chunks: [String]
}

struct RAGBatchIndexRequest: Codable {
    var files: [RAGBatchIndexFile]
}

struct RAGSearchRequest: Codable {
    var query: String
    var topK: Int
}

struct RAGChatRequest: Codable {
    var query: String
}

struct RAGRefineRequest: Codable {
    var fileName: String
    var text: String
    var heuristicSummary: FileSummary
    var heuristicPriority: PriorityLevel
    var eventEvidence: [String]
}

struct RAGProcessResponse: Codable {
    var ok: Bool
    var engine: String?
    var errorCode: String?
    var answer: String?
    var hits: [SearchHit]?
    var summary: FileSummary?
    var priorityLevel: PriorityLevel?
    var keepEvents: Bool?
    var warning: String?
    var error: String?
}

struct RAGBatchIndexResult: Codable, Hashable {
    var fileID: String
    var revisionID: String
}

struct RAGBatchIndexResponse: Codable {
    var ok: Bool
    var engine: String?
    var errorCode: String?
    var warning: String?
    var error: String?
    var results: [RAGBatchIndexResult]?
}

actor RAGService {
    func index(file: DropFile, chunks: [String]) async -> RAGIndexOutcome {
        let batchOutcome = await indexBatch(
            files: [
                RAGBatchIndexFile(
                    fileID: file.id.uuidString,
                    fileName: file.fileName,
                    filePath: file.filePath,
                    contentHash: file.contentHash ?? "",
                    revisionID: file.activeIndexRevision ?? UUID().uuidString,
                    chunks: chunks
                )
            ]
        )
        return RAGIndexOutcome(
            succeeded: batchOutcome.succeeded,
            warning: batchOutcome.warning,
            results: batchOutcome.results
        )
    }

    func indexBatch(files: [RAGBatchIndexFile]) async -> RAGIndexOutcome {
        let request = RAGBatchIndexRequest(files: files)
        do {
            let response: RAGBatchIndexResponse = try await run(mode: "index_batch", payload: request)
            return RAGIndexOutcome(
                succeeded: response.ok,
                warning: response.ok ? response.warning : (response.error ?? response.warning),
                results: response.results ?? []
            )
        } catch {
            return RAGIndexOutcome(succeeded: false, warning: error.localizedDescription, results: [])
        }
    }

    func search(query: String, topK: Int) async throws -> SearchResult {
        let request = RAGSearchRequest(query: query, topK: topK)
        let response: RAGProcessResponse = try await run(mode: "search", payload: request)
        if response.ok {
            return SearchResult(
                answer: response.answer ?? "没有找到足够相关的证据。",
                hits: response.hits ?? [],
                engine: response.engine ?? "zvec",
                warning: response.warning
            )
        }
        throw RAGError.response(code: response.errorCode, message: response.error ?? response.warning ?? "RAG helper failed")
    }

    func chat(query: String) async throws -> SearchResult {
        let request = RAGChatRequest(query: query)
        let response: RAGProcessResponse = try await run(mode: "chat", payload: request)
        if response.ok {
            return SearchResult(
                answer: response.answer ?? "",
                hits: [],
                engine: response.engine ?? "qwen3.5-flash",
                warning: response.warning,
                queryMode: .generalChat
            )
        }
        throw RAGError.response(code: response.errorCode, message: response.error ?? response.warning ?? "Chat helper failed")
    }

    func refine(fileName: String, text: String, summary: FileSummary, priority: PriorityLevel, events: [EventCandidate]) async -> RAGProcessResponse? {
        let request = RAGRefineRequest(
            fileName: fileName,
            text: String(text.prefix(5000)),
            heuristicSummary: summary,
            heuristicPriority: priority,
            eventEvidence: events.prefix(3).map(\.evidence)
        )
        do {
            let response: RAGProcessResponse = try await run(mode: "refine", payload: request)
            return response.ok ? response : nil
        } catch {
            return nil
        }
    }

    private func run<T: Encodable, R: Decodable>(mode: String, payload: T) async throws -> R {
        guard let scriptURL = Bundle.module.url(forResource: "rag_helper", withExtension: "py") else {
            throw RAGError.missingHelper
        }
        try Task.checkCancellation()
        let inputData = try JSONEncoder().encode(payload)
        let python = pythonPath()
        let store = AppPaths.ragStoreURL.path
        let script = scriptURL.path
        let timeout = (mode == "index" || mode == "index_batch") ? 75 : 35
        let task = Task.detached(priority: .userInitiated) {
            try Self.runProcess(
                python: python,
                script: script,
                mode: mode,
                store: store,
                inputData: inputData,
                timeoutSeconds: timeout
            )
        }
        let outputData = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        do {
            return try JSONDecoder().decode(R.self, from: outputData)
        } catch {
            let raw = String(data: outputData, encoding: .utf8) ?? ""
            throw RAGError.process(code: "BAD_RESPONSE", message: raw.isEmpty ? "RAG 返回异常，请重试或检查 Python 环境" : String(raw.prefix(360)))
        }
    }

    private static func runProcess(python: String, script: String, mode: String, store: String, inputData: Data, timeoutSeconds: Int) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script, mode, "--store", store]

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        let group = DispatchGroup()
        var outputData = Data()
        var errorData = Data()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outputData = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorData = error.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        try process.run()
        input.fileHandleForWriting.write(inputData)
        input.fileHandleForWriting.closeFile()

        let timeoutAt = DispatchTime.now() + .seconds(timeoutSeconds)
        while true {
            if Task.isCancelled {
                process.terminate()
                _ = semaphore.wait(timeout: .now() + .seconds(2))
                _ = group.wait(timeout: .now() + .seconds(1))
                throw CancellationError()
            }
            if semaphore.wait(timeout: .now() + .milliseconds(120)) == .success {
                break
            }
            if DispatchTime.now() >= timeoutAt {
                process.terminate()
                _ = semaphore.wait(timeout: .now() + .seconds(2))
                _ = group.wait(timeout: .now() + .seconds(1))
                throw RAGError.process(code: "TIMEOUT", message: "请求超时，请稍后重试或检查网络/API 配置")
            }
        }
        _ = group.wait(timeout: .now() + .seconds(2))
        if process.terminationStatus != 0 {
            let stderr = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw RAGError.process(
                code: "PROCESS_FAILED",
                message: stderr.isEmpty ? "RAG helper 退出（\(process.terminationStatus)）" : String(stderr.prefix(360))
            )
        }
        return outputData
    }

    private func pythonPath() -> String {
        let root: URL
        if Bundle.main.bundleURL.pathExtension == "app" {
            root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        } else {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
        let local = root
            .appendingPathComponent(".venv/bin/python")
            .path
        if FileManager.default.isExecutableFile(atPath: local) {
            return local
        }
        return "/usr/bin/python3"
    }
}

struct RAGIndexOutcome {
    var succeeded: Bool
    var warning: String?
    var results: [RAGBatchIndexResult] = []
}

enum RAGError: LocalizedError {
    case missingHelper
    case response(code: String?, message: String)
    case process(code: String?, message: String)

    var code: String? {
        switch self {
        case .missingHelper: nil
        case .response(let code, _): code
        case .process(let code, _): code
        }
    }

    var suggestedAlertKind: AlertKind {
        switch code {
        case "MISSING_API_KEY", "INVALID_API_KEY", "CONFIG_INVALID", "MISSING_ZVEC":
            .provider
        default:
            .generic
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingHelper: "找不到 RAG helper"
        case .response(let code, let message): Self.userFacingMessage(code: code, raw: message)
        case .process(let code, let message): Self.userFacingMessage(code: code, raw: message)
        }
    }

    private static func userFacingMessage(code: String?, raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        switch code {
        case "MISSING_API_KEY":
            return "未配置 DashScope API Key。请在设置页配置 providers.local.json 或环境变量 DASHSCOPE_API_KEY。"
        case "INVALID_API_KEY":
            return "DashScope API Key 无效或无权限。请在设置页检查 providers.local.json 或环境变量 DASHSCOPE_API_KEY。"
        case "CONFIG_INVALID":
            return "providers.local.json 格式错误。请打开设置修复配置。"
        case "RATE_LIMIT":
            return "接口限流，请稍后重试。"
        case "NETWORK":
            return "网络请求失败，请检查网络后重试。"
        case "TIMEOUT":
            return trimmed.isEmpty ? "请求超时，请稍后重试。" : String(trimmed.prefix(200))
        case "MISSING_ZVEC":
            return trimmed.isEmpty ? "Python 环境缺少 zvec，相关能力暂不可用。" : String(trimmed.prefix(200))
        default:
            return trimmed.isEmpty ? "RAG 运行失败，请稍后重试。" : String(trimmed.prefix(360))
        }
    }
}
