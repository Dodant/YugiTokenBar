#if os(macOS)
import AppKit
import Sparkle

/// 메뉴바 앱에서 예약 확인 알림도 앞으로 가져오는 Sparkle 사용자 드라이버 델리게이트
@MainActor final class UpdaterUserDriverDelegate: NSObject, @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate()
    }
}

/// Sparkle 앱 내 업데이트. 공개 키가 있는 .app 에서만 만든다(없으면 nil → 설정은 GitHub 버전 비교)
@MainActor enum Updater {
    /// 컨트롤러는 델리게이트를 약하게만 잡으므로 앱 수명 동안 여기서 쥔다
    private static let userDriverDelegate = UpdaterUserDriverDelegate()

    static let controller: SPUStandardUpdaterController? = AppInfo.sparkleEnabled()
        ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: userDriverDelegate)
        : nil

    /// 메뉴바 앱이라 앞으로 가져온 뒤 Sparkle 창을 띄운다
    static func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}
#endif
