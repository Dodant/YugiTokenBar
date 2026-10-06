import AppKit
import ImageIO

/// 카드(YGOPRODeck)·팩(Yugipedia/YGOPRODeck) 이미지 디스크 + 메모리 캐시. 번들에 넣지 않고 처음 볼 때 내려받는다.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    enum Size: String, Sendable {
        case small = "cards_small"
        case full = "cards"
    }

    let dir: URL
    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    init(dir: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YugiTokenBar")) {
        self.dir = dir
    }

    func image(_ imageId: Int, size: Size) async -> NSImage? {
        await image(key: "\(size.rawValue)-\(imageId)", url: Self.ygoprodeck("\(size.rawValue)/\(imageId)"))
    }

    /// 봉투 원본은 600px 이지만 가장 크게 그리는 상점 칸도 그 절반 남짓이라 줄여서 디코딩한다
    func packImage(_ pack: Pack) async -> NSImage? {
        guard let s = pack.imageURL, let url = URL(string: s) else { return nil }
        return await image(key: "pack-\(url.lastPathComponent)", url: url, maxPixels: 480)
    }

    func cardBack() async -> NSImage? {
        await image(key: "cards-back_high", url: Self.ygoprodeck("cards/back_high"))
    }

    private static func ygoprodeck(_ path: String) -> URL {
        URL(string: "https://images.ygoprodeck.com/images/\(path).jpg")!
    }

    /// key = 캐시 파일 이름(확장자 제외). 디코딩까지 백그라운드에서 끝내 스크롤 중 메인 스레드가 JPEG 를 풀지 않게 한다.
    private func image(key: String, url: URL, maxPixels: Int? = nil) async -> NSImage? {
        if let image = memory.object(forKey: key as NSString) { return image }
        let file = dir.appendingPathComponent("\(key).jpg")
        let task = inFlight[key] ?? Task.detached { await Self.load(url, file: file, maxPixels: maxPixels) }
        inFlight[key] = task
        let cg = await task.value
        inFlight[key] = nil
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    /// 받아서(또는 디스크에서 읽어서) 바로 디코딩한다. 깨진 캐시 파일은 지워 다음에 다시 받게 한다.
    private nonisolated static func load(_ url: URL, file: URL, maxPixels: Int?) async -> CGImage? {
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
        if let data = try? Data(contentsOf: file) { return data }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }
}
