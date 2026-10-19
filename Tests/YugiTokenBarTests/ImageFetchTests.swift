import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import YugiTokenBar

/// 미리 넣어 둔 상태 코드를 차례로 돌려주는 가짜 서버. 요청 시각을 기록한다.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedCodes: [Int] = []
    private nonisolated(unsafe) static var storedRetryAfter: String?
    private nonisolated(unsafe) static var storedTimes: [Date] = []
    static var codes: [Int] {
        get { lock.withLock { storedCodes } }
        set { lock.withLock { storedCodes = newValue } }
    }
    static var retryAfter: String? {
        get { lock.withLock { storedRetryAfter } }
        set { lock.withLock { storedRetryAfter = newValue } }
    }
    static var times: [Date] {
        get { lock.withLock { storedTimes } }
        set { lock.withLock { storedTimes = newValue } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, retryAfter) = Self.lock.withLock {
            Self.storedTimes.append(Date())
            return (Self.storedCodes.isEmpty ? 200 : Self.storedCodes.removeFirst(), Self.storedRetryAfter)
        }
        let headers = retryAfter.map { ["Retry-After": $0] }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1, 2, 3]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct ImageFetchTests {
    private func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    private func run(codes: [Int], retryAfter: String? = nil, interval: TimeInterval = 0) async -> (Data?, [Date]) {
        StubProtocol.codes = codes
        StubProtocol.retryAfter = retryAfter
        StubProtocol.times = []
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("a.jpg")
        let data = await ImageTransport.fetch(URL(string: "https://example.test/a")!, file: file, session: stubSession(),
                                          throttle: ImageTransport.Throttle(interval: interval))
        return (data, StubProtocol.times)
    }

    @Test func diskCacheSkipsNetwork() async throws {
        StubProtocol.times = []
        let file = tempDir().appendingPathComponent("cached.jpg")
        let expected = Data([9, 8, 7])
        try expected.write(to: file)
        let data = await ImageTransport.fetch(URL(string: "https://example.test/disk")!, file: file,
                                             session: stubSession(), throttle: .init(interval: 0))
        #expect(data == expected)
        #expect(StubProtocol.times.isEmpty)
    }

    @Test func successfulResponseIsWrittenAtomicallyToDisk() async throws {
        StubProtocol.codes = [200]
        StubProtocol.retryAfter = nil
        StubProtocol.times = []
        let file = tempDir().appendingPathComponent("nested/download.jpg")
        let data = await ImageTransport.fetch(URL(string: "https://example.test/download")!, file: file,
                                             session: stubSession(), throttle: .init(interval: 0))
        #expect(data == Data([1, 2, 3]))
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func givesUpAfterSecond503() async {
        let (data, times) = await run(codes: [503, 503, 200], retryAfter: "0")
        #expect(data == nil)
        #expect(times.count == 2)
    }

    @Test func retriesServiceUnavailableOnce() async {
        let (data, times) = await run(codes: [503, 200], retryAfter: "0")
        #expect(data == Data([1, 2, 3]))
        #expect(times.count == 2)
    }

    @Test func cancellationStopsBackoffBeforeRetry() async throws {
        StubProtocol.codes = [503, 200]
        StubProtocol.retryAfter = "30"
        StubProtocol.times = []
        let file = tempDir().appendingPathComponent("cancelled.jpg")
        let session = stubSession()
        let task = Task {
            await ImageTransport.fetch(URL(string: "https://example.test/cancel")!, file: file,
                                       session: session, throttle: .init(interval: 0))
        }
        for _ in 0..<200 {
            if !StubProtocol.times.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(StubProtocol.times.count == 1)
        task.cancel()
        #expect(await task.value == nil)
        #expect(StubProtocol.times.count == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func retryDelayBounds() {
        #expect(ImageTransport.retryDelay(nil) == 30)
        #expect(ImageTransport.retryDelay("invalid") == 30)
        #expect(ImageTransport.retryDelay("-1") == 0)
        #expect(ImageTransport.retryDelay("200") == 120)
        #expect(ImageTransport.retryDelay("0.25") == 0.25)
    }

    @Test func retriesOnceAfterRetryAfter() async {
        let (data, times) = await run(codes: [429, 200], retryAfter: "0.3")
        #expect(data != nil)
        #expect(times.count == 2)
        #expect(times[1].timeIntervalSince(times[0]) >= 0.3)
    }

    @Test func givesUpAfterSecond429() async {
        let (data, times) = await run(codes: [429, 429, 200], retryAfter: "0")
        #expect(data == nil)
        #expect(times.count == 2)
    }

    @Test func doesNotRetryNotFound() async {
        let (data, times) = await run(codes: [404, 200])
        #expect(data == nil)
        #expect(times.count == 1)
    }

    @Test func spacesRequestsToOneHost() async {
        let throttle = ImageTransport.Throttle(interval: 0.1)
        let start = Date()
        await throttle.wait("h"); await throttle.wait("h"); await throttle.wait("h")
        #expect(Date().timeIntervalSince(start) >= 0.2)
        let other = Date()
        await throttle.wait("other")
        #expect(Date().timeIntervalSince(other) < 0.05)
    }
}
