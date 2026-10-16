import Foundation
import Testing
@testable import YugiTokenBar

#if os(Linux)
@Suite struct PlatformTests {
    /// 실행 파일이 .build 아래면 개발 실행(qa-state), 아니면 설치 실행
    @Test func linuxInstalledRunIsOutsideBuildDirs() {
        #expect(AppEnv.isInstalledRun(executablePath: "/app/bin/YugiTokenBar"))
        #expect(!AppEnv.isInstalledRun(executablePath: "/work/.build/debug/YugiTokenBar"))
        #expect(!AppEnv.isInstalledRun(executablePath: "/work/.build-linux/debug/YugiTokenBarPackageTests.xctest"))
    }

    @Test func cursorRootsUseConfigDirOnLinux() {
        let home = URL(fileURLWithPath: "/home/u")
        #expect(LocalAdditionalUsageReader.cursorRoots(home: home).map(\.path)
                == ["/home/u/.config/Cursor/User/globalStorage", "/home/u/.config/Cursor Nightly/User/globalStorage"])
    }

    @Test func liveCursorDashboardIsDisabledOnLinux() {
        #expect(TodayUsageReader.defaultLiveCursor == nil)
    }
}
#endif
