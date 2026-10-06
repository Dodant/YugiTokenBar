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
    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    /// memoryLimit: 메모리 캐시 상한(디코딩된 픽셀 바이트). 작은 카드 한 장이 약 400KB 라 150MB 면 수백 장,
    /// 도감 한 화면(수십 장)과 그 앞뒤 스크롤은 넉넉히 남고, 6천 장을 다 훑어도 그 이상 쌓이지 않는다.
    init(dir: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YugiTokenBar"), memoryLimit: Int = 150 << 20) {
        self.dir = dir
        memory.totalCostLimit = memoryLimit
    }

    func image(_ imageId: Int, size: Size) async -> NSImage? {
        if let s = Self.overframe[imageId] {
            // 원본이 600~1,160px 이라 YGOPRODeck 큰 이미지(세로 614px)만큼 줄여 두 크기에 함께 쓴다
            return await image(key: "overframe-\(imageId)", url: URL(string: s)!, maxPixels: 614)
        }
        return await image(key: "\(size.rawValue)-\(imageId)", url: Self.ygoprodeck("\(size.rawValue)/\(imageId)"))
    }

    /// passcode → 공식 오버프레임(Yugipedia "Extended art") 이미지. 워터마크(SAMPLE) 없는 실물 스캔·공식 이미지만.
    /// 100팩에 든 오버프레임 21종 전부. 카드별 출처는 docs/sources.md.
    /// ponytail: 손으로 고른 표. 새 오버프레임이 나오면 Card Gallery 의 `-EA`·LOSP 등 파일을 확인해 한 줄 추가한다(docs/sources.md 표도).
    static let overframe: [Int: String] = [
        35952884: "https://ms.yugipedia.com//e/e7/ShootingQuasarDragon-RA05-EN-UR-1E-EA.png",
        6218704: "https://ms.yugipedia.com//a/ae/OddEyesArcrayDragon-RA05-EN-UR-1E-EA.png",
        21637210: "https://ms.yugipedia.com//7/7c/FirewallDragonSingularity-RA05-EN-UR-1E-EA.png",
        35405755: "https://ms.yugipedia.com//c/c1/KurikaraDivincarnate-RA05-EN-UR-1E-EA.png",
        48130397: "https://ms.yugipedia.com//f/f6/SuperPolymerization-RA05-EN-UR-1E-EA.png",
        97045737: "https://ms.yugipedia.com//7/7e/DominusPurge-RA05-EN-UR-1E-EA.png",
        31801517: "https://ms.yugipedia.com//7/77/Number62GalaxyEyesPrimePhotonDragon-LOSP-JP-PScR.png",
        13331639: "https://ms.yugipedia.com//f/f7/SupremeKingZARC-LOSP-JP-PScR.png",
        22850702: "https://ms.yugipedia.com//f/f2/ChaosAngel-LOSP-JP-PScR.png",
        98127546: "https://ms.yugipedia.com//c/c1/UnderworldGoddessoftheClosedWorld-LOSP-JP-PScR.png",
        25592142: "https://ms.yugipedia.com//5/56/AstellaroftheWhiteForest-CF02-JP-OP.png",
        61980241: "https://ms.yugipedia.com//8/81/ElzetteoftheWhiteForest-CF02-JP-OP.png",
        // Yugipedia 에 워터마크 판뿐인 카드는 일본 카드숍(카드러시·블루래빗) 상품 스캔
        82344137: "https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_1.jpg",
        44001993: "https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_2.jpg",
        70405001: "https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_3.jpg",
        7894706: "https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_4.jpg",
        40366667: "https://www.cardrush.jp/data/cardrush/product/LOSP2_10.jpg",
        70781052: "https://www.cardrush.jp/data/cardrush/product/S__10100739.jpg",
        53183600: "https://www.rabbit-blue.com/data/nereid/product/RV01/008s.jpg",
        29479265: "https://www.rabbit-blue.com/data/nereid/product/RV01/063s.jpg",
        24269961: "https://www.rabbit-blue.com/data/nereid/product/RV01/064s.jpg",
    ]

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
        memory.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height)
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
