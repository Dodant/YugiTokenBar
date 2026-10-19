#if os(Linux)
import Adwaita
import CAdw
import Foundation
import Testing
@testable import YugiTokenBar

/// Shared helpers for the native GTK suites (YTB_GTK_UI_TESTS=1, scripts/test-linux-ui.sh).
@MainActor enum LinuxGTK {
    typealias Widget = UnsafeMutablePointer<GtkWidget>

    static func find(_ name: String, in widget: Widget) -> Widget? {
        if gtk_widget_get_mapped(widget) != 0, String(cString: gtk_widget_get_name(widget)) == name { return widget }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let result = find(name, in: current) { return result }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }
    /// Runs the main loop; a model's queued background results are drained on every turn.
    static func pump(_ model: LinuxModel? = nil) async {
        for _ in 0..<30 {
            while g_main_context_iteration(nil, 0) != 0 {}
            model?.drainEvents()
            LinuxImageLoader.shared.drain()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    static func screenshot(_ name: String) async {
        guard let path = ProcessInfo.processInfo.environment["YTB_GTK_UI_ARTIFACT_DIR"] else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scrot")
        process.arguments = ["-o", "\(path)/\(name).png"]
        do { try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0) }
        catch { Issue.record("Screenshot failed: \(error)") }
    }
}
#endif
