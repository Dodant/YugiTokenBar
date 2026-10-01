import AppKit

/// YGOPRODeck 카드 이미지 디스크 + 메모리 캐시. 번들에 넣지 않고 처음 볼 때 내려받는다.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    enum Size: String, Sendable {
        case small = "cards_small"
        case full = "cards"
    }

    let dir: URL
    private var memory: [String: NSImage] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]

    init(dir: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YugiTokenBar")) {
        self.dir = dir
    }

    func image(_ imageId: Int, size: Size) async -> NSImage? {
        let key = "\(size.rawValue)-\(imageId)"
        if let image = memory[key] { return image }
        let task = inFlight[key] ?? Task.detached { [dir] in await Self.fetch(imageId, size: size, file: dir.appendingPathComponent("\(key).jpg")) }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil
        guard let data, let image = NSImage(data: data) else { return nil }
        memory[key] = image
        return image
    }

    private nonisolated static func fetch(_ imageId: Int, size: Size, file: URL) async -> Data? {
        if let data = try? Data(contentsOf: file) { return data }
        let url = URL(string: "https://images.ygoprodeck.com/images/\(size.rawValue)/\(imageId).jpg")!
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }
}
