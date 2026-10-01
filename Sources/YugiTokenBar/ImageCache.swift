import AppKit

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
    private var inFlight: [String: Task<Data?, Never>] = [:]

    init(dir: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YugiTokenBar")) {
        self.dir = dir
    }

    func image(_ imageId: Int, size: Size) async -> NSImage? {
        await image(key: "\(size.rawValue)-\(imageId)", url: Self.ygoprodeck("\(size.rawValue)/\(imageId)"))
    }

    func packImage(_ pack: Pack) async -> NSImage? {
        guard let s = pack.imageURL, let url = URL(string: s) else { return nil }
        return await image(key: "pack-\(url.lastPathComponent)", url: url)
    }

    func cardBack() async -> NSImage? {
        await image(key: "cards-back_high", url: Self.ygoprodeck("cards/back_high"))
    }

    private static func ygoprodeck(_ path: String) -> URL {
        URL(string: "https://images.ygoprodeck.com/images/\(path).jpg")!
    }

    /// key = 캐시 파일 이름(확장자 제외)
    private func image(key: String, url: URL) async -> NSImage? {
        if let image = memory.object(forKey: key as NSString) { return image }
        let file = dir.appendingPathComponent("\(key).jpg")
        let task = inFlight[key] ?? Task.detached { [dir] in await Self.fetch(url, file: dir.appendingPathComponent("\(key).jpg")) }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil
        guard let data else { return nil }
        guard let image = NSImage(data: data) else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        memory.setObject(image, forKey: key as NSString)
        return image
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
