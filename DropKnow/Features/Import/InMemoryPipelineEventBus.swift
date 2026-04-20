import Foundation

public actor InMemoryPipelineEventBus: PipelineEventPublishing {
    private var events: [PipelineEvent] = []

    public init() {}

    public func publish(_ event: PipelineEvent) async {
        events.append(event)
    }

    public func allEvents() -> [PipelineEvent] {
        events
    }
}
