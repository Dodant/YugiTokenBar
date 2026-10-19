import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Disk-first byte transport; callers own decoded-image tasks and cancellation waiters.
enum ImageTransport {
    /// 호스트당 동시 연결을 줄인다(기본 6). 빠르게 스크롤해도 YGOPRODeck 에 한꺼번에 몰리지 않게.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: config)
    }()
    private static let throttle = Throttle(interval: 0.08)

    /// 호스트별로 요청 시작 시각을 `interval` 간격으로 줄 세운다. 429·503 이면 그 호스트 전체를 한동안 쉰다.
    actor Throttle {
        private let interval: TimeInterval
        private var next: [String: Date] = [:]
        init(interval: TimeInterval) { self.interval = interval }

        func wait(_ host: String) async {
            let now = Date()
            let at = max(next[host] ?? now, now)
            next[host] = at.addingTimeInterval(interval)
            try? await Task.sleep(for: .seconds(at.timeIntervalSince(now)))
        }

        func backoff(_ host: String, seconds: TimeInterval) {
            next[host] = max(next[host] ?? .distantPast, Date().addingTimeInterval(seconds))
        }
    }

    static func fetch(_ url: URL, file: URL) async -> Data? {
        await fetch(url, file: file, session: session, throttle: throttle)
    }

    /// 디스크에 있으면 그대로, 없으면 받는다. 429·503 은 Retry-After(없으면 30초, 최대 120초)만큼 쉬고 한 번 더 시도한다.
    static func fetch(_ url: URL, file: URL, session: URLSession, throttle: Throttle) async -> Data? {
        if let data = try? Data(contentsOf: file) { return data }
        let host = url.host ?? ""
        for attempt in 0..<2 {
            await throttle.wait(host)
            guard !Task.isCancelled, let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 200 {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
                return data
            }
            guard attempt == 0, http.statusCode == 429 || http.statusCode == 503 else { return nil }
            await throttle.backoff(host, seconds: retryDelay(http.value(forHTTPHeaderField: "Retry-After")))
        }
        return nil
    }
    static func retryDelay(_ header: String?) -> TimeInterval {
        let seconds = Double(header ?? "") ?? 30
        return min(max(seconds, 0), 120)
    }
}
