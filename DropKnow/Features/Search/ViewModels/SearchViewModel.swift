import Foundation
import Observation

@Observable
public final class SearchViewModel {
    public private(set) var status: SearchStatus = .idle
    public private(set) var answer: String = ""
    public private(set) var citations: [CitationResponse] = []

    private let service: any SearchServicing

    public init(service: any SearchServicing) {
        self.service = service
    }

    public func ask(_ question: String) async {
        status = .answering
        let response = await service.ask(question: question)
        status = response.status
        answer = response.answer
        citations = response.citations
    }
}
