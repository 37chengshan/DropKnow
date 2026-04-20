import SwiftUI

public struct DocumentDetailSceneView: View {
    private let document_id: String
    private let container: DropKnowV1Container

    public init(document_id: String, container: DropKnowV1Container = DropKnowV1Container()) {
        self.document_id = document_id
        self.container = container
    }

    public var body: some View {
        DocumentDetailView(
            document_id: document_id,
            viewModel: container.makeDocumentDetailViewModel()
        )
    }
}
