import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct DuelistPackTests {
    /// 시대는 팩의 era 연속 구간(eraNames 순), 정규 부스터 뒤에 듀얼리스트 팩. 빈 시대는 뺀다
    @Test func erasComeFromPackEraRuns() {
        let db = makeDB((0..<5).map { [($0 + 1, 1)] }, era: { [0, 1, 2].contains($0) ? "DM" : "GX" }, kind: { $0 == 2 || $0 == 4 ? .duelist : .booster })
        #expect(db.eras.map(\.name) == ["DM", "GX"] && db.eras.map(\.packs) == [0..<3, 3..<5])
        #expect(db.packs[2].kind == .duelist && db.prefix(packs: 3).eras.map(\.packs) == [0..<3])
        let state = { var s = GameState(); s.eraLimit = "DM"; return s }()
        #expect(Game(db: db, state: state).db.packs.map(\.pid) == ["p0", "p1", "p2"])  // DM 범위에 DM 듀얼리스트 팩이 든다
    }

    /// kind·era 가 없거나 시대 순이 아닌 파일은 거부한다 (조용히 전부 DM 이 되지 않게)
    @Test func loadRejectsUnsortedOrMissingEra() throws {
        let dir = tempDir()
        try "{}".write(to: dir.appendingPathComponent("picks.json"), atomically: true, encoding: .utf8)
        let url = dir.appendingPathComponent("cards_KO.json")
        let pack = { (pid: String, era: String) in #"{"pid":"\#(pid)","name":"n","date":"2004-01-01","kind":"booster","era":"\#(era)","cards":[1]}"# }
        let cards = #""cards":{"1":{"name":"x","text":"","tier":1}}"#  // CardInfo 는 name·text·tier 가 필수 키
        try #"{"packs":[\#(pack("a", "DM")),\#(pack("b", "GX")),\#(pack("c", "DM"))],\#(cards)}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try CardDB.load(from: url) }  // DM 이 끊김
        try #"{"packs":[{"pid":"a","name":"n","date":"2004-01-01","cards":[1]}],\#(cards)}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try CardDB.load(from: url) }  // kind·era 없음
        try #"{"packs":[\#(pack("a", "DM")),\#(pack("b", "GX"))],\#(cards)}"#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = try CardDB.load(from: url)
        #expect(loaded.eras.map(\.name) == ["DM", "GX"])
    }

    /// 두 팩에 든 카드는 두 팩 모두에서 나오고, 받으면 두 팩의 진행도가 오르며, 한 팩만 다 모아도 판매가가 ×3
    @Test func cardInTwoPacksDrawsFromBoth() {
        var game = Game(db: makeDB([[(1, 1), (2, 1), (6, 1)], [(3, 1), (4, 1), (6, 1)]], kind: { $0 == 1 ? .duelist : .booster }), state: GameState())
        var rng = SeededRNG(seed: 7)
        var seen: [Set<Int>] = [[], []]
        for _ in 0..<40 { for p in 0..<2 { if let c = game.draw(pack: p, tier: 1, using: &rng) { seen[p].insert(c) } } }
        #expect(seen[0].contains(6) && seen[1].contains(6))
        game.give(6, source: "p1")
        #expect(game.progress(0).owned == 1 && game.progress(1).owned == 1)
        game.give(1, source: "p0"); game.give(2, source: "p0")
        #expect(game.progress(0).cleared && !game.progress(1).cleared)
        #expect(game.sellPrice(6) == Balance.sellPrice[1]! * Balance.clearedSellMultiplier)
    }
}
