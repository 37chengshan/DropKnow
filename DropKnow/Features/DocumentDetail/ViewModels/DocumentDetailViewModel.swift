import Foundation
import Observation

#if canImport(AppKit)
import AppKit
#endif

@Observable
public final class DocumentDetailViewModel {
    public enum State: Equatable {
        case loading
        case empty
        case ready(DocumentDetailData)
        case partialSuccess(DocumentDetailData, message: String)
        case waitingUserConfirmation(DocumentDetailData)
        case blocked(reason: String)
        case failed(message: String)
        case processing(document_id: String, file_name: String)
    }

    public struct DocumentDetailData: Equatable, Sendable {
        public let document_id: String
        public let file_name: String
        public let file_path: String
        public let summary: String?
        public let action_required: String?
        public let risk_flags_json: String?
        public let events: [DocumentEventDTO]

        public init(
            document_id: String,
            file_name: String,
            file_path: String,
            summary: String?,
            action_required: String?,
            risk_flags_json: String?,
            events: [DocumentEventDTO]
        ) {
            self.document_id = document_id
            self.file_name = file_name
            self.file_path = file_path
            self.summary = summary
            self.action_required = action_required
            self.risk_flags_json = risk_flags_json
            self.events = events
        }
    }

    public private(set) var state: State = .loading
    public private(set) var last_action_message: String?

    private let service: any DocumentDetailServicing

    public init(service: any DocumentDetailServicing) {
        self.service = service
    }

    public func load(document_id: String) async {
        state = .loading
        let result = await service.fetchDocumentDetail(document_id: document_id)

        switch result {
        case .failure(let failure):
            state = .failed(message: failure.message)
        case .success(let payload):
            guard let payload else {
                state = .empty
                return
            }

            let data = DocumentDetailData(
                document_id: payload.document.id,
                file_name: payload.document.file_name,
                file_path: payload.document.absolute_path,
                summary: payload.summary?.one_line_summary,
                action_required: payload.summary?.action_required,
                risk_flags_json: payload.summary?.risk_flags_json,
                events: payload.events
            )

            switch payload.document.lifecycle_status {
            case .ready:
                let hasSummary = (data.summary?.isEmpty == false)
                let hasEvents = !data.events.isEmpty
                if hasSummary && hasEvents {
                    state = .ready(data)
                } else if hasSummary || hasEvents {
                    state = .partialSuccess(data, message: "部分结果可用，仍有能力未完成。")
                } else {
                    state = .failed(message: "ready_without_content")
                }
            case .waiting_user_confirmation:
                state = .waitingUserConfirmation(data)
            case .blocked:
                state = .blocked(reason: payload.document.block_reason.rawValue)
            case .failed:
                state = .failed(message: payload.document.last_error_code?.rawValue ?? "unknown")
            case .detected, .processing:
                state = .processing(
                    document_id: payload.document.id,
                    file_name: payload.document.file_name
                )
            case .unknown:
                state = .failed(message: "unknown")
            }
        }
    }

    public func viewDetail(document_id: String) async {
        await load(document_id: document_id)
    }

    public func openOriginalFile(path: String) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        #endif
    }

    public func retryParse(document_id: String) async {
        let result = await service.retryParse(document_id: document_id, source_type: WatchSourceType.manual.rawValue)
        switch result {
        case .success(let ingestionResult):
            last_action_message = "retry: \(String(describing: ingestionResult))"
            await load(document_id: document_id)
        case .failure(let failure):
            last_action_message = "retry_failed: \(failure.error_code.rawValue)"
        }
    }

    public func addToCalendar(event_id: String, document_id: String) async {
        let result = await service.markEventAddedToCalendar(event_id: event_id)
        switch result {
        case .success(let changed):
            last_action_message = changed ? "calendar_added" : "calendar_noop"
            await load(document_id: document_id)
        case .failure(let failure):
            last_action_message = "calendar_failed: \(failure.error_code.rawValue)"
        }
    }

    public func ignore(event_id: String, document_id: String) async {
        let result = await service.ignoreEvent(event_id: event_id)
        switch result {
        case .success(let changed):
            last_action_message = changed ? "event_ignored" : "ignore_noop"
            await load(document_id: document_id)
        case .failure(let failure):
            last_action_message = "ignore_failed: \(failure.error_code.rawValue)"
        }
    }
}
