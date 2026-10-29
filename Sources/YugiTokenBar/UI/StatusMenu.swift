#if os(macOS)
import SwiftUI

/// 메뉴바 아이콘 오른쪽 클릭(⌃클릭) 메뉴. MenuBarExtra 는 오른쪽 클릭을 받지 않아 앱 이벤트를 먼저 가로챈다
@MainActor enum StatusMenu {
    /// 창을 여는 SwiftUI 동작. 메뉴바 라벨이 나타날 때 넘겨준다
    static var openWindow: OpenWindowAction?
    private static var monitor: Any?

    static func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  // ponytail: 상태 항목 창을 비공개 클래스 이름으로 알아본다. macOS 가 이름을 바꾸면 메뉴만 안 뜨고 왼쪽 클릭은 그대로
                  let window = event.window, window.className == "NSStatusBarWindow",
                  let view = window.contentView else { return event }
            menu(model, button: view as? NSButton).popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY - 4), in: view)
            return nil
        }
    }

    /// 창을 열고 앞으로 꺼낸다 (팝오버와 같이 쓴다)
    static func show(_ id: String, _ openWindow: OpenWindowAction?) {
        openWindow?(id: id)
        // activate 는 다른 앱 뒤에 창을 둘 수 있어서 창을 직접 앞으로 꺼낸다
        NSApp.activate()
        // 컬렉션은 navigationTitle 로 제목이 팩 이름으로 바뀌므로 제목 대신 Scene id(NSWindow.identifier)로 찾는다
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(id) == true }) else { return }
            window.orderFrontRegardless()
            window.makeKey()
        }
    }

    private static func menu(_ model: AppModel, button: NSButton?) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(Item(String(localized: "컬렉션")) { show("dex", openWindow) })
        menu.addItem(Item(String(localized: "사용량")) {
            model.screen = .usage
            // 팝오버가 닫혀 있으면 아이콘을 왼쪽 클릭한 것처럼 연다 (열려 있으면 화면만 바뀐다)
            if !NSApp.windows.contains(where: { $0.isVisible && $0.className.contains("MenuBarExtra") }) { button?.performClick(nil) }
        })
        let info = NSMenuItem(title: String(localized: "메뉴바 표시"), action: nil, keyEquivalent: "")
        info.submenu = NSMenu()
        for choice in AppModel.MenuBarInfo.allCases {
            let item = Item(choice.title) { model.menuBarInfo = choice }
            item.state = model.menuBarInfo == choice ? .on : .off
            info.submenu?.addItem(item)
        }
        menu.addItem(info)
        menu.addItem(.separator())
        let work = Item(String(localized: "업무 모드")) { model.workMode.toggle() }
        work.state = model.workMode ? .on : .off
        menu.addItem(work)
        menu.addItem(.separator())
        menu.addItem(Item(String(localized: "패치노트")) { show("changelog", openWindow) })
        // Sparkle 이 없는 빌드(swift run 등)는 Release 페이지를 연다
        menu.addItem(Item(String(localized: "업데이트 확인")) {
            if Updater.controller != nil { Updater.checkForUpdates() } else { NSWorkspace.shared.open(AppInfo.releasesURL) }
        })
        menu.addItem(.separator())
        menu.addItem(Item(String(localized: "종료")) { NSApp.terminate(nil) })
        return menu
    }

    /// 누르면 클로저를 부르는 메뉴 항목
    private final class Item: NSMenuItem {
        private let handler: () -> Void
        init(_ title: String, _ handler: @escaping () -> Void) {
            self.handler = handler
            super.init(title: title, action: #selector(run), keyEquivalent: "")
            target = self
        }
        required init(coder: NSCoder) { fatalError() }
        @objc private func run() { handler() }
    }
}
#endif
