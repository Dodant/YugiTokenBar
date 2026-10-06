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
