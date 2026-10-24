import Foundation

enum StreamDelivery {
    /// For bufferingOldest continuations, a dropped value was not queued. Wait
    /// for the bounded consumer and enqueue that same value exactly once.
    /// Backpressure is not a response-size failure; byte limits live upstream.
    static func send<Element:Sendable>(_ value:Element,to output:AsyncThrowingStream<Element,Error>.Continuation) async throws {
        while true {
            try Task.checkCancellation()
            switch output.yield(value) {
            case .enqueued: return
            case .dropped: try await Task.sleep(for:.milliseconds(1))
            case .terminated: throw RMError.cancelled
            @unknown default: throw RMError.cancelled
            }
        }
    }
    /// A socket read can contain hundreds of SSE deltas. Keep their order while
    /// publishing contiguous text as one event instead of overflowing a queue.
    static func coalesced(_ events: [ChatEvent]) -> [ChatEvent] {
        var result: [ChatEvent] = [], pending = "", kind = 0
        func flush() {
            if kind == 1 { result.append(.text(pending)) }
            else if kind == 2 { result.append(.reasoning(pending)) }
            pending = ""; kind = 0
        }
        for event in events {
            switch event {
            case .text(let text):
                if kind != 1 { flush(); kind = 1 }; pending += text
            case .reasoning(let text):
                if kind != 2 { flush(); kind = 2 }; pending += text
            default: flush(); result.append(event)
            }
        }
        flush(); return result
    }
    static func yield<Element:Sendable>(_ value:Element,to output:AsyncThrowingStream<Element,Error>.Continuation) throws {
        switch output.yield(value) {
        case .enqueued: break
        case .dropped: throw RMError.tooLarge
        case .terminated: throw RMError.cancelled
        @unknown default: throw RMError.cancelled
        }
    }
}
