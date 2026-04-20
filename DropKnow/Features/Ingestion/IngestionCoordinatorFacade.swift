import Foundation

public actor IngestionCoordinatorFacade {
    private let coordinator: IngestionCoordinator

    public init(coordinator: IngestionCoordinator) {
        self.coordinator = coordinator
    }

    public func ingest(_ request: IngestionRequest) async -> IngestionResult {
        await coordinator.ingest(request)
    }

    public func interrupt(document_id: String) async {
        await coordinator.requestInterruption(document_id: document_id)
    }

    public func recover(document_id: String, request: IngestionRequest) async -> IngestionResult {
        await coordinator.recover(document_id: document_id, request: request)
    }
}
