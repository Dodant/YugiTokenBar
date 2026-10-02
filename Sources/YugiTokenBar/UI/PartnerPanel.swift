import AppKit
import SwiftUI

/// 바탕화면 파트너: 테두리 없는 투명 창. 모든 Space·전체 화면 앱 위에 떠 있고 포커스를 가져가지 않는다.
@MainActor final class PartnerPanel {
    private let panel: NSPanel
    private static let margin = 24.0

    init(frame: FrameBox, onClick: @escaping () -> Void, onHide: @escaping () -> Void, onMoved: @escaping (CGPoint) -> Void) {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        let host = PartnerHostingView(rootView: PartnerView(frame: frame))
        host.onClick = onClick
        host.onHide = onHide
        host.onMoved = onMoved
        panel.contentView = host
    }

    /// 크기를 맞추고 보인다. 이미 보이면 위치는 그대로 두고 크기만 바꾼다.
    func show(size: Double, origin: CGPoint?) {
        let windowSize = Self.windowSize(height: size)
        let start = panel.isVisible ? panel.frame.origin : Self.place(
            origin: origin, size: windowSize,
            screens: NSScreen.screens.map(\.visibleFrame),
            main: NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
        panel.setFrame(CGRect(origin: start, size: windowSize), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    /// 폭은 셀 비율(192:208), 높이는 `PartnerTuning.sizes`로 자른다.
    static func windowSize(height: Double) -> CGSize {
        let h = min(max(height, PartnerTuning.sizes.lowerBound), PartnerTuning.sizes.upperBound)
        return CGSize(width: h * PartnerSheet.cell.width / PartnerSheet.cell.height, height: h)
    }

    /// 저장 위치가 어느 화면에도 걸치지 않으면(모니터 분리 등) 주 화면 오른쪽 아래.
    static func place(origin: CGPoint?, size: CGSize, screens: [CGRect], main: CGRect) -> CGPoint {
        if let origin, screens.contains(where: { $0.intersects(CGRect(origin: origin, size: size)) }) { return origin }
        return CGPoint(x: main.maxX - size.width - margin, y: main.minY + margin)
    }

    /// 메뉴바 상태 아이템 버튼을 눌러 팝오버를 연다. MenuBarExtra 에 여는 API 가 없어서 상태바 창의 버튼을 찾는다.
    static func openPopover() {
        // ponytail: 비공개 클래스 이름(NSStatusBarWindow)에 기댄다. macOS 가 바꾸면 갸웃만 하고 팝오버는 안 열린다.
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = findButton(in: window.contentView) { button.performClick(nil); return }
        }
        AppLog.write("파트너: 메뉴바 버튼을 찾지 못함")
    }

    private static func findButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for sub in view.subviews { if let found = findButton(in: sub) { return found } }
        return nil
    }
}

/// 지금 프레임 하나를 창 크기에 맞춰 그린다.
struct PartnerView: View {
    @ObservedObject var frame: FrameBox

    var body: some View {
        if let image = frame.image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

/// 마우스: 4pt 넘게 끌면 창 이동, 아니면 클릭. 우클릭은 [숨기기] 메뉴.
final class PartnerHostingView: NSHostingView<PartnerView> {
    var onClick: () -> Void = {}
    var onHide: () -> Void = {}
    var onMoved: (CGPoint) -> Void = { _ in }
    private var downAt: CGPoint?
    private var startOrigin: CGPoint = .zero
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - downAt.x, dy = now.y - downAt.y
        if !dragging, dx * dx + dy * dy <= 16 { return }
        dragging = true
        window?.setFrameOrigin(CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        if dragging, let origin = window?.frame.origin { onMoved(origin) } else { onClick() }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(title: "숨기기", action: #selector(hidePartner), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func hidePartner() { onHide() }
}
