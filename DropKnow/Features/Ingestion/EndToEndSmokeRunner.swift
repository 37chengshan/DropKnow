import Foundation

public struct EndToEndRunReport: Sendable {
    public let ingestion_result: IngestionResult
    public let recent_documents: [DocumentDTO]
    public let parse_jobs: [ParseJobDTO]
    public let events: [DocumentEventDTO]

    public init(
        ingestion_result: IngestionResult,
        recent_documents: [DocumentDTO],
        parse_jobs: [ParseJobDTO],
        events: [DocumentEventDTO]
    ) {
        self.ingestion_result = ingestion_result
        self.recent_documents = recent_documents
        self.parse_jobs = parse_jobs
        self.events = events
    }
}

public actor EndToEndSmokeRunner {
    private let container: DropKnowV1Container

    public init(container: DropKnowV1Container = DropKnowV1Container()) {
        self.container = container
    }

    public func runSingleDocument(
        fileName: String = "dropknow_e2e_demo.txt",
        content: String = "后天上午十点在北京办公室提交合同，提醒我加入日历"
    ) async -> EndToEndRunReport {
        let ingestionResult = await container.runDemoFlow(
            fileName: fileName,
            content: content,
            sourceType: .manual
        )

        let docsResult = await container.documentRepository.listRecent(limit: 10)
        let docs: [DocumentDTO]
        switch docsResult {
        case .success(let value):
            docs = value
        case .failure:
            docs = []
        }

        guard let document = docs.first else {
            return EndToEndRunReport(
                ingestion_result: ingestionResult,
                recent_documents: [],
                parse_jobs: [],
                events: []
            )
        }

        let jobsResult = await container.parseJobRepository.listRecent(limit: 20)
        let jobs: [ParseJobDTO]
        switch jobsResult {
        case .success(let value):
            jobs = value.filter { $0.document_id == document.id }
        case .failure:
            jobs = []
        }

        let eventsResult = await container.eventRepository.get(document_id: document.id)
        let events: [DocumentEventDTO]
        switch eventsResult {
        case .success(let value):
            events = value
        case .failure:
            events = []
        }

        return EndToEndRunReport(
            ingestion_result: ingestionResult,
            recent_documents: docs,
            parse_jobs: jobs,
            events: events
        )
    }
}
