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
