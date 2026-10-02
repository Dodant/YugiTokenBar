import Foundation

struct LogEntry: Codable, Sendable, Equatable {
    let cid: Int
    /// "free" 또는 팩 pid
    let source: String
    let date: Date
}

/// 사용자가 만든 덱. cards 는 cid → 장 수.
struct Deck: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var cards: [Int: Int] = [:]
    var count: Int { cards.values.reduce(0, +) }
}

struct GameState: Codable, Sendable, Equatable {
    var coins = 0
    var coinRemainder = 0
    var dropProgress = 0
    var owned: [Int: Int] = [:]
    var claimedDate: String?
    var claimedByProvider: [String: Int] = [:]
    /// 아직 열지 않은 무료 카드 장 수
    var pendingFree = 0
    /// 코인으로 산 팩 수 (packsPerFreePack 마다 0으로)
    var packStamp = 0
    /// 아직 쓰지 않은 무료 팩
    var freePacks = 0
    /// 컬렉션 즐겨찾기 (미보유 카드도 가능)
    var favorites: Set<Int> = []
    /// 설정: 이미 가진 카드가 나오면 바로 판다
    var autoSellDuplicates = false
    /// 컬렉션 창에서 만든 덱들
    var decks: [Deck] = []
    var log: [LogEntry] = []

    init() {}

    /// 빠진 키는 기본값 — 나중에 필드를 추가해도 옛 세이브가 "손상"으로 초기화되지 않게.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameState()
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? d.coins
        coinRemainder = try c.decodeIfPresent(Int.self, forKey: .coinRemainder) ?? d.coinRemainder
        dropProgress = try c.decodeIfPresent(Int.self, forKey: .dropProgress) ?? d.dropProgress
        owned = try c.decodeIfPresent([Int: Int].self, forKey: .owned) ?? d.owned
        claimedDate = try c.decodeIfPresent(String.self, forKey: .claimedDate)
        claimedByProvider = try c.decodeIfPresent([String: Int].self, forKey: .claimedByProvider) ?? d.claimedByProvider
        pendingFree = try c.decodeIfPresent(Int.self, forKey: .pendingFree) ?? d.pendingFree
        packStamp = try c.decodeIfPresent(Int.self, forKey: .packStamp) ?? d.packStamp
        freePacks = try c.decodeIfPresent(Int.self, forKey: .freePacks) ?? d.freePacks
        favorites = try c.decodeIfPresent(Set<Int>.self, forKey: .favorites) ?? d.favorites
        autoSellDuplicates = try c.decodeIfPresent(Bool.self, forKey: .autoSellDuplicates) ?? d.autoSellDuplicates
        decks = try c.decodeIfPresent([Deck].self, forKey: .decks) ?? d.decks
        log = try c.decodeIfPresent([LogEntry].self, forKey: .log) ?? d.log
    }
}

/// state.json 저장소. 원자적 쓰기, 쓰기 전 직전 파일을 .bak 으로 보존.
struct StateStore {
    let url: URL
    var backupURL: URL { url.appendingPathExtension("bak") }

    /// `YTB_STATE_DIR` 가 있으면 그 폴더를 쓴다(개발·QA 때 실제 세이브와 분리).
    static func standard() -> StateStore {
        let override = ProcessInfo.processInfo.environment["YTB_STATE_DIR"] ?? ""
        let dir = override.isEmpty
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("YugiTokenBar")
            : URL(fileURLWithPath: override, isDirectory: true)
        return StateStore(url: dir.appendingPathComponent("state.json"))
    }

    func load() -> GameState {
        if let state = Self.decode(url) { return state }
        if FileManager.default.fileExists(atPath: url.path) {
            // 손상된 원본은 지우지 않고 옆에 보관한다(데이터 유실 방지).
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: aside)
            AppLog.write("state.json 손상 → \(aside.lastPathComponent) 보관, .bak 복구 시도")
        }
        return Self.decode(backupURL) ?? GameState()
    }

    func save(_ state: GameState) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        // 현재 파일이 멀쩡할 때만 백업을 갱신한다(손상본이 좋은 .bak을 덮어쓰지 않도록).
        if Self.decode(url) != nil {
            try? fm.removeItem(at: backupURL)
            try fm.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func decode(_ url: URL) -> GameState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GameState.self, from: data)
    }
}
