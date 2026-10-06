import AppKit
import ImageIO

/// 파트너 「날개 크리보」 스프라이트 시트의 동작 행. rawValue = 시트의 행 번호(0부터).
enum PartnerAnim: Int, CaseIterable, Sendable {
    case idle, flyRight, flyLeft, wave, flap, sad, excited, puzzled, lookAround

    var frameCount: Int { Self.frameCounts[rawValue] }
    private static let frameCounts = [6, 8, 8, 4, 5, 8, 6, 6, 6]
}

/// `Resources/partner.png`(셀 192×208, 8열 × 9행)을 동작별 프레임으로 자른 것.
struct PartnerSheet {
    static let cell = CGSize(width: 192, height: 208)
    static let columns = 8
    let frames: [PartnerAnim: [CGImage]]

    /// 이미지가 아니거나 크기가 격자(1536×1872)와 다르면 nil.
    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == Int(Self.cell.width) * Self.columns,
              image.height == Int(Self.cell.height) * PartnerAnim.allCases.count else { return nil }
        var frames: [PartnerAnim: [CGImage]] = [:]
        for anim in PartnerAnim.allCases {
            frames[anim] = (0..<anim.frameCount).compactMap { col in
                image.cropping(to: CGRect(x: CGFloat(col) * Self.cell.width, y: CGFloat(anim.rawValue) * Self.cell.height,
                                          width: Self.cell.width, height: Self.cell.height))
            }
        }
        self.frames = frames
    }

    /// .app 안에서는 Contents/Resources/partner.png, `swift run`·테스트에서는 저장소의 Resources/partner.png.
    static func bundled() -> PartnerSheet? {
        let url = Bundle.main.url(forResource: "partner", withExtension: "png")
            ?? CardDB.repoCardsURL.deletingLastPathComponent().appendingPathComponent("partner.png")
        let sheet = PartnerSheet(url: url)
        if sheet == nil { AppLog.write("partner.png 를 읽지 못해 파트너를 끕니다") }
        return sheet
    }
}

/// 파트너 동작 기준값. 게임 밸런스가 아니라서 `Balance`에 두지 않는다.
enum PartnerTuning {
    static let fps = 5.0
    /// Claude·Codex 공식 한도 중 가장 높은 %가 이 이상이면 시무룩
    static let sadPercent = 80.0
    static let flyTokensPerMinute = 100_000
    static let flapTokensPerMinute = 1_000
    /// 기준 동작을 한 바퀴 재생한 뒤 첫 프레임에서 쉬는 시간(초). 범위 안에서 무작위.
    static func rest(_ mood: PartnerMood) -> ClosedRange<Double> {
        switch mood {
        case .idle: 3...8
        case .flap: 2...5
        case .fly: 1...3
        case .sad: 4...8
        }
    }
    /// 대기가 이만큼(초, 무작위) 이어지면 두리번 1회
    static let lookAroundEvery = 20.0...40.0
    /// 메뉴바 깜빡임 주기 (4초)
    static let menuBlinkTicks = Int(4 * fps)
    /// 바탕화면 파트너 높이(pt)와 설정 슬라이더 단위
    static let sizes = 64.0...256.0
    static let sizeStep = 16.0
}

/// 갱신(60초) 때 읽은 오늘 토큰 합계
struct UsageSample: Equatable, Sendable {
    let date: String
    let total: Int
    let at: Date
}

/// 기준 상태. 매 갱신마다 다시 정한다.
enum PartnerMood: Equatable, Sendable {
    case idle, flap, fly, sad

    /// 위에서부터 먼저 맞는 것: 한도 → 많은 사용량 → 사용량 → 대기
    static func base(tokensPerMinute: Int, limitPercent: Double) -> PartnerMood {
        if limitPercent >= PartnerTuning.sadPercent { return .sad }
        if tokensPerMinute >= PartnerTuning.flyTokensPerMinute { return .fly }
        if tokensPerMinute >= PartnerTuning.flapTokensPerMinute { return .flap }
        return .idle
    }

    /// 시무룩 판정에 쓰는 한도 %: 초기화 시각이 지난 한도(조회 실패로 남은 옛 값)는 뺀다.
    static func limitPercent(_ meters: [Meter], now: Date = Date()) -> Double {
        meters.filter { ($0.resetsAt ?? .distantFuture) > now }.map(\.percent).max() ?? 0
    }

    /// 이 상태의 기준 동작인가 (쉬기 여부 판단용)
    func plays(_ anim: PartnerAnim) -> Bool {
        switch self {
        case .idle: anim == .idle || anim == .lookAround
        case .flap: anim == .flap
        case .fly: anim == .flyRight || anim == .flyLeft
        case .sad: anim == .sad
        }
    }

    /// 직전 갱신과의 합계 차이 ÷ 경과 분(1분 미만은 1분으로 쳐서 튀지 않게). 첫 갱신·날짜 변경·감소는 0.
    static func tokensPerMinute(from previous: UsageSample?, to current: UsageSample) -> Int {
        guard let previous, previous.date == current.date, current.total > previous.total else { return 0 }
        let minutes = max(1, current.at.timeIntervalSince(previous.at) / 60)
        return Int(Double(current.total - previous.total) / minutes)
    }
}

/// 파트너 애니메이션 진행 (1틱 = 1/fps 초). 기준 동작은 한 바퀴마다 무작위로 쉬고,
/// 한 번 재생 동작은 큐로 받아 기준 상태를 잠시 덮는다(끝나면 쉬지 않고 기준 상태로).
struct PartnerPlayer: Sendable {
    private(set) var mood: PartnerMood = .idle
    private(set) var anim: PartnerAnim = .idle
    private(set) var frame = 0
    private(set) var queue: [PartnerAnim] = []
    /// 첫 프레임으로 쉬고 있을 남은 틱
    private var hold = 0
    /// 지금 동작이 한 번 재생(큐·클릭)인가
    private var oneShot = false
    /// 대기가 이어진 틱과, 두리번까지 남은 기준 (틱)
    private var idleTicks = 0
    private var lookAroundAt: Int
    private var rng: any RandomNumberGenerator & Sendable

    init(rng: any RandomNumberGenerator & Sendable = SystemRandomNumberGenerator()) {
        self.rng = rng
        lookAroundAt = 0
        lookAroundAt = randomTicks(PartnerTuning.lookAroundEvery)
    }

    /// 기준 동작 사이에 쉬는 중
    var resting: Bool { hold > 0 }

    mutating func setMood(_ next: PartnerMood) {
        guard next != mood else { return }
        mood = next
        idleTicks = 0
        if hold > 0 { hold = 0; advance() }  // 멈춰 있던 대기는 바로 새 상태로
    }

    /// 한 번 재생. 같은 동작이 이미 큐에 있거나 한 번 재생 중이면 넣지 않는다. 멈춰 있던 대기는 바로 끊는다.
    mutating func play(_ a: PartnerAnim) {
        guard !queue.contains(a), !(oneShot && anim == a) else { return }
        queue.append(a)
        if hold > 0 { hold = 0; advance() }
    }

    /// 큐를 비우고 바로 재생 (클릭).
    mutating func interrupt(_ a: PartnerAnim) {
        queue.removeAll()
        hold = 0
        start(a, oneShot: true)
    }

    mutating func tick() {
        if mood == .idle { idleTicks += 1 }
        if hold > 0 {
            hold -= 1
            if hold == 0 { advance() }
            return
        }
        frame += 1
        guard frame >= anim.frameCount else { return }
        // 한 번 재생·큐·상태가 바뀐 뒤의 옛 동작이면 바로 다음으로, 지금 상태의 동작이면 첫 프레임에서 쉰다
        if oneShot || !queue.isEmpty || !mood.plays(anim) { advance(); return }
        frame = 0
        hold = max(1, randomTicks(PartnerTuning.rest(mood)))
    }

    /// 다음 동작: 큐 → 기준 상태
    private mutating func advance() {
        if !queue.isEmpty { start(queue.removeFirst(), oneShot: true); return }
        switch mood {
        case .sad: start(.sad)
        case .flap: start(.flap)
        case .fly: start(anim == .flyRight ? .flyLeft : .flyRight)
        case .idle:
            if idleTicks >= lookAroundAt {
                idleTicks = 0
                lookAroundAt = randomTicks(PartnerTuning.lookAroundEvery)
                start(.lookAround)
            } else {
                start(.idle)
            }
        }
    }

    private mutating func start(_ a: PartnerAnim, oneShot: Bool = false) {
        anim = a
        frame = 0
        self.oneShot = oneShot
    }

    private mutating func randomTicks(_ seconds: ClosedRange<Double>) -> Int {
        Int((Double.random(in: seconds, using: &rng) * PartnerTuning.fps).rounded())
    }

    /// 메뉴바 대기 행 프레임: menuBlinkTicks 마다 깜빡임 한 번, 나머지는 첫 프레임 (라벨을 다시 그리는 횟수를 줄이려고).
    static func menuFrame(tick: Int) -> Int {
        let t = tick % PartnerTuning.menuBlinkTicks
        return t < PartnerAnim.idle.frameCount ? t : 0
    }
}

extension PartnerAnim {
    /// 세이브가 바뀔 때 한 번 재생할 동작: 새로 해금·무료 카드나 무료 팩이 늘어남 → 설렘, 코인이 팩 가격을 넘어섬 → 손짓.
    static func reactions(from old: GameState, to new: GameState, newlyUnlocked: Bool) -> [PartnerAnim] {
        var result: [PartnerAnim] = []
        if newlyUnlocked || new.pendingFree > old.pendingFree || new.freePacks > old.freePacks { result.append(.excited) }
        if old.coins < Balance.packPrice, new.coins >= Balance.packPrice { result.append(.wave) }
        return result
    }
}

/// 화면에 그릴 프레임 하나. 메뉴바와 바탕화면이 따로 가져서, 바탕화면이 매 프레임 바뀌어도 메뉴바 라벨은 깜빡일 때만 다시 그린다.
@MainActor final class FrameBox: ObservableObject {
    @Published var image: NSImage?
}

/// 파트너 애니메이션을 타이머로 돌리고 프레임을 내보낸다. 시트를 못 읽으면 아무것도 하지 않는다(메뉴바는 카드 아이콘).
@MainActor final class PartnerModel {
    let desktop = FrameBox()
    let menu = FrameBox()
    private var player = PartnerPlayer()
    private let frames: [PartnerAnim: [NSImage]]
    private let menuFrames: [NSImage]
    private var timer: Timer?
    private var ticks = 0

    init(sheet: PartnerSheet? = .bundled()) {
        let images = sheet?.frames ?? [:]
        frames = images.mapValues { $0.map { NSImage(cgImage: $0, size: PartnerSheet.cell) } }
        // 메뉴바: 셀 위쪽 빈 공간(대기 행 그림은 y 54~203)을 잘라 세로 가운데에 오게 하고, 숫자와 살짝 띄운다
        let crop = CGRect(x: 0, y: 50, width: PartnerSheet.cell.width, height: 157)
        let height = 18.0, gap = 3.0
        let iconSize = NSSize(width: height * crop.width / crop.height, height: height)
        menuFrames = (images[.idle] ?? []).compactMap { $0.cropping(to: crop) }.map { cg in
            NSImage(size: NSSize(width: iconSize.width + gap, height: height), flipped: false) { _ in
                NSImage(cgImage: cg, size: iconSize).draw(in: NSRect(origin: .zero, size: iconSize))
                return true
            }
        }
    }

    var isReady: Bool { !menuFrames.isEmpty }

    /// 해금되면 부른다. 여러 번 불러도 타이머는 하나.
    func start() {
        guard isReady, timer == nil else { return }
        render()
        let timer = Timer(timeInterval: 1 / PartnerTuning.fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }  // RunLoop.main 에서 불린다
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)  // 메뉴·팝오버가 열려 있어도 돈다
        self.timer = timer
    }

    func setMood(_ mood: PartnerMood) { player.setMood(mood); render() }
    /// 해금 전(타이머 꺼짐)의 반응은 버린다. 쌓아 두면 해금 순간 한꺼번에 재생된다.
    func play(_ anim: PartnerAnim) { guard timer != nil else { return }; player.play(anim); render() }
    func interrupt(_ anim: PartnerAnim) { player.interrupt(anim); render() }

    private func tick() {
        player.tick()
        ticks += 1
        render()
    }

    /// 바뀐 프레임만 내보낸다 (같은 이미지면 @Published 를 건드리지 않는다).
    private func render() {
        guard isReady else { return }
        let image = frames[player.anim]?[player.frame]
        if desktop.image !== image { desktop.image = image }
        let icon = menuFrames[PartnerPlayer.menuFrame(tick: ticks)]
        if menu.image !== icon { menu.image = icon }
    }
}
