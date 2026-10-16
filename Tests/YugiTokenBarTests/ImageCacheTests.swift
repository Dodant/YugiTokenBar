#if os(macOS)
import AppKit
import Testing
@testable import YugiTokenBar

@Suite struct ImageCacheTests {
    @MainActor @Test func servesDiskCacheWithoutNetwork() async throws {
        let dir = tempDir()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("cards_small-123.jpg"))
        let cache = ImageCache(dir: dir)
        let image = await cache.image(123, size: .small)
        #expect(image != nil)
    }

    /// 오버프레임 카드는 크기와 상관없이 overframe-<passcode> 한 파일을 쓴다
    @MainActor @Test func overframeCardsUseTheirOwnFile() async throws {
        let dir = tempDir()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let id = try #require(ImageCache.overframe.keys.first)
        try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("overframe-\(id).jpg"))
        let cache = ImageCache(dir: dir)
        #expect(await cache.image(id, size: .small) != nil)
        #expect(await cache.image(id, size: .full) != nil)
    }

    /// cached 는 메모리에 올라온 것만 바로 준다 (비동기 image 와 같은 키: 크기별, 오버프레임은 크기 무관)
    @MainActor @Test func cachedReturnsOnlyWhatIsInMemory() async throws {
        let dir = tempDir()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let over = try #require(ImageCache.overframe.keys.first)
        for name in ["cards_small-7", "overframe-\(over)"] {
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("\(name).jpg"))
        }
        let cache = ImageCache(dir: dir)
        #expect(cache.cached(7, size: .small) == nil)  // 디스크에만 있으면 없다
        let small = try #require(await cache.image(7, size: .small))
        #expect(cache.cached(7, size: .small) === small)
        #expect(cache.cached(7, size: .full) == nil)
        let o = try #require(await cache.image(over, size: .small))
        #expect(cache.cached(over, size: .full) === o)
    }

    /// cachedPack 은 packImage 로 메모리에 올라온 팩 이미지만 바로 준다
    @MainActor @Test func cachedPackReturnsOnlyWhatIsInMemory() async throws {
        let cache = ImageCache(dir: tempDir()) { _, _, _ in onePixel() }
        let pack = Pack(pid: "p1", name: "p", date: "", cards: [], imageURL: "https://example.com/a/pack1.jpg")
        #expect(cache.cachedPack(pack) == nil)
        let loaded = try #require(await cache.packImage(pack))
        #expect(cache.cachedPack(pack) === loaded)
    }

    @MainActor @Test func removesGarbageCacheFileAndRetriesNextCall() async throws {
        let dir = tempDir()
        let cacheFile = dir.appendingPathComponent("cards_small-456.jpg")
        try "garbage data".data(using: .utf8)!.write(to: cacheFile)
        let cache = ImageCache(dir: dir)
        let image = await cache.image(456, size: .small)
        #expect(image == nil)
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
    }

    /// 메모리 캐시는 픽셀 바이트 상한을 넘으면 오래된 이미지를 내보내고, 다음 요청은 디스크에서 다시 읽는다
    @MainActor @Test func memoryCacheEvictsOverCostLimit() async throws {
        let dir = tempDir()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for id in [1, 2] { try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("cards_small-\(id).jpg")) }

        let roomy = ImageCache(dir: dir)
        let a = try #require(await roomy.image(1, size: .small))
        _ = await roomy.image(2, size: .small)
        #expect(await roomy.image(1, size: .small) === a)  // 메모리에서

        let tight = ImageCache(dir: dir, memoryLimit: 20)  // 2×2 한 장(16바이트 남짓)만 들어간다
        let b = try #require(await tight.image(1, size: .small))
        _ = await tight.image(2, size: .small)
        let again = try #require(await tight.image(1, size: .small))
        #expect(again !== b)  // 밀려나서 디스크에서 다시
    }

    /// 기다리던 셀이 하나라도 남아 있으면 받기를 이어 가고, 다 사라지면(스크롤로 지나감) 받기를 취소한다
    @MainActor @Test func keepsDownloadWhileSomeoneWaits() async throws {
        let cache = ImageCache(dir: tempDir()) { _, _, _ in
            try? await Task.sleep(for: .milliseconds(300))
            return Task.isCancelled ? nil : onePixel()
        }
        let gone = Task { await cache.image(1, size: .small) }
        let staying = Task { await cache.image(1, size: .small) }
        try await Task.sleep(for: .milliseconds(50))
        gone.cancel()
        #expect(await staying.value != nil)
    }

    @MainActor @Test func cancelsDownloadWhenEveryoneLeaves() async throws {
        let seen = CancelFlag()
        let cache = ImageCache(dir: tempDir()) { _, _, _ in
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { await seen.set() }
            return nil
        }
        let gone = Task { await cache.image(1, size: .small) }
        try await Task.sleep(for: .milliseconds(50))
        gone.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await seen.value)
    }

    /// 업무 모드가 켜져 있으면 로더(디스크·네트워크·디코드)를 부르지 않고 nil, 끄면 다시 불러온다. force 면 켜져 있어도 불러온다
    @MainActor @Test func workModeSkipsLoading() async {
        let suite = "ytb-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        d.set(true, forKey: AppModel.workModeKey)
        let calls = CallCount()
        let cache = ImageCache(dir: tempDir(), loader: { _, _, _ in await calls.bump(); return onePixel() }, defaults: d)
        #expect(await cache.image(1, size: .small) == nil)
        #expect(await calls.value == 0)
        #expect(cache.cached(1, size: .small) == nil)
        #expect(cache.cachedPack(Pack(pid: "p1", name: "p", date: "", cards: [], imageURL: "https://example.com/a/pack1.jpg")) == nil)
        #expect(await cache.image(1, size: .small, force: true) != nil)
        #expect(await calls.value == 1)
        #expect(cache.cached(1, size: .small, force: true) != nil)
        #expect(cache.cached(1, size: .small) == nil)
        d.set(false, forKey: AppModel.workModeKey)
        #expect(await cache.image(1, size: .small) != nil)
        #expect(await calls.value == 1)
    }

    /// 팩 이미지는 긴 변이 maxPixels 를 넘지 않게 줄여서 디코딩한다
    @Test func decodeDownsamplesToMaxPixels() throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 600, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let small = try #require(ImageCache.decode(data, maxPixels: 120))
        #expect(max(small.width, small.height) == 120)
        #expect(ImageCache.decode(data, maxPixels: nil)?.height == 600)
    }
}

private actor CallCount {
    var value = 0
    func bump() { value += 1 }
}

private actor CancelFlag {
    var value = false
    func set() { value = true }
}

private func onePixel() -> CGImage? {
    CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
}

/// 미리 넣어 둔 상태 코드를 차례로 돌려주는 가짜 서버. 요청 시각을 기록한다.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var codes: [Int] = []
    nonisolated(unsafe) static var retryAfter: String?
    nonisolated(unsafe) static var times: [Date] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.times.append(Date())
        let code = Self.codes.isEmpty ? 200 : Self.codes.removeFirst()
        let headers = Self.retryAfter.map { ["Retry-After": $0] }
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
        let data = await ImageCache.fetch(URL(string: "https://example.test/a")!, file: file, session: stubSession(),
                                          throttle: ImageCache.Throttle(interval: interval))
        return (data, StubProtocol.times)
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
        let throttle = ImageCache.Throttle(interval: 0.1)
        let start = Date()
        await throttle.wait("h"); await throttle.wait("h"); await throttle.wait("h")
        #expect(Date().timeIntervalSince(start) >= 0.2)
        let other = Date()
        await throttle.wait("other")
        #expect(Date().timeIntervalSince(other) < 0.05)
    }
}
#endif
