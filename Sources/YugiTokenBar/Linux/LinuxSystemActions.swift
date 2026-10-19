#if os(Linux)
import CAdw
import Foundation

/// Opens URLs and folders through the desktop's default handler (GIO, portal-aware inside Flatpak). Never shells out.
enum LinuxSystemActions {
    /// Returns nil on success, otherwise the GIO error message.
    @discardableResult static func open(_ url: URL) -> String? {
        var error: UnsafeMutablePointer<GError>?
        let ok = g_app_info_launch_default_for_uri(url.absoluteString, nil, &error)
        guard ok == 0 else { return nil }
        let message = error.map { String(cString: $0.pointee.message) } ?? "No handler for \(url.absoluteString)"
        g_clear_error(&error)
        return message
    }
}
#endif
