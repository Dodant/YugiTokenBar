#if os(Linux)
import CAdw
import Foundation

enum LinuxSaveTransfer {
    /// Reads one byte past the limit so an oversized file is rejected without loading all of it.
    static func readEnvelope(at url: URL) throws -> SaveEnvelope {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: SaveEnvelope.maxFileBytes + 1) ?? Data()
        return try SaveEnvelope.decode(data)
    }

    /// GIO replaces the destination itself, which also works for document-portal paths that forbid sibling temp files.
    static func write(_ data: Data, to url: URL) throws {
        let file = g_file_new_for_path(url.path)
        defer { g_object_unref(UnsafeMutableRawPointer(file)) }
        let replaceDestination = GFileCreateFlags(rawValue: 1 << 1) // G_FILE_CREATE_REPLACE_DESTINATION, spelled numerically because Swift does not import the constant
        var error: UnsafeMutablePointer<GError>?
        let ok = data.withUnsafeBytes { bytes in
            g_file_replace_contents(file, bytes.baseAddress?.assumingMemoryBound(to: CChar.self), gsize(bytes.count),
                                    nil, 0, replaceDestination, nil, nil, &error)
        }
        guard ok != 0 else {
            let message = error.map { String(cString: $0.pointee.message) } ?? "write failed"
            g_clear_error(&error)
            throw NSError(domain: "YugiTokenBar.SaveTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
#endif
