import Testing
@testable import YugiTokenBar

@Suite struct DeckTests {
    /// 카드마다 3장까지. 보유 수와 상관없이 미보유 카드도 넣는다(목표 덱).
    @Test func addAllowsUnownedUpToThreeCopies() {
        var game = Game(db: makeDB([[(1, 1), (2, 1)]]), state: GameState())
        game.state.owned = [1: 1]
        let deck = game.addDeck()
        #expect(deck.name == "새 덱 1")
        // #expect 안에서는 mutating 호출을 못 해서 결과를 먼저 받는다
        let adds = (0..<4).map { _ in game.addToDeck(deck.id, 1) }
        #expect(adds == [true, true, true, false])  // 보유 1장이어도 3장까지, 4장째는 거절
        let unowned = game.addToDeck(deck.id, 2)
        #expect(unowned)  // 미보유
        #expect(game.deck(deck.id)?.cards == [1: 3, 2: 1])
        #expect(game.deck(deck.id)?.count == 4)
    }

    @Test func removeRenameDelete() {
        var game = Game(db: makeDB([[(1, 1)]]), state: GameState())
        let deck = game.addDeck()
        _ = game.addToDeck(deck.id, 1)
        _ = game.addToDeck(deck.id, 1)
        game.removeFromDeck(deck.id, 1)
        #expect(game.deck(deck.id)?.cards == [1: 1])
        game.removeFromDeck(deck.id, 1)
        #expect(game.deck(deck.id)?.cards == [:])
        game.renameDeck(deck.id, to: "  드래곤 덱 ")
        #expect(game.deck(deck.id)?.name == "드래곤 덱")
        game.renameDeck(deck.id, to: "   ")  // 빈 이름은 무시
        #expect(game.deck(deck.id)?.name == "드래곤 덱")
        game.deleteDeck(deck.id)
        #expect(game.state.decks.isEmpty)
    }
}
