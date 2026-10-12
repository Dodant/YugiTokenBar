import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct AppInfoTests {
    @Test func publishedReleaseVersion() {
        let data = Data(#"{"tag_name":"v0.5.8","draft":false,"prerelease":false}"#.utf8)
        #expect(AppInfo.releaseVersion(from: data) == "0.5.8")
        #expect(AppInfo.isNewer("0.10.0", than: "0.9.9"))
    }

    @Test func unpublishedOrInvalidReleaseIsIgnored() {
        for json in [
            #"{"tag_name":"v0.5.8","draft":true,"prerelease":false}"#,
            #"{"tag_name":"v0.5.8","draft":false,"prerelease":true}"#,
            #"{"tag_name":"v0.5.8-beta","draft":false,"prerelease":false}"#,
            #"{"tag_name":"v0..8","draft":false,"prerelease":false}"#,
            #"{"message":"Not Found"}"#,
        ] {
            #expect(AppInfo.releaseVersion(from: Data(json.utf8)) == nil)
        }
    }
}
