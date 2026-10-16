import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct LocalizerTests {
    @Test func parsesEntriesWithEscapesAndSkipsComments() {
        let text = #"""
        /* SettingsView.swift:12 */
        "안녕 \"세계\"" = "Hello \"world\"";

        "줄\n바꿈" = "line\nbreak";
        "역슬래시 \\" = "backslash \\";
        malformed
        """#
        #expect(Localizer.parseStrings(text) == ["안녕 \"세계\"": "Hello \"world\"", "줄\n바꿈": "line\nbreak", "역슬래시 \\": "backslash \\"])
    }

    @Test func interpolationBuildsCompilerStyleKey() {
        let key: LocalizationKey = "\(3)장 · +\("ⓒ 5")"
        #expect(key.pattern == "%lld장 · +%@")
        #expect(key.arguments == ["3", "ⓒ 5"])
    }

    @Test func looksUpAndFillsPlaceholders() {
        let l = Localizer(table: ["%lld장 · +%@": "%lld cards · +%@", "새 덱 %lld": "New Deck %lld", "%@ (%@)": "%2$@ / %1$@"])
        #expect(l.string("\(3)장 · +\("ⓒ 5")") == "3 cards · +ⓒ 5")
        #expect(l.string("새 덱 \(7)") == "New Deck 7")
        #expect(l.string("\("a") (\("b"))") == "b / a")
    }

    @Test func missingKeyFallsBackToKoreanPattern() {
        let l = Localizer(table: ["%lld장": "%lld cards · %@"])
        #expect(l.string("버그 신고") == "버그 신고")
        #expect(l.string("\(2)장을 융합했어요") == "2장을 융합했어요")
        #expect(l.string("\(2)장") == "2 cards · %@")
    }

    @Test func realTablesParse() {
        #expect(Localizer.table(lang: "en")["무료 팩 · %@"] == "Free pack · %@")
        #expect(Localizer.table(lang: "ja").count == Localizer.table(lang: "en").count)
        #expect(Localizer.table(lang: "ko")["버그 신고"] == nil)
    }

    @Test func repoResourceFallsBackWhenNothingIsInstalled() {
        #expect(PlatformPaths.installedResource("cards_KO.json") == nil)
        #expect(FileManager.default.fileExists(atPath: PlatformPaths.resource("cards_KO.json").path))
        #expect(PlatformPaths.resource("en.lproj/Localizable.strings").lastPathComponent == "Localizable.strings")
    }
}
