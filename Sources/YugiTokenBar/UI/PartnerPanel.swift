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
        panel.hidesOnDeactivate = false  // 기본 true: 앱이 비활성화되면 사라짐
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        let host = PartnerHostingView(rootView: PartnerView(frame: frame))
        host.onClick = onClick
        host.onHide = onHide
        host.onMoved = onMoved
        panel.contentView = host
    }

    /// 크기를 맞추고 보인다. 이미 보이면 지금 위치에서 크기만 바꾼다(키워서 가운데가 화면 밖이 되면 오른쪽 아래로).
    func show(size: Double, origin: CGPoint?) {
        let windowSize = Self.windowSize(height: size)
        let start = Self.place(
            origin: panel.isVisible ? panel.frame.origin : origin, size: windowSize,
            screens: NSScreen.screens.map(\.visibleFrame),
            main: NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
        panel.setFrame(CGRect(origin: start, size: windowSize), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    /// 폭은 셀 비율(192:208), 높이는 `PartnerTuning.sizes`로 자른다.
    static func windowSize(height: Double) -> CGSize {
        let h = min(max(height, PartnerTuning.sizes.lowerBound), PartnerTuning.sizes.upperBound)
        return CGSize(width: h * PartnerSheet.cell.width / PartnerSheet.cell.height, height: h)
    }

    /// 창 가운데가 어느 화면에도 없으면(모니터 분리, 화면 밖으로 끌어냄 등) 주 화면 오른쪽 아래.
    static func place(origin: CGPoint?, size: CGSize, screens: [CGRect], main: CGRect) -> CGPoint {
        if let origin, screens.contains(where: { $0.contains(CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)) }) { return origin }
        return CGPoint(x: main.maxX - size.width - margin, y: main.minY + margin)
    }
}

/// 지금 프레임 하나를 창 크기에 맞춰 그린다.
struct PartnerView: View {
    let frame: FrameBox

    var body: some View {
        if let image = frame.image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

/// 마우스: 4pt 넘게 끌면 창 이동, 아니면 클릭(갸웃). Ctrl 클릭·우클릭은 [숨기기] 메뉴.
final class PartnerHostingView: NSHostingView<PartnerView> {
    var onClick: () -> Void = {}
    var onHide: () -> Void = {}
    var onMoved: (CGPoint) -> Void = { _ in }
    private var downAt: CGPoint?
    private var startOrigin: CGPoint = .zero
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { downAt = nil; rightMouseDown(with: event); return }
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
        guard downAt != nil else { return }
        defer { downAt = nil }
        if dragging, let origin = window?.frame.origin { onMoved(origin) } else { onClick() }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false  // NSHostingView 의 검증이 사용자 액션을 꺼 버린다
        let item = NSMenuItem(title: String(localized: "숨기기"), action: #selector(hidePartner), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func hidePartner() { onHide() }
}
