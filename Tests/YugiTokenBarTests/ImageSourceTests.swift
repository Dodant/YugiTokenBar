import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct ImageSourceTests {
    @Test func normalPasscodeAndSizeMatrix() {
        // Konami cid 4007 belongs to a card whose image passcode is 89631139.
        for (size, prefix) in [(ImageSize.small, "cards_small"), (.full, "cards")] {
            let request = ImageSource.card(imageID: 89631139, size: size)
            #expect(request.key == "\(prefix)-89631139")
            #expect(request.fileName == "\(prefix)-89631139.jpg")
            #expect(request.url.absoluteString == "https://images.ygoprodeck.com/images/\(prefix)/89631139.jpg")
            #expect(request.maxPixels == nil)
            #expect(!request.url.absoluteString.contains("4007"))
        }
    }

    @Test func overframeMatrixSharesBothSizes() {
        #expect(ImageSource.overframe.count == 25)
        for (passcode, source) in ImageSource.overframe {
            for size in [ImageSize.small, .full] {
                let request = ImageSource.card(imageID: passcode, size: size, overframe: true)
                #expect(request.key == "overframe-\(passcode)")
                #expect(request.fileName == "overframe-\(passcode).jpg")
                #expect(request.url.absoluteString == source)
                #expect(request.maxPixels == 614)
            }
        }
    }

    @Test func lockedOverframesKeepNormalSizeSpecificSources() {
        for passcode in ImageSource.overframe.keys {
            for size in [ImageSize.small, .full] {
                let request = ImageSource.card(imageID: passcode, size: size)
                #expect(request.key == "\(size.rawValue)-\(passcode)")
                #expect(request.url.absoluteString == "https://images.ygoprodeck.com/images/\(size.rawValue)/\(passcode).jpg")
                #expect(request.maxPixels == nil)
            }
        }
    }

    @Test func unavailableOverframeFallsBackToNormalSource() {
        for size in [ImageSize.small, .full] {
            #expect(ImageSource.card(imageID: 89631139, size: size, overframe: true)
                    == ImageSource.card(imageID: 89631139, size: size))
        }
    }

    @Test func packKeepsExistingBasenameAndDecodeLimit() throws {
        let pack = Pack(pid: "p1", name: "p", date: "", cards: [], imageURL: "https://example.test/images/one.jpg")
        let request = try #require(ImageSource.pack(pack))
        #expect(request.key == "pack-one.jpg")
        #expect(request.fileName == "pack-one.jpg.jpg")
        #expect(request.maxPixels == 480)
        #expect(request.url.absoluteString == pack.imageURL)
        #expect(ImageSource.pack(Pack(pid: "p2", name: "p", date: "", cards: [], imageURL: nil)) == nil)
    }
}
