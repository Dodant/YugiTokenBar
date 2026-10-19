#if os(macOS)
import AppKit
import ImageIO

/// 카드(YGOPRODeck, 오버프레임은 Yugipedia·카드숍)·팩(Yugipedia/YGOPRODeck) 이미지 디스크 + 메모리 캐시. 번들에 넣지 않고 처음 볼 때 내려받는다.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    enum Size: String, Sendable {
        case small = "cards_small"
        case full = "cards"
    }

    let dir: URL
    /// 업무 모드 설정을 읽는다 (테스트가 따로 넣는다)
    private let defaults: UserDefaults
    private let memory = NSCache<NSString, NSImage>()
    /// 받는 중인 이미지와 그걸 기다리는 뷰 수. 기다리는 뷰가 다 사라지면(스크롤로 셀이 지나감) 받기를 취소한다.
    private var inFlight: [String: (task: Task<CGImage?, Never>, waiters: Int)] = [:]
    /// (원본 URL, 캐시 파일, maxPixels) → 이미지. 테스트가 네트워크 대신 넣는다.
    private let loader: @Sendable (URL, URL, Int?) async -> CGImage?

    /// memoryLimit: 메모리 캐시 상한(디코딩된 픽셀 바이트). 작은 카드 한 장이 약 400KB 라 150MB 면 수백 장,
    /// 도감 한 화면(수십 장)과 그 앞뒤 스크롤은 넉넉히 남고, 6천 장을 다 훑어도 그 이상 쌓이지 않는다.
    init(dir: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YugiTokenBar"), memoryLimit: Int = 150 << 20,
         loader: @escaping @Sendable (URL, URL, Int?) async -> CGImage? = ImageCache.load,
         defaults: UserDefaults = .standard) {
        self.dir = dir
        self.defaults = defaults
        self.loader = loader
        memory.totalCostLimit = memoryLimit
    }

    private var workMode: Bool { defaults.bool(forKey: AppModel.workModeKey) }

    /// force: 업무 모드여도 불러온다 (컬렉션 정보 패널의 고른 카드 한 장만)
    /// overframe: 오버프레임 판이 있으면 그 그림 (`Game.showsOverframe`, 같은 카드를 여러 장 가졌을 때)
    func image(_ imageId: Int, size: Size, overframe: Bool = false, force: Bool = false) async -> NSImage? {
        if overframe, let s = ImageSource.overframe[imageId] {
            // 원본이 600~1,160px 이라 YGOPRODeck 큰 이미지(세로 614px)만큼 줄여 두 크기에 함께 쓴다
            return await image(key: key(imageId, size: size, overframe: true), url: URL(string: s)!, maxPixels: 614, force: force)
        }
        return await image(key: key(imageId, size: size, overframe: false), url: Self.ygoprodeck("\(size.rawValue)/\(imageId)"), force: force)
    }

    /// 필드 마법의 일러스트 칸만 (설정 [필드 배경]). 따로 받지 않고 큰 카드 이미지에서 자른다.
    /// 마법 카드는 틀이 같아 비율로 자르고, 흐리게 깔아서 칸 가장자리가 섞이지 않게 조금 안쪽만 쓴다
    func fieldArt(_ imageId: Int) async -> NSImage? {
        guard let card = await image(imageId, size: .full)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = Double(card.width), h = Double(card.height)
        return card.cropping(to: CGRect(x: w * 0.13, y: h * 0.19, width: w * 0.74, height: w * 0.74)).map { NSImage(cgImage: $0, size: .zero) }
    }

    /// 메모리 캐시에 이미 있으면 바로 (뷰가 첫 프레임부터 그리도록, 기다리는 동안 뒷면이 깜빡이지 않게)
    func cached(_ imageId: Int, size: Size, overframe: Bool = false, force: Bool = false) -> NSImage? {
        guard force || !workMode else { return nil }
        return memory.object(forKey: key(imageId, size: size, overframe: overframe) as NSString)
    }

    private func key(_ imageId: Int, size: Size, overframe: Bool) -> String {
        overframe && ImageSource.overframe[imageId] != nil ? "overframe-\(imageId)" : "\(size.rawValue)-\(imageId)"
    }

    /// 봉투 원본은 600px 이지만 가장 크게 그리는 상점 칸도 그 절반 남짓이라 줄여서 디코딩한다
    func packImage(_ pack: Pack) async -> NSImage? {
        guard let s = pack.imageURL, let url = URL(string: s) else { return nil }
        return await image(key: "pack-\(url.lastPathComponent)", url: url, maxPixels: 480)
    }

    /// packImage 의 메모리 캐시 조회 (cached 와 같은 목적)
    func cachedPack(_ pack: Pack) -> NSImage? {
        guard !workMode else { return nil }
        guard let s = pack.imageURL, let url = URL(string: s) else { return nil }
        return memory.object(forKey: "pack-\(url.lastPathComponent)" as NSString)
    }

    /// 카드 뒷면(tools/clean-card-back.py 산출물). .app 안에서는 Contents/Resources/card-back.jpg, `swift run`·테스트에서는 저장소의 Resources/card-back.jpg.
    static let cardBack = NSImage(contentsOf: Bundle.main.url(forResource: "card-back", withExtension: "jpg")
        ?? AppInfo.repoRoot.appendingPathComponent("Resources/card-back.jpg"))

    private static func ygoprodeck(_ path: String) -> URL {
        URL(string: "https://images.ygoprodeck.com/images/\(path).jpg")!
    }

    /// key = 캐시 파일 이름(확장자 제외). 디코딩까지 백그라운드에서 끝내 스크롤 중 메인 스레드가 JPEG 를 풀지 않게 한다.
    private func image(key: String, url: URL, maxPixels: Int? = nil, force: Bool = false) async -> NSImage? {
        guard force || !workMode else { return nil }
        if let image = memory.object(forKey: key as NSString) { return image }
        let file = dir.appendingPathComponent("\(key).jpg")
        let loader = loader
        let task = inFlight[key]?.task ?? Task.detached { await loader(url, file, maxPixels) }
        inFlight[key] = (task, (inFlight[key]?.waiters ?? 0) + 1)
        let cg = await withTaskCancellationHandler { await task.value } onCancel: {
            Task { @MainActor in self.leave(key, task) }
        }
        if inFlight[key]?.task == task { inFlight[key] = nil }  // 그사이 새로 시작한 받기는 남긴다
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        memory.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height)
        return image
    }

    /// 기다리던 뷰 하나가 사라졌다. 남은 뷰가 없으면 받기를 취소한다.
    private func leave(_ key: String, _ task: Task<CGImage?, Never>) {
        guard let entry = inFlight[key], entry.task == task else { return }
        if entry.waiters > 1 { inFlight[key]?.waiters -= 1; return }
        task.cancel()
        inFlight[key] = nil
    }

    /// 받아서(또는 디스크에서 읽어서) 바로 디코딩한다. 깨진 캐시 파일은 지워 다음에 다시 받게 한다.
    nonisolated static func load(_ url: URL, file: URL, maxPixels: Int?) async -> CGImage? {
        guard let data = await fetch(url, file: file) else { return nil }
        guard let image = decode(data, maxPixels: maxPixels) else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return image
    }

    nonisolated static func decode(_ data: Data, maxPixels: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        if let maxPixels {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            options[kCGImageSourceCreateThumbnailWithTransform] = true
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixels
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    /// 호스트당 동시 연결을 줄인다(기본 6). 빠르게 스크롤해도 YGOPRODeck 에 한꺼번에 몰리지 않게.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: config)
    }()
    private nonisolated static let throttle = Throttle(interval: 0.08)

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

    private nonisolated static func fetch(_ url: URL, file: URL) async -> Data? {
        await fetch(url, file: file, session: session, throttle: throttle)
    }

    /// 디스크에 있으면 그대로, 없으면 받는다. 429·503 은 Retry-After(없으면 30초, 최대 120초)만큼 쉬고 한 번 더 시도한다.
    nonisolated static func fetch(_ url: URL, file: URL, session: URLSession, throttle: Throttle) async -> Data? {
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
            let seconds = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30
            await throttle.backoff(host, seconds: min(max(seconds, 0), 120))
        }
        return nil
    }
}
#endif
