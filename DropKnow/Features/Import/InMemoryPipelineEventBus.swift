import Foundation
import Observation

@Observable
public final class InMemoryPipelineEventBus: PipelineEventPublishing {
    public private(set) var events: [PipelineEvent] = []

    public init() {}

    public nonisolated func publish(_ event: PipelineEvent) {
        events.append(event)
    }

    public func clear() {
        events.removeAll()
    }

    public nonisolated func allEvents() -> [PipelineEvent] {
        events
    }
}
