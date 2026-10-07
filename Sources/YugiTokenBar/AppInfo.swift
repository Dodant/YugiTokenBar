import Foundation

/// 버전·저장소·번들 문서. 버전과 패치노트의 원본은 저장소 루트의 CHANGELOG.md 하나다
/// (scripts/build-app.sh 가 맨 위 `## x.y.z` 를 Info.plist 에 넣는다).
enum AppInfo {
    static let repoURL = URL(string: "https://github.com/Dodant/YugiTokenBar")!
    static let latestChangelogURL = URL(string: "https://raw.githubusercontent.com/Dodant/YugiTokenBar/main/CHANGELOG.md")!

    /// 저장소 루트. `swift run`·테스트에서 번들 대신 읽는 파일(cards_XX.json·partner.png·문서)의 기준
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Sources/YugiTokenBar
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // 저장소 루트

    /// .app 이면 Info.plist 값, `swift run` 이면 nil
    static var bundleVersion: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
    static var buildNumber: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String }

    static var versionText: String {
        bundleVersion.map { "v\($0) (\(buildNumber ?? "?"))" } ?? String(localized: "개발 빌드")
    }

    /// 업데이트 비교에 쓰는 현재 버전. 개발 빌드는 로컬 CHANGELOG 기준.
    static var currentVersion: String { bundleVersion ?? topVersion(ofChangelog: changelog) ?? "0" }

    static var changelog: String { text("CHANGELOG", repoPath: "CHANGELOG.md") }
    static var license: String { text("NOTICE", repoPath: "Sources/YugiTokenBar/Usage/NOTICE.md") }

    private static func text(_ name: String, repoPath: String) -> String {
        let url = Bundle.main.url(forResource: name, withExtension: "md") ?? repoRoot.appendingPathComponent(repoPath)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? String(localized: "\(repoPath)를 읽지 못했어요.")
    }

    /// CHANGELOG 의 첫 `## x.y.z` 제목. build-app.sh 의 awk 와 같은 규칙.
    static func topVersion(ofChangelog text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix("## ") {
            let token = line.dropFirst(3).split(separator: " ").first.map(String.init) ?? ""
            if token.first?.isNumber == true { return token }
        }
        return nil
    }

    /// a 가 b 보다 높은 버전인가 ("0.10.0" > "0.9.1" 숫자 비교)
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// main 브랜치 CHANGELOG 의 최신 버전. 실패하면 nil.
    // ponytail: 릴리스 없이 main 기준으로 비교. 릴리스를 만들기 시작하면 Releases API 로 바꿀 것
    static func fetchLatestVersion() async -> String? {
        let request = URLRequest(url: latestChangelogURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return topVersion(ofChangelog: String(decoding: data, as: UTF8.self))
    }
}
