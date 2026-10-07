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
        #expect(PartnerSheet(url: CardDB.repoURL("ko")) == nil)
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

    /// 쉬는 동안이면 끝날 때까지 돌린다. 돌린 틱 수를 돌려준다.
    private func runRest(_ p: inout PartnerPlayer) -> Int {
        var n = 0
        while p.resting { p.tick(); n += 1 }
        return n
    }

    @Test func flyAlternatesDirectionWithRests() {
        var p = PartnerPlayer(rng: SeededRNG(seed: 1))
        p.setMood(.fly)
        run(&p, PartnerAnim.idle.frameCount)
        #expect(p.anim == .flyRight)
        run(&p, PartnerAnim.flyRight.frameCount)
        #expect(p.resting && p.anim == .flyRight && p.frame == 0)  // 한 바퀴 뒤 첫 프레임에서 쉰다
        _ = runRest(&p)
        #expect(p.anim == .flyLeft)  // 쉬고 나면 반대 방향
        run(&p, PartnerAnim.flyLeft.frameCount)
        _ = runRest(&p)
        #expect(p.anim == .flyRight)
    }

    @Test func baseLoopRestsWithinRange() {
        for seed in 0..<20 as Range<UInt64> {
            var p = PartnerPlayer(rng: SeededRNG(seed: seed))
            p.setMood(.flap)
            run(&p, PartnerAnim.idle.frameCount)
            #expect(p.anim == .flap)
            run(&p, PartnerAnim.flap.frameCount)
            let range = PartnerTuning.rest(.flap)
            let ticks = runRest(&p)
            #expect(ticks >= Int(range.lowerBound * PartnerTuning.fps) && ticks <= Int(range.upperBound * PartnerTuning.fps))
            #expect(p.anim == .flap && p.frame == 0 && !p.resting)
        }
    }

    @Test func oneShotDoesNotRest() {
        var p = PartnerPlayer(rng: SeededRNG(seed: 2))
        p.setMood(.sad)
        p.interrupt(.excited)
        run(&p, PartnerAnim.excited.frameCount)
        #expect(p.anim == .sad && !p.resting)  // 한 번 재생 뒤에는 쉬지 않고 바로 기준 상태
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
        #expect(q.anim == .flap && q.frame == 0)  // setMood ends the idle rest and starts flap at once
        run(&q, 1)
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
        var p = PartnerPlayer(rng: SeededRNG(seed: 3))
        var seen = false
        let maxIdle = PartnerTuning.lookAroundEvery.upperBound + PartnerTuning.rest(.idle).upperBound
        for _ in 0..<Int(maxIdle * PartnerTuning.fps) + PartnerAnim.idle.frameCount {
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

    // MARK: 해금·저장

    @Test func partnerCardIsWingedKuriboh() throws {
        #expect(try CardDB.bundled().cards[CardDB.partnerCard]?.name == "날개 크리보")
    }

    @Test func unlockIsPermanent() {
        var game = Game(db: makeDB([[(CardDB.partnerCard, 3)]]), state: GameState())
        let result1 = game.unlockPartnerIfOwned()
        #expect(!result1)  // 없으면 잠김
        game.state.owned[CardDB.partnerCard] = 1
        let result2 = game.unlockPartnerIfOwned()
        #expect(result2)   // 새로 해금
        let result3 = game.unlockPartnerIfOwned()
        #expect(!result3)  // 이미 해금
        let sellResult = game.sell(CardDB.partnerCard)
        #expect(sellResult != nil)
        #expect(game.state.partnerUnlocked)    // 팔아도 유지
    }

    @Test func oldSaveDecodesPartnerDefaults() throws {
        let state = try JSONDecoder().decode(GameState.self, from: Data(#"{"coins":5,"owned":{"6314":1}}"#.utf8))
        #expect(state.coins == 5 && !state.partnerUnlocked && state.partnerEnabled)
        #expect(state.partnerSize == 128 && state.partnerOrigin == nil)
    }

    @Test func partnerFieldsRoundTrip() throws {
        var state = GameState()
        state.partnerUnlocked = true
        state.partnerEnabled = false
        state.partnerSize = 96
        state.partnerOrigin = CGPoint(x: 120, y: 40)
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        #expect(back == state)
    }

    // MARK: 반응

    @Test func reactionsOnUnlockAndCoins() {
        var old = GameState()
        old.coins = Balance.packPrice - 1
        var new = old
        #expect(PartnerAnim.reactions(from: old, to: new, newlyUnlocked: false).isEmpty)
        #expect(PartnerAnim.reactions(from: old, to: new, newlyUnlocked: true) == [.excited])
        new.coins = Balance.packPrice
        #expect(PartnerAnim.reactions(from: old, to: new, newlyUnlocked: false) == [.wave])
        new.pendingFree = 1
        #expect(PartnerAnim.reactions(from: old, to: new, newlyUnlocked: false) == [.excited, .wave])
        old.coins = Balance.packPrice  // 이미 넘어 있으면 손짓 없음
        old.pendingFree = 1
        new.freePacks = 1
        #expect(PartnerAnim.reactions(from: old, to: new, newlyUnlocked: false) == [.excited])
    }

    @MainActor @Test func saveUnlocksPartner() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var state = GameState()
        state.pendingFree = 1
        try store.save(state)
        let model = AppModel(db: makeDB([[(CardDB.partnerCard, 1)]]), store: store, partner: PartnerModel(sheet: nil))
        #expect(!model.game.state.partnerUnlocked)
        #expect(model.openFree())  // 풀에 날개 크리보 1종뿐
        #expect(model.game.state.partnerUnlocked)
        #expect(store.load().partnerUnlocked)
    }

    @MainActor @Test func unlocksOnLaunch() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var state = GameState()
        state.owned[CardDB.partnerCard] = 1
        try store.save(state)
        let model = AppModel(db: makeDB([[(CardDB.partnerCard, 1)]]), store: store, partner: PartnerModel(sheet: nil))
        #expect(!model.game.state.partnerUnlocked)
        model.unlockOnLaunch()
        #expect(model.game.state.partnerUnlocked)
        #expect(store.load().partnerUnlocked)
    }

    @MainActor @Test func importKeepsUnlockAndLocalPartnerSettings() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var state = GameState()
        state.partnerUnlocked = true
        state.partnerSize = 200
        try store.save(state)
        let model = AppModel(db: makeDB([[(1, 1)]]), store: store, partner: PartnerModel(sheet: nil))
        var incoming = GameState()
        incoming.partnerSize = 64
        _ = try model.importSave(SaveEnvelope(appVersion: "0", exportedAt: Date(), state: incoming))
        #expect(model.game.state.partnerUnlocked)  // 해금은 영구
        #expect(model.game.state.partnerSize == 200)  // 표시 설정은 이 Mac 값
        #expect(store.load().partnerUnlocked)
    }

    @MainActor @Test func importSaveWithKuribohUnlocks() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        try store.save(GameState())
        let model = AppModel(db: makeDB([[(CardDB.partnerCard, 1)]]), store: store, partner: PartnerModel(sheet: nil))
        var incoming = GameState()
        incoming.owned[CardDB.partnerCard] = 1
        _ = try model.importSave(SaveEnvelope(appVersion: "0", exportedAt: Date(), state: incoming))
        #expect(model.game.state.partnerUnlocked)
        #expect(store.load().partnerUnlocked)
    }

    @MainActor @Test func missingSheetDisablesPartner() {
        let m = PartnerModel(sheet: nil)
        #expect(!m.isReady)
        m.start()
        m.play(.excited)
        #expect(m.menu.image == nil && m.desktop.image == nil)
    }

    @Test func expiredLimitsDoNotMakeSad() {
        let now = Date()
        let stale = Meter(label: "5시간", percent: 95, resetsAt: now.addingTimeInterval(-60))
        let live = Meter(label: "주간", percent: 40, resetsAt: now.addingTimeInterval(3600))
        #expect(PartnerMood.limitPercent([stale, live], now: now) == 40)
        #expect(PartnerMood.limitPercent([Meter(label: "모델", percent: 85)], now: now) == 85)  // 시각 모름 → 유지
        #expect(PartnerMood.limitPercent([], now: now) == 0)
    }

    // MARK: 바탕화면 창

    @MainActor @Test func offscreenOriginFallsBack() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 118, height: 128)
        let kept = CGPoint(x: 300, y: 200)
        #expect(PartnerPanel.place(origin: kept, size: size, screens: [main], main: main) == kept)
        let gone = CGPoint(x: 3000, y: 200)  // 떼어 낸 외부 모니터
        let sliver = CGPoint(x: 1440 - 10, y: 200)  // 10pt 만 걸치게 끌어냄
        let corner = CGPoint(x: 1440 - 118 - 24, y: 24)
        #expect(PartnerPanel.place(origin: gone, size: size, screens: [main], main: main) == corner)
        #expect(PartnerPanel.place(origin: sliver, size: size, screens: [main], main: main) == corner)
        #expect(PartnerPanel.place(origin: nil, size: size, screens: [main], main: main) == corner)
    }

    @MainActor @Test func sizeIsClamped() {
        #expect(PartnerPanel.windowSize(height: 10).height == 64)
        #expect(PartnerPanel.windowSize(height: 999).height == 256)
        let s = PartnerPanel.windowSize(height: 208)
        #expect(s.width == 192 && s.height == 208)
    }
}
