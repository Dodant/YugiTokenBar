#if os(Linux)
import Foundation

/// Background work transports bytes only. GTK drains and decodes a bounded number per tick.
@MainActor final class LinuxImageLoader {
    enum Size: Int { case grid = 300, detail = 614 }
    typealias Fetch = @Sendable (ImageRequest) async -> Data?
    private struct Event: Sendable { let key: String; let flight: UUID; let data: Data? }
    private final class Inbox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Event] = []
        func put(_ value: Event) { lock.lock(); defer { lock.unlock() }; values.append(value) }
        func pop() -> Event? { lock.lock(); defer { lock.unlock() }; return values.isEmpty ? nil : values.removeFirst() }
    }
    private struct Subscriber { let key: LinuxTextureCache.Key; let receive: (LinuxTextureCache.Texture?) -> Void }
    private struct Flight { let id: UUID; let request: ImageRequest; let task: Task<Void, Never>; var subscribers: [UUID: Subscriber] }
    static let shared = LinuxImageLoader()
    let cache: LinuxTextureCache
    let noImages: Bool
    private let fetch: Fetch
    private let inbox = Inbox()
    private var flights: [String: Flight] = [:]
    private var subscriptions: [UUID: String] = [:]
    private var paused = false
    private var waiting: [String: (ImageRequest, [UUID: Subscriber])] = [:]
    var inFlightCount: Int { flights.count }
    init(cache: LinuxTextureCache = LinuxTextureCache(), noImages: Bool = ProcessInfo.processInfo.environment["YTB_SMOKE_NO_IMAGES"] == "1", fetch: @escaping Fetch = { request in
        await ImageTransport.fetch(request.url, file: ImageSource.cacheDirectory.appendingPathComponent(request.fileName))
    }) { self.cache = cache; self.noImages = noImages; self.fetch = fetch }

    @discardableResult func subscribe(_ request: ImageRequest, size: Size, receive: @escaping (LinuxTextureCache.Texture?) -> Void) -> UUID {
        let token = UUID()
        guard !noImages else {
            let texture = placeholder(size: size)
            LinuxTextureCache.retaining(texture) { receive(texture) }
            return token
        }
        let key = LinuxTextureCache.Key(source: request.key, pixels: size.rawValue)
        if let texture = cache.texture(for: key) {
            LinuxTextureCache.retaining(texture) { receive(texture) }
            return token
        }
        subscriptions[token] = request.key
        let subscriber = Subscriber(key: key, receive: receive)
        if flights[request.key] != nil { flights[request.key]?.subscribers[token] = subscriber; return token }
        if paused {
            if waiting[request.key] != nil { waiting[request.key]?.1[token] = subscriber }
            else { waiting[request.key] = (request, [token: subscriber]) }
            return token
        }
        launch(request, subscribers: [token: subscriber])
        return token
    }
    private func launch(_ request: ImageRequest, subscribers: [UUID: Subscriber]) {
        let id = UUID(), inbox = inbox, fetch = fetch
        let task = Task.detached {
            let data = await fetch(request)
            guard !Task.isCancelled else { return }
            inbox.put(Event(key: request.key, flight: id, data: data))
        }
        flights[request.key] = Flight(id: id, request: request, task: task, subscribers: subscribers)
    }
    func unsubscribe(_ token: UUID) {
        guard let key = subscriptions.removeValue(forKey: token) else { return }
        if waiting[key] != nil {
            waiting[key]?.1.removeValue(forKey: token)
            if waiting[key]?.1.isEmpty == true { waiting.removeValue(forKey: key) }
            return
        }
        guard var flight = flights[key] else { return }
        flight.subscribers.removeValue(forKey: token)
        if flight.subscribers.isEmpty { flight.task.cancel(); flights.removeValue(forKey: key) }
        else { flights[key] = flight }
    }
    /// At most two source results (and four dimension decodes) per GTK tick.
    func drain(maxResults: Int = 2) {
        for _ in 0..<maxResults {
            guard let event = inbox.pop() else { break }
            guard let flight = flights[event.key], flight.id == event.flight else { continue }
            flights.removeValue(forKey: event.key)
            var failed = false
            let groups = Dictionary(grouping: flight.subscribers, by: { $0.value.key })
            for (key, subscribers) in groups {
                let texture = event.data.flatMap { cache.decode($0, for: key) }
                if event.data != nil && texture == nil && !failed {
                    failed = true
                    // Remove before callbacks can subscribe and start their next request.
                    try? FileManager.default.removeItem(at: ImageSource.cacheDirectory.appendingPathComponent(flight.request.fileName))
                }
                LinuxTextureCache.retaining(texture) {
                    for (token, subscriber) in subscribers {
                        // Callbacks may tear down another subscriber during this delivery.
                        guard subscriptions.removeValue(forKey: token) != nil else { continue }
                        subscriber.receive(texture)
                    }
                }
            }
        }
    }
    func placeholder(size: Size) -> LinuxTextureCache.Texture? {
        let key = LinuxTextureCache.Key(source: "bundled-card-back", pixels: size.rawValue)
        if let texture = cache.texture(for: key) { return texture }
        guard let bytes = try? Data(contentsOf: PlatformPaths.resource("card-back.jpg")) else { return nil }
        return cache.decode(bytes, for: key)
    }
    func stop() {
        paused = true
        for (key, flight) in flights {
            flight.task.cancel()
            waiting[key] = (flight.request, flight.subscribers)
        }
        flights.removeAll(); cache.removeAll()
    }
    func resume() {
        guard paused else { return }
        paused = false
        let pending = waiting; waiting.removeAll()
        for (_, (request, subscribers)) in pending { launch(request, subscribers: subscribers) }
    }
}
#endif
