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

    static let dbs: [String: CardDB] = Dictionary(uniqueKeysWithValues: ["ko", "en", "ja"].map { ($0, try! CardDB.load(from: CardDB.repoURL($0))) })

    /// 세 언어 파일은 같은 팩(pid·카드 목록)·같은 카드 집합이고, 언어 무관 필드가 같다
    @Test func sameCardsAndPacksInEveryLanguage() {
        let ko = Self.dbs["ko"]!
        for (lang, db) in Self.dbs {
            #expect(db.packs.map(\.pid) == ko.packs.map(\.pid), "\(lang) 팩 순서")
            #expect(db.packs.map(\.cards) == ko.packs.map(\.cards), "\(lang) 팩 카드")
            #expect(db.packs.map(\.imageURL) == ko.packs.map(\.imageURL) && db.packs.map(\.date) == ko.packs.map(\.date))
            #expect(Set(db.cards.keys) == Set(ko.cards.keys), "\(lang) cid 집합")
            for (cid, k) in ko.cards {
                let c = db.cards[cid]!
                #expect(c.tier == k.tier && c.kindCode == k.kindCode && c.summons == k.summons && c.imageId == k.imageId
                        && c.level == k.level && c.atk == k.atk && c.def == k.def && c.scale == k.scale, "\(lang) \(cid)")
                #expect(c.materials?.map(\.cid) == k.materials?.map(\.cid) && c.fusionMaterials == k.fusionMaterials, "\(lang) \(cid) 소재")
            }
        }
    }

    /// 대체 규칙 결과: 어느 언어든 모든 카드·팩에 이름이 있고, EN·JP 는 대부분 그 언어다
    @Test func everyCardHasAName() {
        let ko = Self.dbs["ko"]!
        for (lang, db) in Self.dbs {
            #expect(db.cards.values.allSatisfy { !$0.name.isEmpty }, "\(lang) 빈 이름")
            #expect(db.packs.allSatisfy { !$0.name.isEmpty })
            guard lang != "ko" else { continue }
            let same = ko.cards.filter { db.cards[$0.key]?.name == $0.value.name }.count
            #expect(same < ko.cards.count / 10, "\(lang): KO 와 이름이 같은 카드가 \(same)장 (대체가 너무 많음)")
        }
        #expect(Self.dbs["en"]!.cards[4007]?.name == "Blue-Eyes White Dragon")
        #expect(Self.dbs["ja"]!.cards[4007]?.name == "青眼の白龍")
        #expect(Self.dbs["en"]!.cards[4043]?.materials == [Material(cid: 4044), Material(cid: 4045)])
        #expect(Self.dbs["en"]!.cards[4043]?.text.contains("+") == false)  // 소재 줄은 뗀다
    }

    /// 같은 세이브를 어느 언어로 열어도 컬렉션 수·등급 진행·종류·융합 가능 목록이 같다
    @Test func collectionIsTheSameInEveryLanguage() {
        var state = GameState()
        state.eraLimit = "Modern"
        state.fusionOnly = true
        let ko = Self.dbs["ko"]!
        for (i, cid) in ko.allCIDs.enumerated() where i % 3 == 0 { state.owned[cid] = 1 + i % 4 }
        state.owned[CardDB.fusionSpell] = 1
        let games = Self.dbs.mapValues { Game(db: $0, state: state) }
        let base = games["ko"]!
        for (lang, game) in games {
            #expect(game.ownedDistinct == base.ownedDistinct, "\(lang)")
            #expect(game.db.allCIDs.count == base.db.allCIDs.count)
            #expect(game.tierProgress.map(\.owned) == base.tierProgress.map(\.owned))
            #expect(game.fusable == base.fusable, "\(lang) 융합 가능")
            for kind in CardKind.allCases.map(\.rawValue) + CardInfo.summonCodes {
                #expect(game.db.allCIDs.filter { game.db.cards[$0]!.matches(kind: kind) } == base.db.allCIDs.filter { base.db.cards[$0]!.matches(kind: kind) }, "\(lang) \(kind)")
            }
            #expect(game.db.allCIDs.map { game.db.cards[$0]!.levelKind } == base.db.allCIDs.map { base.db.cards[$0]!.levelKind })
        }
    }
}
