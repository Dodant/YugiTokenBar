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
}
