import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 버전·저장소·번들 문서. 버전과 패치노트의 원본은 저장소 루트의 CHANGELOG.md(한국어) 하나다
/// (scripts/build-app.sh 가 맨 위 `## x.y.z` 를 Info.plist 에 넣는다). CHANGELOG.en.md·ja.md 는 그 번역이다.
enum AppInfo {
    static let repoURL = URL(string: "https://github.com/Dodant/YugiTokenBar")!
    static let releasesURL = URL(string: "https://github.com/Dodant/YugiTokenBar/releases/latest")!
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/Dodant/YugiTokenBar/releases/latest")!
    static let supportEmail = "ohho0506@gmail.com"

    /// 버그 신고 메일 (설정 › 정보 & 지원). 제목에 버전, 본문 끝에 버전·macOS·언어를 미리 적어 둔다
    static var bugReportURL: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = supportEmail
        c.queryItems = [
            URLQueryItem(name: "subject", value: "[YugiTokenBar] " + String(localized: "버그 신고") + " (\(versionText))"),
            URLQueryItem(name: "body", value: String(localized: "어떤 일이 있었는지 적어 주세요:") +
                "\n\n\n---\nYugiTokenBar \(versionText) · \(osName) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(AppLanguage.current)"),
        ]
        return c.url!
    }

    #if os(Linux)
    private static let osName = "Linux"
    #else
    private static let osName = "macOS"
    #endif

    /// 저장소 루트. `swift run`·테스트에서 번들 대신 읽는 파일(cards_XX.json·partner.png·문서)의 기준
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Sources/YugiTokenBar
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // 저장소 루트

    /// .app 이면 Info.plist 값, `swift run` 이면 nil
    static var bundleVersion: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
    static var buildNumber: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String }

    private static var developmentBuildText: String { String(localized: "개발 빌드") }

    #if os(Linux)
    /// Flatpak 빌드가 설치하는 version.txt (개발 실행에는 없다)
    static var installedVersion: String? { installedVersion(at: PlatformPaths.installedResource("version.txt")) }
    static func installedVersion(at url: URL?) -> String? {
        guard let url, let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : (value.hasPrefix("v") ? String(value.dropFirst()) : value)
    }
    static var versionText: String { installedVersion.map { "v\($0)" } ?? developmentBuildText }
    static var currentVersion: String {
        installedVersion ?? topVersion(ofChangelog: text("CHANGELOG", repoPath: "CHANGELOG.md")) ?? "0"
    }
    #else
    static var versionText: String {
        bundleVersion.map { "v\($0) (\(buildNumber ?? "?"))" } ?? developmentBuildText
    }

    /// 업데이트 비교에 쓰는 현재 버전. 개발 빌드는 로컬 CHANGELOG 기준.
    static var currentVersion: String { bundleVersion ?? topVersion(ofChangelog: text("CHANGELOG", repoPath: "CHANGELOG.md")) ?? "0" }
    #endif

    /// 앱 언어의 패치노트: ko → CHANGELOG.md, en·ja → CHANGELOG.en.md·CHANGELOG.ja.md
    static var changelog: String { changelog(lang: AppLanguage.current) }
    static func changelog(lang: String) -> String {
        let name = lang == "ko" ? "CHANGELOG" : "CHANGELOG.\(lang)"
        return text(name, repoPath: name + ".md")
    }
    /// 라이선스 창: PokeTokenBar 고지(NOTICE) 뒤에 Sparkle LICENSE 전문
    #if os(Linux)
    /// Linux 라이선스 창: NOTICE 뒤에 패키지별 LICENSE. 설치본은 licenses/ 폴더, 개발 실행은 .build-linux/checkouts.
    static var license: String { license(installed: PlatformPaths.installedResource("licenses"),
                                         checkouts: repoRoot.appendingPathComponent(".build-linux/checkouts")) }
    static func license(installed: URL?, checkouts: URL) -> String {
        var parts = [text("NOTICE", repoPath: "Sources/YugiTokenBar/Usage/NOTICE.md")]
        let fm = FileManager.default
        func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
        if let installed, let names = try? fm.contentsOfDirectory(atPath: installed.path) {
            for name in names.sorted() {
                let url = installed.appendingPathComponent(name)
                if let body = read(url) { parts.append("## \(url.deletingPathExtension().lastPathComponent)\n\n\(body)") }
            }
        } else {
            for package in ["adwaita-swift", "meta", "meta-sqlite", "levenshtein-transformations", "SQLite.swift",
                            "CSQLite", "swift-crypto", "swift-asn1", "XMLCoder"] {
                let dir = checkouts.appendingPathComponent(package)
                guard let file = (try? fm.contentsOfDirectory(atPath: dir.path))?.sorted()
                    .first(where: { $0.uppercased().hasPrefix("LICENSE") }),
                      let body = read(dir.appendingPathComponent(file)) else { continue }
                parts.append("## \(package)\n\n\(body)")
            }
        }
        return parts.joined(separator: "\n\n")
    }
    #else
    static var license: String {
        text("NOTICE", repoPath: "Sources/YugiTokenBar/Usage/NOTICE.md") + "\n\n## Sparkle\n\n"
            + text("Sparkle-LICENSE", repoPath: ".build/artifacts/sparkle/Sparkle/LICENSE")
    }
    #endif

    /// Sparkle 을 켤까: 번들 Info.plist 에 EdDSA 공개 키가 있을 때만 (swift run·키 없는 빌드는 GitHub 확인)
    static func sparkleEnabled(info: [String: Any]? = Bundle.main.infoDictionary) -> Bool {
        (info?["SUPublicEDKey"] as? String).map { !$0.isEmpty } ?? false
    }

    private static func text(_ name: String, repoPath: String) -> String {
        let url = PlatformPaths.installedResource(name + ".md") ?? repoRoot.appendingPathComponent(repoPath)
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

    /// 게시된 정식 릴리스만 확인한다(main의 미배포 변경·초안·프리릴리스 제외).
    static func releaseVersion(from data: Data) -> String? {
        struct Release: Decodable {
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease else { return nil }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        return version
    }

    static func fetchLatestVersion() async -> String? {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("YugiTokenBar", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return releaseVersion(from: data)
    }
}
