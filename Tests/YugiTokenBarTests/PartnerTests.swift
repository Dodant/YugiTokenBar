import CoreGraphics
import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct PartnerTests {
    // MARK: 시트

    @Test func sheetSlicesEveryRow() throws {
        #expect(PartnerAnim.allCases.map(\.frameCount) == [6, 8, 8, 4, 5, 8, 6, 6, 6])
        let sheet = try #require(PartnerSheet.bundled())
        for anim in PartnerAnim.allCases {
            let frames = try #require(sheet.frames[anim])
            #expect(frames.count == anim.frameCount)
            #expect(frames.allSatisfy { $0.width == 192 && $0.height == 208 })
        }
    }

    @Test func sheetRejectsNonImage() {
        #expect(PartnerSheet(url: CardDB.repoCardsURL) == nil)
    }

    // MARK: 상태 판정

    @Test func baseMoodPriority() {
        #expect(PartnerMood.base(tokensPerMinute: 500_000, limitPercent: 80) == .sad)  // 한도가 사용량보다 먼저
        #expect(PartnerMood.base(tokensPerMinute: 0, limitPercent: 79.9) == .idle)
        #expect(PartnerMood.base(tokensPerMinute: 100_000, limitPercent: 0) == .fly)
        #expect(PartnerMood.base(tokensPerMinute: 99_999, limitPercent: 0) == .flap)
        #expect(PartnerMood.base(tokensPerMinute: 1_000, limitPercent: 0) == .flap)
        #expect(PartnerMood.base(tokensPerMinute: 999, limitPercent: 0) == .idle)
    }

    @Test func tokensPerMinuteFromSamples() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = UsageSample(date: "2026-10-02", total: 1_000, at: t0)
        #expect(PartnerMood.tokensPerMinute(from: nil, to: a) == 0)  // 첫 갱신
        let b = UsageSample(date: "2026-10-02", total: 201_000, at: t0.addingTimeInterval(120))
        #expect(PartnerMood.tokensPerMinute(from: a, to: b) == 100_000)
    }

    @Test func tokensPerMinuteIgnoresResetAndShortGaps() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = UsageSample(date: "2026-10-02", total: 50_000, at: t0)
        let nextDay = UsageSample(date: "2026-10-03", total: 60_000, at: t0.addingTimeInterval(60))
        #expect(PartnerMood.tokensPerMinute(from: a, to: nextDay) == 0)  // 자정
        let lower = UsageSample(date: "2026-10-02", total: 10_000, at: t0.addingTimeInterval(60))
        #expect(PartnerMood.tokensPerMinute(from: a, to: lower) == 0)  // 일시적으로 작게 읽힘
        let soon = UsageSample(date: "2026-10-02", total: 55_000, at: t0.addingTimeInterval(1))
        #expect(PartnerMood.tokensPerMinute(from: a, to: soon) == 5_000)  // 1분 미만은 1분으로
    }

    // MARK: 애니메이션 진행

    private func run(_ p: inout PartnerPlayer, _ n: Int) { for _ in 0..<n { p.tick() } }

    @Test func oneShotReturnsToBase() {
        var p = PartnerPlayer()
        p.setMood(.flap)
        p.interrupt(.excited)
        #expect(p.anim == .excited && p.frame == 0)
        run(&p, PartnerAnim.excited.frameCount)
        #expect(p.anim == .flap && p.frame == 0)
    }

    @Test func queueDedupesAndInterruptClears() {
        var p = PartnerPlayer()
        p.setMood(.sad)
        p.play(.wave)
        p.play(.wave)
        #expect(p.queue == [.wave])
        p.play(.excited)
        p.interrupt(.puzzled)
        #expect(p.queue.isEmpty && p.anim == .puzzled)
    }

    @Test func idleHoldBreaksForOneShotAndMood() {
        var p = PartnerPlayer()
        run(&p, PartnerAnim.idle.frameCount)  // 첫 깜빡임이 끝나면 첫 프레임으로 멈춘다
        #expect(p.anim == .idle && p.frame == 0)
        p.play(.wave)
        #expect(p.anim == .wave && p.queue.isEmpty)  // 멈춰 있던 대기는 바로 끊는다

        var q = PartnerPlayer()
        run(&q, PartnerAnim.idle.frameCount)
        q.setMood(.sad)
        #expect(q.anim == .sad)
    }

    @Test func flyAlternatesDirection() {
        var p = PartnerPlayer()
        p.setMood(.fly)
        run(&p, PartnerAnim.idle.frameCount)
        #expect(p.anim == .flyRight)
        run(&p, PartnerAnim.flyRight.frameCount)
        #expect(p.anim == .flyRight)  // After one loop, still flyRight
        run(&p, PartnerAnim.flyRight.frameCount * (PartnerTuning.flyLoops - 1))
        #expect(p.anim == .flyLeft)  // After flyLoops total, switch to flyLeft
        run(&p, PartnerAnim.flyLeft.frameCount * PartnerTuning.flyLoops)
        #expect(p.anim == .flyRight)  // After flyLeft loops, switch back to flyRight
    }

    @Test func oneShotInteractions() {
        // (a) setMood during one-shot doesn't cut it
        var p = PartnerPlayer()
        p.setMood(.sad)
        p.interrupt(.excited)
        #expect(p.anim == .excited)
        p.setMood(.idle)
        run(&p, 3)  // Tick a few frames into excited
        #expect(p.anim == .excited)  // Still excited, not switched to idle yet
        run(&p, PartnerAnim.excited.frameCount - 3)  // Finish excited
        #expect(p.anim == .idle)  // Now becomes idle

        // (b) play during non-idle base waits for loop end
        var q = PartnerPlayer()
        run(&q, PartnerAnim.idle.frameCount)  // Finish initial idle
        q.setMood(.flap)
        run(&q, 1)  // One tick to advance to flap
        #expect(q.anim == .flap)
        q.play(.wave)
        #expect(q.anim == .flap && !q.queue.isEmpty)  // Still flap, wave waits in queue
        run(&q, PartnerAnim.flap.frameCount)  // Finish one flap loop
        #expect(q.anim == .wave)  // Now plays wave

        // (c) interrupt with current anim restarts at frame 0
        var r = PartnerPlayer()
        run(&r, PartnerAnim.idle.frameCount)  // Finish initial idle (frame becomes 6, then advance)
        r.setMood(.flap)  // hold > 0, so advance() is called immediately, frame = 0
        run(&r, 3)  // Tick 3 more frames into flap
        #expect(r.frame == 3 && r.anim == .flap)
        r.interrupt(.flap)
        #expect(r.anim == .flap && r.frame == 0)  // Restarted at frame 0
    }

    @Test func idleLooksAroundEventually() {
        var p = PartnerPlayer()
        var seen = false
        for _ in 0..<(PartnerTuning.lookAroundTicks + 60) {
            p.tick()
            seen = seen || p.anim == .lookAround
        }
        #expect(seen)
    }

    @Test func menuBlinksPeriodically() {
        #expect((0..<6).map { PartnerPlayer.menuFrame(tick: $0) } == [0, 1, 2, 3, 4, 5])
        #expect(PartnerPlayer.menuFrame(tick: 6) == 0)
        #expect(PartnerPlayer.menuFrame(tick: PartnerTuning.menuBlinkTicks - 1) == 0)
        #expect(PartnerPlayer.menuFrame(tick: PartnerTuning.menuBlinkTicks + 1) == 1)
    }
}
