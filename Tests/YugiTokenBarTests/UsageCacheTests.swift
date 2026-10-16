import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif
import Testing
@testable import YugiTokenBar

@Suite struct UsageCacheTests {
    /// 로컬 Cursor DB: 두 번째부터는 새 행만 읽어 합치고, DB 를 새로 만들어 rowid 가 거꾸로 가면 처음부터 읽은 것만 쓴다
    @Test func localCursorReadsNewRowsAndResetsOnRewrite() async throws {
        let dir = tempDir(), db = dir.appendingPathComponent("state.vscdb")
        func exec(_ sql: String) {
            var handle: OpaquePointer?
            sqlite3_open(db.path, &handle)
            sqlite3_exec(handle, sql, nil, nil, nil)
            sqlite3_close(handle)
        }
        func bubble(_ id: Int, _ input: Int) -> String {
            let at = ISO8601DateFormatter().string(from: Date())
            return #"INSERT INTO cursorDiskKV (key, value) VALUES ('bubbleId:c:\#(id)', '{"tokenCount":{"inputTokens":\#(input),"outputTokens":0},"createdAt":"\#(at)"}');"#
        }
        exec("CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);" + bubble(1, 100) + bubble(2, 20))
        let reader = TodayUsageReader(claudeRoots: [tempDir()], liveCursor: nil)
        let since = Date().addingTimeInterval(-3600)
        func total() async -> Int { await reader.localCursorEntries(modifiedSince: since, roots: [dir]).reduce(0) { $0 + $1.total } }

        #expect(await total() == 120)
        exec(bubble(3, 5))
        #expect(await total() == 125)  // 앞의 두 행은 지난 결과에서, 새 행만 읽어 더한다
        #expect(await total() == 125)  // 새 행이 없으면 그대로
        exec("DELETE FROM cursorDiskKV; VACUUM;" + bubble(9, 7))  // rowid 가 1부터 다시
        #expect(await total() == 7)
    }

    /// 파일별 캐시를 디스크에 두면, 새 인스턴스(다음 실행)도 바뀌지 않은 파일은 다시 파싱하지 않는다
    @Test func usageCacheSurvivesRestart() async throws {
        let root = tempDir(), project = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        func line(_ input: Int) -> String {
            #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":\#(input),"output_tokens":0}}}"# + "\n"
        }
        let log = project.appendingPathComponent("s.jsonl"), file = tempDir().appendingPathComponent("usage-cache.json")
        // 수정 시각은 초 단위로 고정한다 (되돌려 쓸 때 나노초가 잘려 다른 파일로 보이지 않게)
        let mtime = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down) - 10)
        func write(_ input: Int) throws {
            try line(input).write(to: log, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: log.path)
        }
        try write(100)
        let since = Date().addingTimeInterval(-3600)
        #expect(await LocalUsageCache(claudeRoots: [root], fileURL: file).claudeEntries(modifiedSince: since).map(\.total) == [100])

        // 크기·수정 시각이 같은 채로 내용만 바꾸면, 디스크 캐시를 읽은 새 인스턴스는 예전 값을 낸다
        try write(200)
        #expect(await LocalUsageCache(claudeRoots: [root], fileURL: file).claudeEntries(modifiedSince: since).map(\.total) == [100])
        #expect(await LocalUsageCache(claudeRoots: [root]).claudeEntries(modifiedSince: since).map(\.total) == [200])
    }
}
