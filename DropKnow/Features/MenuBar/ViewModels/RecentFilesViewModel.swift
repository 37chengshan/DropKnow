import Foundation
import Observation

@Observable
public final class RecentFilesViewModel {
    public enum State: Equatable {
        case loading
        case empty
        case loaded
        case error(message: String)
    }

    public struct Item: Equatable, Sendable {
        public let document_id: String
        public let file_name: String
        public let subtitle: String
        public let key_points: [String]
        public let lifecycle_status: DocumentLifecycleStatus
        public let imported_at: String

        public init(
            document_id: String,
            file_name: String,
            subtitle: String,
            key_points: [String],
            lifecycle_status: DocumentLifecycleStatus,
            imported_at: String
        ) {
            self.document_id = document_id
            self.file_name = file_name
            self.subtitle = subtitle
            self.key_points = key_points
            self.lifecycle_status = lifecycle_status
            self.imported_at = imported_at
        }
    }

    public private(set) var state: State = .loading
    public private(set) var items: [Item] = []

    private let service: any DashboardServicing

    public init(service: any DashboardServicing) {
        self.service = service
    }

    public func load(limit: Int = 30) async {
        state = .loading

        let result = await service.fetchRecentFiles(limit: limit)
        switch result {
        case .failure(let failure):
            items = []
            state = .error(message: failure.message)
        case .success(let snapshots):
            items = snapshots.map {
                Item(
                    document_id: $0.document_id,
                    file_name: $0.file_name,
                    subtitle: Self.subtitle(from: $0),
                    key_points: $0.key_points,
                    lifecycle_status: $0.lifecycle_status,
                    imported_at: $0.imported_at
                )
            }

            state = items.isEmpty ? .empty : .loaded
        }
    }

    private static func subtitle(from snapshot: RecentFileSnapshot) -> String {
        switch snapshot.lifecycle_status {
        case .ready:
            return snapshot.summary_text ?? "摘要准备完成"
        case .waiting_user_confirmation:
            return "等待用户确认风险"
        case .blocked:
            return "已阻断：\(snapshot.block_reason.rawValue)"
        case .failed:
            if let code = snapshot.last_error_code {
                return "失败：\(code.rawValue)"
            }
            return "处理失败"
        case .detected, .processing:
            return "处理中"
        case .unknown:
            return "状态未知"
        }
    }
}
