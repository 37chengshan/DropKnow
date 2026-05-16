import Foundation

enum RAGProviderMode: String, Hashable {
    case remoteReady
    case localFallback
    case unavailable
}

struct RAGProviderStatus: Hashable {
    var mode: RAGProviderMode
    var headline: String
    var detail: String?
}

