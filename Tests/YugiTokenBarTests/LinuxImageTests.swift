#if os(Linux)
import Adwaita
import CAdw
import Foundation
import Testing
@testable import YugiTokenBar

private actor LinuxControlledImageBytes {
    var continuations: [CheckedContinuation<Data?, Never>] = []
    var count = 0
    func fetch() async -> Data? {
        count += 1
        return await withCheckedContinuation { continuations.append($0) }
    }
    func finish(_ value: Data?) { continuations.removeFirst().resume(returning: value) }
}

@MainActor private final class LinuxTextureFinalizations { var count = 0 }

/// Run with scripts/test-linux-images.sh: real GTK objects and widget finalization require a display.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["YTB_GTK_IMAGE_TESTS"] == "1"))
@MainActor struct LinuxImageTests {
    private func wait(_ predicate: () async -> Bool) async {
        for _ in 0..<2000 {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for image worker")
    }
    @Test func nativeOwnershipAndLoader() async throws {
        gtk_init()
        let bytes = try Data(contentsOf: PlatformPaths.resource("card-back.jpg"))
        let cache = LinuxTextureCache(countLimit: 2)
        let key = LinuxTextureCache.Key(source: "fixture", pixels: 300)
        let grid = try #require(cache.decode(bytes, for: key))
        #expect(grid.width == 204 && grid.height == 300)
        #expect(grid.cost == 204 * 300 * 4)
        #expect(cache.decode(bytes, for: key)?.pointer == grid.pointer)
        let widget = gtk_picture_new()!
        g_object_ref_sink(UnsafeMutableRawPointer(widget))
        gtk_picture_set_paintable(OpaquePointer(widget), grid.pointer)
        let detail = try #require(cache.decode(bytes, for: .init(source: "fixture", pixels: 614)))
        #expect(detail.width == 419 && detail.height == 614)
        _ = cache.decode(bytes, for: .init(source: "third", pixels: 300))
        #expect(cache.texture(for: key) == nil && cache.count == 2)
        #expect(gtk_picture_get_paintable(OpaquePointer(widget)) == grid.pointer)
        #expect(gdk_texture_get_width(grid.pointer) == 204) // GTK keeps evicted image alive.
        g_object_unref(UnsafeMutableRawPointer(widget))
        #expect(cache.decode(Data([0, 1, 2]), for: .init(source: "invalid", pixels: 300)) == nil)

        let requests = LinuxControlledImageBytes()
        let loader = LinuxImageLoader(noImages: false, fetch: { _ in await requests.fetch() })
        let request = ImageRequest(key: "fixture", url: URL(string: "https://example.invalid/fixture")!, maxPixels: nil)
        var deliveries = 0
        var pointers: [OpaquePointer] = []
        let first = loader.subscribe(request, size: .grid) { texture in deliveries += 1; if let texture { pointers.append(texture.pointer) } }
        _ = loader.subscribe(request, size: .grid) { texture in deliveries += 1; if let texture { pointers.append(texture.pointer) } }
        await wait { await requests.count == 1 }
        loader.unsubscribe(first)
        await requests.finish(bytes)
        await wait { loader.drain(); return deliveries == 1 }
        #expect(pointers.count == 1)
        _ = loader.subscribe(request, size: .grid) { texture in #expect(texture?.pointer == pointers[0]); deliveries += 1 }
        #expect(deliveries == 2)

        let stale = LinuxControlledImageBytes()
        let staleLoader = LinuxImageLoader(noImages: false, fetch: { _ in await stale.fetch() })
        let canceled = staleLoader.subscribe(request, size: .grid) { _ in Issue.record("Canceled subscriber received stale bytes") }
        await wait { await stale.count == 1 }
        staleLoader.unsubscribe(canceled)
        #expect(staleLoader.inFlightCount == 0)
        var resumed = false
        _ = staleLoader.subscribe(request, size: .grid) { _ in resumed = true }
        await wait { await stale.count == 2 }
        staleLoader.stop(); staleLoader.resume()
        await wait { await stale.count == 3 }
        await stale.finish(bytes); await stale.finish(bytes)
        try? await Task.sleep(for: .milliseconds(20))
        staleLoader.drain(); #expect(!resumed)
        await stale.finish(bytes)
        await wait { staleLoader.drain(); return resumed }

        let queued = LinuxControlledImageBytes()
        let queuedLoader = LinuxImageLoader(noImages: false, fetch: { _ in await queued.fetch() })
        var queuedDelivered = false
        _ = queuedLoader.subscribe(request, size: .grid) { _ in queuedDelivered = true }
        await wait { await queued.count == 1 }
        await queued.finish(bytes)
        try? await Task.sleep(for: .milliseconds(20)) // Worker enqueues; GTK has not drained it.
        queuedLoader.stop(); queuedLoader.resume()
        await wait { await queued.count == 2 }
        queuedLoader.drain(); #expect(!queuedDelivered)
        await queued.finish(bytes)
        await wait { queuedLoader.drain(); return queuedDelivered }
        queuedLoader.stop()

        let noImagesRequests = LinuxControlledImageBytes()
        let noImages = LinuxImageLoader(noImages: true, fetch: { _ in await noImagesRequests.fetch() })
        var placeholder = false
        _ = noImages.subscribe(request, size: .grid) { placeholder = $0 != nil }
        #expect(placeholder && noImages.inFlightCount == 0)
        #expect(await noImagesRequests.count == 0)

        // Actual adapter: identity update reuses GTK paintable; destruction cancels its last subscriber.
        let nativeRequests = LinuxControlledImageBytes()
        let nativeLoader = LinuxImageLoader(noImages: false, fetch: { _ in await nativeRequests.fetch() })
        let picture = LinuxPicture(request: request, loader: nativeLoader)
        let storage = picture.makeStorage()
        let pointer = storage.opaquePointer!
        g_object_ref_sink(UnsafeMutableRawPointer(pointer))
        let placeholderPointer = gtk_picture_get_paintable(pointer)
        picture.updatePicture(storage)
        #expect(gtk_picture_get_paintable(pointer) == placeholderPointer)
        await wait { await nativeRequests.count == 1 }
        nativeLoader.stop(); nativeLoader.resume()
        await wait { await nativeRequests.count == 2 }
        await nativeRequests.finish(bytes)
        try? await Task.sleep(for: .milliseconds(10))
        nativeLoader.drain()
        #expect(gtk_picture_get_paintable(pointer) == placeholderPointer)
        await nativeRequests.finish(bytes)
        await wait { nativeLoader.drain(); return nativeLoader.inFlightCount == 0 }
        #expect(gtk_picture_get_paintable(pointer) != placeholderPointer)
        let nextRequest = ImageRequest(key: "another", url: request.url, maxPixels: nil)
        LinuxPicture(request: nextRequest, loader: nativeLoader).updatePicture(storage)
        await wait { await nativeRequests.count == 3 }
        g_object_unref(UnsafeMutableRawPointer(pointer))
        #expect(nativeLoader.inFlightCount == 0)
        await nativeRequests.finish(bytes)
        nativeLoader.drain() // No access to the finalized GTK pointer.
        let corruptRequest = ImageRequest(key: "task6-corrupt-" + UUID().uuidString, url: request.url, maxPixels: nil)
        let corruptFile = ImageSource.cacheDirectory.appendingPathComponent(corruptRequest.fileName)
        try FileManager.default.createDirectory(at: corruptFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0, 1, 2]).write(to: corruptFile)
        let corruptLoader = LinuxImageLoader(noImages: false)
        var corruptFinished = false
        _ = corruptLoader.subscribe(corruptRequest, size: .grid) { texture in
            #expect(texture == nil)
            #expect(!FileManager.default.fileExists(atPath: corruptFile.path))
            corruptFinished = true
        }
        await wait { corruptLoader.drain(); return corruptFinished }
        #expect(!FileManager.default.fileExists(atPath: corruptFile.path))
        // A new request after invalid disk removal can successfully receive fresh bytes.
        let retryLoader = LinuxImageLoader(noImages: false, fetch: { _ in bytes })
        var retried = false
        _ = retryLoader.subscribe(corruptRequest, size: .grid) { retried = $0 != nil }
        await wait { retryLoader.drain(); return retried }
        corruptLoader.stop(); retryLoader.stop()

        let reentrantCache = LinuxTextureCache(countLimit: 1)
        let reentrantLoader = LinuxImageLoader(cache: reentrantCache, noImages: false, fetch: { _ in bytes })
        var reentrantDelivered = 0
        for _ in 0..<2 {
            _ = reentrantLoader.subscribe(request, size: .grid) { texture in
                reentrantCache.removeAll()
                #expect(texture.map { gdk_texture_get_width($0.pointer) } == 204)
                reentrantDelivered += 1
            }
        }
        await wait { reentrantLoader.drain(); return reentrantDelivered == 2 }
        reentrantLoader.stop()
        let costCache = LinuxTextureCache()
        for index in 0..<40 { _ = costCache.decode(bytes, for: .init(source: "detail-\(index)", pixels: 614)) }
        #expect(costCache.count < 40 && costCache.cost <= 32 * 1024 * 1024)
        costCache.removeAll()

        // Repeated pack-sized populations release their widget references after navigation.
        let navigationCache = LinuxTextureCache()
        let finalizations = LinuxTextureFinalizations()
        for pass in 0..<4 {
            var widgets: [UnsafeMutablePointer<GtkWidget>] = []
            for index in 0..<154 {
                let texture = try #require(navigationCache.decode(bytes, for: .init(source: "pack-\(pass)-\(index)", pixels: 300)))
                g_object_weak_ref(UnsafeMutableRawPointer(texture.pointer).assumingMemoryBound(to: GObject.self), { context, _ in
                    guard let context else { return }
                    let counter = Unmanaged<LinuxTextureFinalizations>.fromOpaque(context).takeRetainedValue()
                    MainActor.assumeIsolated { counter.count += 1 }
                }, Unmanaged.passRetained(finalizations).toOpaque())
                let item = gtk_picture_new()!
                g_object_ref_sink(UnsafeMutableRawPointer(item))
                gtk_picture_set_paintable(OpaquePointer(item), texture.pointer)
                widgets.append(item)
            }
            #expect(navigationCache.count <= 96 && navigationCache.cost <= 32 * 1024 * 1024)
            for item in widgets { g_object_unref(UnsafeMutableRawPointer(item)) }
        }
        navigationCache.removeAll()
        #expect(finalizations.count == 4 * 154)

        // A visible native-adapter artifact, rather than a PNG decoded outside GTK.
        let visualLoader = LinuxImageLoader(noImages: false, fetch: { _ in bytes })
        let visual = LinuxPicture(request: request, size: .detail, loader: visualLoader).makeStorage()
        let window = UnsafeMutableRawPointer(gtk_window_new()!).assumingMemoryBound(to: GtkWindow.self)
        gtk_window_set_title(window, "Task6 native picture")
        gtk_window_set_default_size(window, 460, 660)
        gtk_window_set_child(window, UnsafeMutablePointer<GtkWidget>(visual.opaquePointer))
        gtk_window_present(window)
        await wait {
            visualLoader.drain()
            while g_main_context_iteration(nil, 0) != 0 { }
            return visualLoader.inFlightCount == 0
        }
        for _ in 0..<20 {
            while g_main_context_iteration(nil, 0) != 0 { }
            try? await Task.sleep(for: .milliseconds(10))
        }
        if let directory = ProcessInfo.processInfo.environment["YTB_GTK_IMAGE_ARTIFACT_DIR"] {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/bin/scrot")
            capture.arguments = ["-o", directory + "/native-picture.png"]
            try capture.run(); capture.waitUntilExit()
            #expect(capture.terminationStatus == 0)
        }
        gtk_window_destroy(window); visualLoader.stop()
        if ProcessInfo.processInfo.environment["YTB_GTK_IMAGE_ONLINE"] == "1" {
            let online = ImageSource.card(imageID: 46986414, size: .small)
            let file = URL(fileURLWithPath: ProcessInfo.processInfo.environment["YTB_STATE_DIR"]!).appendingPathComponent("online-image.jpg")
            try? FileManager.default.removeItem(at: file)
            let downloaded = try #require(await ImageTransport.fetch(online.url, file: file))
            let onlineCache = LinuxTextureCache()
            let decoded = try #require(onlineCache.decode(downloaded, for: .init(source: online.key, pixels: 300)))
            print("GTK_ONLINE_IMAGE_OK bytes=\(downloaded.count) size=\(decoded.width)x\(decoded.height) url=\(online.url)")
            onlineCache.removeAll()
        }
        loader.stop(); staleLoader.stop(); nativeLoader.stop(); noImages.stop(); cache.removeAll()
        print("GTK_IMAGE_PROBE_OK dimensions=204x300,419x614 cacheIdentity=shared evictionWidgetAlive=true cancelAll=true staleResume=true noImagesRequests=0 nativeDestroyed=true")
    }
}
#endif
