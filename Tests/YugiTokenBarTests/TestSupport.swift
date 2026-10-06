import Foundation
@testable import YugiTokenBar

/// 시드 고정 RNG (SplitMix64)
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 팩마다 (cid, tier) 목록으로 작은 카드 DB를 만든다. 여러 팩에 있는 카드는 build-cards.py 처럼 가장 높은 tier.
func makeDB(_ packs: [[(cid: Int, tier: Int)]]) -> CardDB {
    var cards: [Int: CardInfo] = [:]
    var built: [Pack] = []
    for (i, list) in packs.enumerated() {
        for c in list {
            cards[c.cid] = CardInfo(name: "카드\(c.cid)", attr: nil, level: nil, type: nil,
                                    atk: nil, def: nil, text: "", imageId: nil, tier: max(cards[c.cid]?.tier ?? 1, c.tier))
        }
        built.append(Pack(pid: "p\(i)", name: "팩\(i)", date: "2004-01-01",
                          cards: list.map(\.cid)))
    }
    return CardDB(packs: built, cards: cards)
}

func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ytb-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
