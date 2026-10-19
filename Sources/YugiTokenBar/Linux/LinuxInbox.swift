#if os(Linux)
import Foundation

/// Background work only delivers values; the GTK thread owns all state changes.
final class LinuxInbox: @unchecked Sendable {
    enum Event: Sendable {
        case usage(UInt64, UInt64, UInt64, Result<LinuxUsageSnapshot, StringFailure>)
        case history(UInt64, UInt64, UInt64, String, Result<UsageByDay, StringFailure>)
    }
    struct StringFailure: Error, Sendable { let message: String }
    private let lock = NSLock()
    private var events: [Event] = []
    private var closed = false

    func send(_ event: Event) {
        lock.lock(); defer { lock.unlock() }
        if !closed { events.append(event) }
    }
    func drain() -> [Event] {
        lock.lock(); defer { lock.unlock() }
        let result = events; events.removeAll(); return result
    }
    func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true; events.removeAll()
    }
}

#endif
