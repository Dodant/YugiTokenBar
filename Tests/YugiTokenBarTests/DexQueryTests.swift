import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct DexQueryTests {
    /// 등급 메뉴의 "✦ 오버프레임": 오버프레임 판이 있는 카드만 (보유·해금과 상관없이)
    @MainActor @Test func overframeFilterKeepsOnlyOverframeCards() {
        let game = Game(db: oneBoxDB([1: overframeCard("카드1"), 2: card("카드2"), 3: overframeCard("카드3", 1)]), state: GameState())
        #expect(DexQuery(tier: DexQuery.overframeTier).entries(in: game).visible.map(\.cid) == [1, 3])
    }

    /// 전체는 팩 순서로 재수록을 한 번만. 등급·종류·검색 → 미보유 숨기기 → 정렬(같으면 순번). number 는 걸러도 처음 순번 그대로
    @MainActor @Test func filtersAndSorts() {
        var game = Game(db: makeDB([[(3, 1), (1, 4)], [(1, 4), (2, 2)]]), state: GameState())
        game.state.owned = [1: 2, 2: 1]
        let all = DexQuery().entries(in: game).visible
        #expect(all.map(\.cid) == [3, 1, 2] && all.map(\.number) == [1, 2, 3])

        let ownedOnly = DexQuery(showUnowned: false).entries(in: game)
        #expect(ownedOnly.visible.map(\.cid) == [1, 2])
        #expect(ownedOnly.tiered.count == 3)  // 부제의 "보유 / 전체" 는 숨기기 전 목록으로 센다

        #expect(DexQuery(sort: .tierDesc).entries(in: game).visible.map(\.cid) == [1, 2, 3])
        #expect(DexQuery(sort: .tierAsc).entries(in: game).visible.map(\.cid) == [3, 2, 1])
        #expect(DexQuery(sort: .copies).entries(in: game).visible.map(\.cid) == [1, 2, 3])

        let rare = DexQuery(tier: 2).entries(in: game).visible
        #expect(rare.map(\.cid) == [2] && rare.map(\.number) == [3])
        #expect(DexQuery(search: "카드3").entries(in: game).visible.map(\.cid) == [3])
        #expect(DexQuery(scope: .pack("p1")).entries(in: game).visible.map(\.cid) == [1, 2])
        #expect(DexQuery(scope: .pack("3")).entries(in: game).visible.map(\.cid) == [3, 1, 2])  // 옛 인덱스 키 → 전체
    }

    @Test func searchIgnoresSpacesAndMiddleDot() {
        #expect(DexQuery.squash("ブラック・マジシャン").localizedStandardContains(DexQuery.squash("ブラックマジシャン")))
        #expect(DexQuery.squash("Dark Magician") == "DarkMagician")
    }

    /// 즐겨찾기·덱 범위는 그 카드만, 팩 순서대로
    @MainActor @Test func favoritesAndDeckScopes() {
        var game = Game(db: makeDB([[(3, 1), (1, 4)], [(2, 2)]]), state: GameState())
        game.state.favorites = [2, 3]
        #expect(DexQuery(scope: .favorites).entries(in: game).visible.map(\.cid) == [3, 2])
        let deck = game.addDeck()
        _ = game.addToDeck(deck.id, 2)
        _ = game.addToDeck(deck.id, 1)
        #expect(DexQuery(scope: .deck(deck.id)).entries(in: game).visible.map(\.cid) == [1, 2])
    }

    /// 최근 획득은 획득 기록 최신순, 같은 카드는 한 번, DB 밖 카드는 뺀다
    @MainActor @Test func recentScope() {
        var game = Game(db: makeDB([[(3, 1), (1, 4)], [(2, 2)]]), state: GameState())
        for cid in [1, 2, 99, 1, 3] { game.give(cid, source: LogEntry.free) }
        #expect(DexQuery(scope: .recent).entries(in: game).visible.map(\.cid) == [3, 1, 2])
        // 정렬을 고르면 그대로 따른다 (같은 등급이면 획득 순서)
        #expect(DexQuery(scope: .recent, sort: .tierAsc).entries(in: game).visible.map(\.cid) == [3, 2, 1])
    }

    /// 그리드 칸 id 는 위치가 아니라 카드(cid)라, 목록이 바뀌어도 같은 칸 뷰가 다른 카드를 보여 주지 않는다
    @MainActor @Test func idIsCidAndUnique() {
        var game = Game(db: makeDB([[(3, 1), (1, 4)], [(1, 4), (2, 2)]]), state: GameState())
        let deck = game.addDeck()
        _ = game.addToDeck(deck.id, 2)
        _ = game.addToDeck(deck.id, 1)
        for scope in [DexScope?.none, .pack("p1"), .deck(deck.id)] {
            let ids = DexQuery(scope: scope).entries(in: game).visible.map(\.id)
            #expect(ids == DexQuery(scope: scope).entries(in: game).visible.map(\.cid))
            #expect(Set(ids).count == ids.count)
        }
    }

    /// game 에서 센 값은 보유·시대가 같은 동안 다시 세지 않는다 (사이드바 통계·융합 가능 목록)
    @MainActor @Test func gameMemoRecomputesOnlyWhenOwnedOrEraChange() {
        var game = Game(db: makeDB([[(1, 1)], [(2, 2)]]), state: GameState())
        var computed = 0
        let memo = GameMemo<Int> { computed += 1; return $0.ownedDistinct }
        #expect(memo(game) == 0 && memo(game) == 0 && computed == 1)
        game.state.coins = 5  // 상관없는 변화
        #expect(memo(game) == 0 && computed == 1)
        game.state.owned = [1: 1]
        #expect(memo(game) == 1 && computed == 2)
        game.state.eraLimit = "DM"
        #expect(memo(game) == 1 && computed == 3)
    }
}
