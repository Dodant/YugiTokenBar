import Foundation
import Testing
@testable import YugiTokenBar

/// Pi·Gemini·Grok·OMP 파일 파서. 줄을 나누는 방식을 바꿔도 같은 결과를 내야 한다 (픽스처는 PokeTokenBar 테스트의 것).
@Suite struct ProviderLineScanTests {
    private static let fmt = LocalUsageReader.localDayFormatter()
    private static func write(_ text: String, _ name: String) throws -> URL {
        let url = tempDir().appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func piParsesAssistantUsageOnly() throws {
        let url = try Self.write("""
        {"type":"message","id":"p0","timestamp":"2026-11-01T10:00:00.000Z","message":{"role":"user","content":"hi"}}
        {"type":"message","id":"p1","timestamp":"2026-11-01T10:00:05.000Z","message":{"role":"assistant","model":"pi-x","usage":{"input":100,"output":10,"cacheWrite":5,"cacheRead":20}}}
        """, "s.jsonl")
        let entries = try #require(LocalUsageReader.parsePiFile(url, fmt: Self.fmt))
        #expect(entries.map(\.id) == ["p1"])
        #expect(entries.map(\.model) == ["pi-x"])
        #expect(entries.map(\.total) == [135])
    }

    @Test func geminiParsesTokensAndKeepsUpdateAsFinal() throws {
        let url = try Self.write("""
        {"type":"session_metadata","sessionId":"s1","startTime":"2026-07-03T01:00:00.000Z"}
        {"type":"user","id":"m1","timestamp":"2026-07-03T01:00:05.000Z","content":[{"text":"hi"}]}
        {"type":"gemini","id":"m2","timestamp":"2026-07-03T01:00:10.000Z","model":"gemini-2.5-pro","tokens":{"input":1000,"output":50,"cached":600,"thoughts":30,"tool":20,"total":1100}}
        {"type":"gemini","id":"m3","timestamp":"2026-07-03T01:01:00.000Z","model":"gemini-2.5-flash","tokens":{"input":10,"output":5,"cached":0,"thoughts":0,"tool":0,"total":15}}
        {"type":"message_update","id":"m3","tokens":{"input":10,"output":8,"cached":0,"thoughts":2,"tool":0,"total":20}}
        """, "session.jsonl")
        let entries = LocalUsageReader.parseGeminiFile(url, fmt: Self.fmt)
        #expect(entries.count == 2)
        #expect(entries.first?.model == "gemini-2.5-pro")
        #expect(entries.map(\.total) == [1100, 20])
        #expect(entries.map(\.cacheRead) == [600, 0])
    }

    @Test func grokParsesTurnCompletedOnly() throws {
        let url = try Self.write("""
        {"timestamp":1785000019,"method":"_x.ai/session/update","params":{"sessionId":"s2","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hi"}}}}
        {"timestamp":1785000020,"method":"_x.ai/session/update","params":{"sessionId":"s2","update":{"sessionUpdate":"turn_completed","prompt_id":"p-snake","stop_reason":"end_turn","usage":{"input_tokens":60,"output_tokens":10,"total_tokens":110,"cached_read_tokens":40}},"_meta":{"eventId":"ev-snake","agentTimestampMs":1785000020000}}}
        """, "updates.jsonl")
        let entries = LocalUsageReader.parseGrokFile(url, fmt: Self.fmt)
        #expect(entries.count == 1)
        #expect(entries.map(\.total) == [110])
        #expect(entries.map(\.cacheRead) == [40])
    }

    @Test func ompParsesAssistantUsageLines() throws {
        let url = try Self.write("""
        {"type":"session","version":3,"id":"019f9552","timestamp":"2026-07-03T01:00:00.000Z","cwd":"/Users/x/Proj"}
        {"type":"model_change","id":"aa01","parentId":null,"timestamp":"2026-07-03T01:00:01.000Z","model":"modal-k3/moonshotai/Kimi-K3"}
        {"type":"message","id":"bb01","parentId":"aa01","timestamp":"2026-07-03T01:00:05.000Z","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}
        {"type":"message","id":"cc01","parentId":"bb01","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","content":[{"type":"text","text":"hello"}],"model":"moonshotai/Kimi-K3","usage":{"input":100,"output":10,"cacheRead":600,"cacheWrite":40,"totalTokens":750,"cost":{"input":0.001,"output":0.002,"cacheRead":0.002,"cacheWrite":0.0,"total":0.005}}}}
        {"type":"message","id":"dd01","parentId":"cc01","timestamp":"2026-07-03T01:00:12.000Z","message":{"role":"toolResult","toolCallId":"t1","content":[{"type":"text","text":"ok"}]}}
        {"type":"message","id":"ee01","parentId":"dd01","timestamp":"2026-07-03T01:01:00.000Z","message":{"role":"assistant","content":[],"model":"modal/nvidia/GLM-5.2","usage":{"input":5,"output":7,"cacheRead":0,"cacheWrite":3,"totalTokens":15,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}}}}
        {"type":"custom","customType":"tool_execution_start","timestamp":"2026-07-03T01:01:05.000Z"}
        """, "2026-07-03T01-00-00-000Z_019f9552.jsonl")
        let entries = try #require(LocalUsageReader.parseOmpFile(url, fmt: Self.fmt))
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.total)) == [750, 15])
        #expect(Set(entries.map(\.model)) == ["moonshotai/Kimi-K3", "modal/nvidia/GLM-5.2"])
    }

    /// 네 파서가 쓰는 공유 줄 반복기: 잘못된 UTF-8은 그 줄만 건너뛰고 `\r\n` 줄 끝도 줄마다 읽는다 (OMP 로 대표)
    @Test func ompSkipsInvalidUTF8LineAndReadsCRLF() throws {
        let good = #"{"type":"message","id":"c1","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","model":"m","usage":{"input":1,"output":2,"cacheRead":0,"cacheWrite":0,"totalTokens":3}}}"#
        var data = Data((good + "\r\n").utf8)
        data.append(contentsOf: [0xFF, 0xFE, 0x0A])
        let url = tempDir().appendingPathComponent("x.jsonl")
        try data.write(to: url)
        let entries = try #require(LocalUsageReader.parseOmpFile(url, fmt: Self.fmt))
        #expect(entries.map(\.total) == [3])
    }
}
