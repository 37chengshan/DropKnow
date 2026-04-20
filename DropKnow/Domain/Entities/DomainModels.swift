import Foundation

public struct Document: Equatable, Sendable {
    public let id: String
    public let watchDirectoryID: String?
    public let fileName: String
    public let fileExtension: String
    public let absolutePath: String
    public let fileHash: String
    public let fileSize: Int64
    public let importedAt: String
    public let lifecycleStatus: DocumentLifecycleStatus
    public let currentStage: DocumentStage
    public let blockReason: BlockReason
    public let eventStatus: DocumentEventStatus
    public let parseStatus: String?
    public let summaryStatus: String?
    public let privacyStatus: String?
    public let readinessFlagsJSON: String
    public let importanceScore: Double
    public let lastErrorCode: ErrorCode?
    public let lastErrorMessage: String?
}

public struct DocumentSummary: Equatable, Sendable {
    public let documentID: String
    public let documentType: String
    public let oneLineSummary: String
    public let actionRequired: String
    public let keyPointsJSON: String
    public let timeSignalsJSON: String
    public let locationSignalsJSON: String
    public let supportingSnippetsJSON: String
    public let riskFlagsJSON: String
    public let confidence: Double
    public let modelProvider: String
    public let modelName: String
    public let createdAt: String
    public let updatedAt: String
}

public struct DocumentEvent: Equatable, Sendable {
    public let id: String
    public let documentID: String
    public let eventType: String
    public let title: String
    public let startTime: String?
    public let endTime: String?
    public let rawTimeText: String
    public let timezone: String?
    public let location: String?
    public let notes: String?
    public let evidenceSnippet: String
    public let confidence: Double
    public let calendarEligible: Bool
    public let decisionStatus: EventDecisionStatus
    public let calendarStatus: CalendarStatus
    public let calendarEventIdentifier: String?
    public let createdAt: String
    public let updatedAt: String
}

public struct ParseJob: Equatable, Sendable {
    public let id: String
    public let documentID: String
    public let stage: DocumentStage
    public let status: ParseJobStatus
    public let providerID: String?
    public let startedAt: String?
    public let finishedAt: String?
    public let durationMS: Int?
    public let errorCode: ErrorCode?
    public let errorMessage: String?
}
