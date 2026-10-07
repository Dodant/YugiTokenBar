import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct DexQueryTests {
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
        #expect(DexQuery(scope: .pack(1)).entries(in: game).visible.map(\.cid) == [1, 2])
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

    /// 그리드 칸 id 는 위치가 아니라 카드(cid)라, 목록이 바뀌어도 같은 칸 뷰가 다른 카드를 보여 주지 않는다
    @MainActor @Test func idIsCidAndUnique() {
        var game = Game(db: makeDB([[(3, 1), (1, 4)], [(1, 4), (2, 2)]]), state: GameState())
        let deck = game.addDeck()
        _ = game.addToDeck(deck.id, 2)
        _ = game.addToDeck(deck.id, 1)
        for scope in [DexScope?.none, .pack(1), .deck(deck.id)] {
            let ids = DexQuery(scope: scope).entries(in: game).visible.map(\.id)
            #expect(ids == DexQuery(scope: scope).entries(in: game).visible.map(\.cid))
            #expect(Set(ids).count == ids.count)
        }
    }
}
