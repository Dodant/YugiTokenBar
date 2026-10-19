#if os(Linux)
import CAdw
import Foundation

/// GTK-loop-only owners. Visible pictures retain their own paintable reference outside this budget.
@MainActor final class LinuxTextureCache {
    struct Key: Hashable { let source: String; let pixels: Int }
    struct Texture { let pointer: OpaquePointer; let width: Int; let height: Int; var cost: Int { width * height * 4 } }
    private struct Entry { let texture: Texture; var stamp: UInt64 }
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var cost = 0
    var count: Int { entries.count }
    let countLimit: Int
    let byteLimit: Int
    init(countLimit: Int = 96, byteLimit: Int = 32 * 1024 * 1024) {
        precondition(countLimit > 0 && byteLimit >= 614 * 614 * 4)
        self.countLimit = countLimit; self.byteLimit = byteLimit
    }
    func texture(for key: Key) -> Texture? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1; entry.stamp = clock; entries[key] = entry
        return entry.texture
    }
    /// Returns a borrowed cache-owned texture. The consumer must attach it before the next insertion.
    func decode(_ data: Data, for key: Key) -> Texture? {
        if let existing = texture(for: key) { return existing }
        guard (1...614).contains(key.pixels), let loader = gdk_pixbuf_loader_new() else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(loader)) }
        let written = data.withUnsafeBytes { bytes in
            gdk_pixbuf_loader_write(loader, bytes.bindMemory(to: UInt8.self).baseAddress, UInt(data.count), nil)
        }
        let closed = gdk_pixbuf_loader_close(loader, nil)
        guard written != 0, closed != 0,
              let original = gdk_pixbuf_loader_get_pixbuf(loader) else { return nil }
        let width = Int(gdk_pixbuf_get_width(original)), height = Int(gdk_pixbuf_get_height(original))
        guard width > 0, height > 0 else { return nil }
        let ratio = min(1, Double(key.pixels) / Double(max(width, height)))
        let w = max(1, Int(Double(width) * ratio)), h = max(1, Int(Double(height) * ratio))
        guard let scaled = gdk_pixbuf_scale_simple(original, Int32(w), Int32(h), GDK_INTERP_BILINEAR) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(scaled)) }
        guard let pointer = gdk_texture_new_for_pixbuf(scaled) else { return nil }
        let texture = Texture(pointer: pointer, width: w, height: h)
        // Evict before insertion, so the newly returned borrowed reference remains valid.
        while !entries.isEmpty && (entries.count >= countLimit || cost + texture.cost > byteLimit) { evictOldest() }
        clock &+= 1; entries[key] = Entry(texture: texture, stamp: clock); cost += texture.cost
        return texture
    }
    /// Protect a borrowed texture across callbacks that may reenter or clear this cache.
    static func retaining<T>(_ texture: Texture?, _ body: () -> T) -> T {
        if let texture { _ = g_object_ref(UnsafeMutableRawPointer(texture.pointer)) }
        defer { if let texture { g_object_unref(UnsafeMutableRawPointer(texture.pointer)) } }
        return body()
    }
    private func evictOldest() {
        guard let key = entries.min(by: { $0.value.stamp < $1.value.stamp })?.key,
              let entry = entries.removeValue(forKey: key) else { return }
        cost -= entry.texture.cost
        g_object_unref(UnsafeMutableRawPointer(entry.texture.pointer))
    }
    func removeAll() { while !entries.isEmpty { evictOldest() } }
    isolated deinit { removeAll() }
}
#endif
