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

    private static func strings(_ lang: String) throws -> [String: String] {
        let url = AppInfo.repoRoot.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(lang) strings 를 읽지 못함")
    }

    private static func specifiers(_ s: String) -> [String] {
        s.matches(of: /%(?:\d+\$)?(lld|ld|d|@|lf|f)/).map { String($0.output.1) }.sorted()
    }

    /// en·ja 키가 같고, 값에 한글이 없고, 키마다 형식 지정자가 같다 (다르면 번역이 조용히 안 나오거나 죽는다)
    @Test func formatSpecifiersMatch() throws {
        let en = try Self.strings("en"), ja = try Self.strings("ja")
        #expect(Set(en.keys) == Set(ja.keys))
        for (table, name) in [(en, "en"), (ja, "ja")] {
            for (key, value) in table {
                #expect(Self.specifiers(key) == Self.specifiers(value), "\(name): \(key) → \(value)")
                #expect(value.range(of: "[가-힣]", options: .regularExpression) == nil, "\(name) 번역 안 됨: \(key)")
            }
        }
        #expect(en.count >= 3)
    }
}
