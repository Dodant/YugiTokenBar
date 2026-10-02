import Foundation

/// 내보낸 세이브 파일. `GameState` 디코딩은 빠진 키를 기본값으로 채워서 아무 JSON 이나 "성공"하므로,
/// 기본값이 없는 format/schema 로 세이브 파일인지 먼저 가린다.
struct SaveEnvelope: Codable, Equatable {
    static let formatID = "yugitokenbar.save"
    static let schemaVersion = 1
    /// 정상 세이브는 수백 KB 이하. 거대한 JSON 이 메인 스레드를 오래 잡지 않게 막는다.
    static let maxFileBytes = 8 * 1024 * 1024

    var format = formatID
    var schema = schemaVersion
    var appVersion: String
    var exportedAt: Date
    var state: GameState

    init(appVersion: String, exportedAt: Date, state: GameState) {
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.state = state
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SaveEnvelope {
        guard data.count <= maxFileBytes else { throw SaveTransferError.tooLarge }
        struct Header: Decodable { let format: String; let schema: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == formatID
        else { throw SaveTransferError.notASaveFile }
        guard header.schema <= schemaVersion else { throw SaveTransferError.newerSchema }
        do { return try JSONDecoder().decode(SaveEnvelope.self, from: data) } catch { throw SaveTransferError.notASaveFile }
    }

    static func fileName(_ date: Date) -> String { "YugiTokenBar-Save-\(stamp(date, "yyyyMMdd")).json" }
}

enum SaveTransferError: LocalizedError, Equatable {
    case notASaveFile, newerSchema, tooLarge

    var errorDescription: String? {
        switch self {
        case .notASaveFile: "YugiTokenBar 세이브 파일이 아니에요."
        case .newerSchema: "더 새 버전 앱에서 만든 세이브예요. 앱을 업데이트한 뒤 가져와 주세요."
        case .tooLarge: "세이브 파일로 보기엔 너무 커요."
        }
    }
}

extension GameState {
    /// 다른 Mac 세이브를 들여올 때 적립 원장은 이 Mac 값을 쓴다. 안 그러면 오늘 토큰을 다시 적립한다.
    func withLedger(of local: GameState) -> GameState {
        var state = self
        state.claimedDate = local.claimedDate
        state.claimedByProvider = local.claimedByProvider
        return state
    }

    var distinctOwned: Int { owned.values.filter { $0 > 0 }.count }
}

extension StateStore {
    /// 가져오기 직전 현재 세이브를 같은 폴더(= YTB_STATE_DIR)에 봉투로 남긴다. 그대로 [가져오기]로 되돌릴 수 있다.
    // ponytail: 백업은 쌓이기만 한다(수십 KB). 많아지면 오래된 것부터 정리
    func backupBeforeImport(_ state: GameState, appVersion: String, now: Date = Date()) throws -> URL {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let backup = dir.appendingPathComponent("state.import-backup-\(stamp(now, "yyyyMMdd-HHmmss")).json")
        try SaveEnvelope(appVersion: appVersion, exportedAt: now, state: state).encoded().write(to: backup, options: .atomic)
        return backup
    }
}

private func stamp(_ date: Date, _ format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format
    return formatter.string(from: date)
}
