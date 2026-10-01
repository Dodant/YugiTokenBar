import Foundation

struct LogEntry: Codable, Sendable, Equatable {
    let cid: Int
    /// "free" 또는 팩 pid
    let source: String
    let date: Date
}

struct GameState: Codable, Sendable, Equatable {
    var coins = 0
    var coinRemainder = 0
    var dropProgress = 0
    var owned: [Int: Int] = [:]
    var unlocked = 1
    var claimedDate: String?
    var claimedByProvider: [String: Int] = [:]
    var unseenFree = 0
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
        unlocked = try c.decodeIfPresent(Int.self, forKey: .unlocked) ?? d.unlocked
        claimedDate = try c.decodeIfPresent(String.self, forKey: .claimedDate)
        claimedByProvider = try c.decodeIfPresent([String: Int].self, forKey: .claimedByProvider) ?? d.claimedByProvider
        unseenFree = try c.decodeIfPresent(Int.self, forKey: .unseenFree) ?? d.unseenFree
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
        if fm.fileExists(atPath: url.path) {
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
