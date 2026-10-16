import Foundation

#if !canImport(ObjectiveC)
/// Darwin 의 autoreleasepool 자리. Linux 에는 오토릴리스 풀이 없어 본문만 실행한다 (Usage/ 12곳·TodayUsageReader 1곳)
@discardableResult
func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result { try body() }
#endif

#if os(Linux)
/// OAuthLimitsProvider.swift 는 macOS 전용이지만 ClaudeAccountRoots 의 로컬 로그인 판독에도 이 값 타입을 쓴다.
struct AccountIdentity: Equatable, Sendable {
    let email: String
    let organizationName: String?
}

extension NSString {
    /// Foundation 의 macOS 전용 경로 축약 API 와 같은 결과를 낸다.
    var abbreviatingWithTildeInPath: String {
        let path = self as String
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
#endif
