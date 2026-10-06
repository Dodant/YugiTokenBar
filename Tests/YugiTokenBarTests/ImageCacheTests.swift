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

    @MainActor @Test func removesGarbageCacheFileAndRetriesNextCall() async throws {
        let dir = tempDir()
        let cacheFile = dir.appendingPathComponent("cards_small-456.jpg")
        try "garbage data".data(using: .utf8)!.write(to: cacheFile)
        let cache = ImageCache(dir: dir)
        let image = await cache.image(456, size: .small)
        #expect(image == nil)
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
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
