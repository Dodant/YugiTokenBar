#if os(macOS)
import AppKit
import ImageIO

/// 카드(YGOPRODeck, 오버프레임은 Yugipedia·카드숍)·팩(Yugipedia/YGOPRODeck) 이미지 디스크 + 메모리 캐시. 번들에 넣지 않고 처음 볼 때 내려받는다.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    typealias Size = ImageSize
    typealias Throttle = ImageTransport.Throttle

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
    init(dir: URL = ImageSource.cacheDirectory, memoryLimit: Int = 150 << 20,
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
        let request = ImageSource.card(imageID: imageId, size: size, overframe: overframe)
        return await image(key: request.key, url: request.url, maxPixels: request.maxPixels, force: force)
    }

    /// 메모리 캐시에 이미 있으면 바로 (뷰가 첫 프레임부터 그리도록, 기다리는 동안 뒷면이 깜빡이지 않게)
    func cached(_ imageId: Int, size: Size, overframe: Bool = false, force: Bool = false) -> NSImage? {
        guard force || !workMode else { return nil }
        return memory.object(forKey: key(imageId, size: size, overframe: overframe) as NSString)
    }

    private func key(_ imageId: Int, size: Size, overframe: Bool) -> String {
        ImageSource.card(imageID: imageId, size: size, overframe: overframe).key
    }

    static let overframe = ImageSource.overframe

    /// 봉투 원본은 600px 이지만 가장 크게 그리는 상점 칸도 그 절반 남짓이라 줄여서 디코딩한다
    func packImage(_ pack: Pack) async -> NSImage? {
        guard let request = ImageSource.pack(pack) else { return nil }
        return await image(key: request.key, url: request.url, maxPixels: request.maxPixels)
    }

    /// packImage 의 메모리 캐시 조회 (cached 와 같은 목적)
    func cachedPack(_ pack: Pack) -> NSImage? {
        guard !workMode else { return nil }
        guard let request = ImageSource.pack(pack) else { return nil }
        return memory.object(forKey: request.key as NSString)
    }

    /// 카드 뒷면(tools/clean-card-back.py 산출물). .app 안에서는 Contents/Resources/card-back.jpg, `swift run`·테스트에서는 저장소의 Resources/card-back.jpg.
    static let cardBack = NSImage(contentsOf: Bundle.main.url(forResource: "card-back", withExtension: "jpg")
        ?? AppInfo.repoRoot.appendingPathComponent("Resources/card-back.jpg"))

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

    private nonisolated static func fetch(_ url: URL, file: URL) async -> Data? {
        await ImageTransport.fetch(url, file: file)
    }

    /// 공용 전송의 테스트용 호환 API.
    nonisolated static func fetch(_ url: URL, file: URL, session: URLSession, throttle: Throttle) async -> Data? {
        await ImageTransport.fetch(url, file: file, session: session, throttle: throttle)
    }
}
#endif
