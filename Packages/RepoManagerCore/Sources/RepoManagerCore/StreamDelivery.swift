import Foundation

enum StreamDelivery {
    static func yield<Element:Sendable>(_ value:Element,to output:AsyncThrowingStream<Element,Error>.Continuation) throws {
        switch output.yield(value) {
        case .enqueued: break
        case .dropped: throw RMError.tooLarge
        case .terminated: throw RMError.cancelled
        @unknown default: throw RMError.cancelled
        }
    }
}
