import Foundation
import Observation

@Observable
public final class SearchViewModel {
    public struct AnswerData: Equatable, Sendable {
        public let answer: String
        public let citations: [CitationResponse]

        public init(answer: String, citations: [CitationResponse]) {
            self.answer = answer
            self.citations = citations
        }
    }

    public enum State: Equatable {
        case idle(suggestions: [String])
        case retrieving
        case assembling
        case answering
        case searchResults([SearchSnapshot.SearchResultItem])
        case answer(AnswerData)
        case noResult(message: String)
        case blocked(reason: SearchBlockReason, message: String)
        case failed(message: String)
    }

    public let suggestions: [String] = [
        "这周有哪些考试安排？",
        "有哪些需要我处理的截止日期？",
        "帮我找和报名相关的通知",
        "有哪些文件提到了明天？"
    ]

    public var mode: QuickMode = .search
    public private(set) var state: State
    public var selectedSuggestionIndex: Int?

    private let service: any SearchServicing
    private var latestRequestID: UUID = UUID()

    public init(service: any SearchServicing) {
        self.service = service
        self.state = .idle(suggestions: suggestions)
    }

    public func run(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle(suggestions: suggestions)
            return
        }

        let requestID = UUID()
        latestRequestID = requestID

        state = .retrieving
        if mode == .search {
            state = .assembling
        } else {
            state = .answering
        }

        let response = await service.ask(question: trimmed, mode: mode)
        guard requestID == latestRequestID else {
            return
        }
        state = mapState(from: response)
    }

    public func reset() {
        state = .idle(suggestions: suggestions)
    }

    public func useSuggestion(_ suggestion: String) async {
        await run(suggestion)
    }

    private func mapState(from snapshot: SearchSnapshot) -> State {
        switch snapshot.status {
        case .idle:
            return .idle(suggestions: suggestions)
        case .retrieving:
            return .retrieving
        case .assembling:
            return .assembling
        case .answering:
            return .answering
        case .success:
            switch snapshot.mode {
            case .search:
                return .searchResults(snapshot.results)
            case .qa:
                return .answer(AnswerData(answer: snapshot.answer, citations: snapshot.citations))
            }
        case .no_result:
            return .noResult(message: snapshot.answer)
        case .blocked:
            return .blocked(reason: snapshot.block_reason, message: snapshot.answer)
        case .failed:
            return .failed(message: snapshot.answer)
        case .unknown:
            return .failed(message: "搜索状态未知，请重试。")
        }
    }
}
