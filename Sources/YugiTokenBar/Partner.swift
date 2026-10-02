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
        return PartnerSheet(url: url)
    }
}

/// 파트너 동작 기준값. 게임 밸런스가 아니라서 `Balance`에 두지 않는다.
enum PartnerTuning {
    static let fps = 8.0
    /// Claude·Codex 공식 한도 중 가장 높은 %가 이 이상이면 시무룩
    static let sadPercent = 80.0
    static let flyTokensPerMinute = 100_000
    static let flapTokensPerMinute = 1_000
    /// 비행 행을 한 방향으로 몇 번 돌고 방향을 바꾸나
    static let flyLoops = 2
    /// 대기: 깜빡임 뒤 첫 프레임으로 멈춰 있는 틱 (3초)
    static let idleHoldTicks = Int(3 * fps)
    /// 대기가 이만큼(20초) 이어지면 두리번 1회
    static let lookAroundTicks = Int(20 * fps)
    /// 메뉴바 깜빡임 주기 (4초)
    static let menuBlinkTicks = Int(4 * fps)
    /// 바탕화면 파트너 높이(pt). 설정 슬라이더는 16 단위.
    static let sizes = 64.0...256.0
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

    /// 직전 갱신과의 합계 차이 ÷ 경과 분(1분 미만은 1분으로 쳐서 튀지 않게). 첫 갱신·날짜 변경·감소는 0.
    static func tokensPerMinute(from previous: UsageSample?, to current: UsageSample) -> Int {
        guard let previous, previous.date == current.date, current.total > previous.total else { return 0 }
        let minutes = max(1, current.at.timeIntervalSince(previous.at) / 60)
        return Int(Double(current.total - previous.total) / minutes)
    }
}

/// 파트너 애니메이션 진행 (1틱 = 1/fps 초). 한 번 재생 동작은 큐로 받아 기준 상태를 잠시 덮는다.
struct PartnerPlayer: Sendable {
    private(set) var mood: PartnerMood = .idle
    private(set) var anim: PartnerAnim = .idle
    private(set) var frame = 0
    private(set) var queue: [PartnerAnim] = []
    /// 대기 첫 프레임으로 멈춰 있을 남은 틱
    private var hold = 0
    /// 지금 동작을 몇 번 돌았나 (비행 방향 전환용)
    private var loops = 0
    /// 대기가 이어진 틱 (두리번용)
    private var idleTicks = 0

    mutating func setMood(_ next: PartnerMood) {
        guard next != mood else { return }
        mood = next
        idleTicks = 0
        if hold > 0 { hold = 0; advance() }  // 멈춰 있던 대기는 바로 새 상태로
    }

    /// 한 번 재생. 같은 동작이 이미 큐에 있으면 넣지 않는다. 멈춰 있던 대기는 바로 끊는다.
    mutating func play(_ a: PartnerAnim) {
        guard !queue.contains(a) else { return }
        queue.append(a)
        if hold > 0 { hold = 0; advance() }
    }

    /// 큐를 비우고 바로 재생 (클릭).
    mutating func interrupt(_ a: PartnerAnim) {
        queue.removeAll()
        hold = 0
        start(a)
    }

    mutating func tick() {
        if mood == .idle { idleTicks += 1 }
        if hold > 0 { hold -= 1; return }
        frame += 1
        guard frame >= anim.frameCount else { return }
        loops += 1
        advance()
    }

    /// 지금 동작이 한 바퀴 끝났을 때: 큐 → 기준 상태
    private mutating func advance() {
        if !queue.isEmpty { start(queue.removeFirst()); return }
        switch mood {
        case .sad: start(.sad)
        case .flap: start(.flap)
        case .fly:
            if anim != .flyRight && anim != .flyLeft { start(.flyRight) }
            else if loops >= PartnerTuning.flyLoops { start(anim == .flyRight ? .flyLeft : .flyRight) }
            else { frame = 0 }
        case .idle:
            if idleTicks >= PartnerTuning.lookAroundTicks { idleTicks = 0; start(.lookAround) }
            else { start(.idle); hold = PartnerTuning.idleHoldTicks }
        }
    }

    private mutating func start(_ a: PartnerAnim) {
        if a != anim { loops = 0 }
        anim = a
        frame = 0
    }

    /// 메뉴바 대기 행 프레임: menuBlinkTicks 마다 깜빡임 한 번, 나머지는 첫 프레임 (라벨을 다시 그리는 횟수를 줄이려고).
    static func menuFrame(tick: Int) -> Int {
        let t = tick % PartnerTuning.menuBlinkTicks
        return t < PartnerAnim.idle.frameCount ? t : 0
    }
}
