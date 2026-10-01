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
}
