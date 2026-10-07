import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct LocalizationTests {
    /// 시스템 언어 → 이번 실행 언어. 지원하지 않는 언어는 영어
    @Test func unsupportedLanguageFallsBackToEnglish() {
        #expect(AppLanguage.resolve(["ko-KR"]) == "ko")
        #expect(AppLanguage.resolve(["ja-JP", "en"]) == "ja")
        #expect(AppLanguage.resolve(["en-GB"]) == "en")
        #expect(AppLanguage.resolve(["fr-FR"]) == "en")
        #expect(AppLanguage.resolve(["de", "ko"]) == "ko")  // 목록 안에서 처음 지원하는 언어
        #expect(AppLanguage.supported.allSatisfy { CardDB.fileName($0).hasPrefix("cards_") })
    }

    /// 고른 언어는 앱 도메인 AppleLanguages 에, 시스템 따르기는 키를 지운다
    @Test func storingLanguageWritesAppleLanguages() throws {
        let suite = "ytb-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AppLanguage.stored(in: defaults) == .system)
        AppLanguage.store(.ja, in: defaults)
        #expect(AppLanguage.stored(in: defaults) == .ja)
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["ja"])
        AppLanguage.store(.system, in: defaults)
        #expect(AppLanguage.stored(in: defaults) == .system)
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
    }

    /// 앱이 지원하는 언어마다 lproj 가 있다 (ko 가 없으면 한국어 시스템에서 en 으로 떨어진다)
    @Test func everySupportedLanguageHasAnLproj() {
        for lang in AppLanguage.supported {
            let url = AppInfo.repoRoot.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
            #expect(FileManager.default.fileExists(atPath: url.path), "\(lang).lproj 없음")
        }
    }
}
