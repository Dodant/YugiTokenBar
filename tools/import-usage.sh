#!/bin/bash
# PokeTokenBar(MIT) 토큰 읽기 코드를 고정 커밋에서 복사하고, 이 앱에 없는 의존성을 패치한다.
# 저장소 루트에서 실행: bash tools/import-usage.sh
set -euo pipefail
SRC=${PTB_REPO:-$HOME/remote-claude-projects/code/PokeTokenBar-carryover}
REV=de617e3
DST=Sources/YugiTokenBar/Usage
mkdir -p "$DST"
for f in LocalUsageReader AppLog AppEnv BinaryLocator ClaudeAccountRoots CustomScanRoots Models ModelPricing UsageEnvironment LogRepeatSuppressor UsageCost \
         OAuthLimitsProvider KeychainAccess ProcessRunner CodexRateLimitsProvider \
         UsageProvider LocalAdditionalUsageProvider LocalAsideUsageReader LocalAntigravityUsageReader CursorUsageAPI AppStatePaths \
         LocalUsageCache; do
  git -C "$SRC" show "$REV:Sources/PokeTokenBar/Core/$f.swift" > "$DST/$f.swift"
done
python3 - "$DST" <<'PY'
import re, sys
d = sys.argv[1]
def edit(name, fn):
    p = f"{d}/{name}.swift"; s = open(p).read(); t = fn(s)
    assert t != s, f"{name}: 패치 대상 없음"
    open(p, "w").write(t)
# UI 문자열(L) 의존 메서드 제거
edit("UsageCost", lambda s: re.sub(r"\n    func text\(_ l: L.*?\n    }\n\n    func explanation\(_ l: L\).*?\n    }\n", "\n", s, flags=re.S))
# 설정 화면용 추가 provider 루트 제거 (이 앱은 해당 리더를 복사하지 않음)
edit("CustomScanRoots", lambda s: re.sub(r'        case "antigravity":.*?(?=        case "pi":)', "", s, flags=re.S))
# Cursor API 캐시를 이 앱 세이브 폴더에 둔다
edit("AppStatePaths", lambda s: s.replace('"PTB_STATE_DIR"', '"YTB_STATE_DIR"').replace('appendingPathComponent("PokeTokenBar")', 'appendingPathComponent("YugiTokenBar")'))
# 파일별 사용량 캐시를 이 앱 세이브 폴더(YTB_STATE_DIR 를 따른다)에 둔다
edit("LocalUsageCache", lambda s: re.sub(r'(private static let defaultFileURL: URL = \{\n).*?(\n    \}\(\))',
     r'\1        AppStatePaths.directory().appendingPathComponent("usage-cache.json")\2', s, flags=re.S))
edit("AppLog", lambda s: s.replace("PokeTokenBar.log", "YugiTokenBar.log").replace('"poketokenbar.log"', '"yugitokenbar.log"'))
# 쓰는 중인 Claude 세션 파일은 TodayUsageReader 가 새로 붙은 줄만 읽는다: 줄 파서를 열고, 파일별 캐시가 그 파일을 건너뛰게 한다
edit("LocalUsageReader", lambda s: s.replace("    private static func parseClaudeLine(", "    static func parseClaudeLine("))
edit("LocalUsageCache", lambda s: s.replace("func claudeEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {",
     "func claudeEntries(modifiedSince: Date, skipping: Set<String> = []) -> [LocalUsageReader.Entry] {")
     .replace("all += collect(root: root, since: modifiedSince, cache: &claudeCache, annotate:",
              "all += collect(root: root, since: modifiedSince, cache: &claudeCache,\n                           include: skipping.isEmpty ? nil : { !skipping.contains($0.path) }, annotate:"))
# 매번 같은 Cursor API 상태 줄은 바뀔 때와 1시간마다만 남긴다
edit("CursorUsageAPI", lambda s: s
     .replace('AppLog.write("cursor api: session token ready', 'AppLog.writeIfChanged("cursor-api-token", "cursor api: session token ready')
     .replace('AppLog.write("cursor api: fetched ', 'AppLog.writeIfChanged("cursor-api-fetch", "cursor api: fetched ')
     .replace('AppLog.write("cursor api: fetch failed — ', 'AppLog.writeIfChanged("cursor-api-fetch", "cursor api: fetch failed — ')
     .replace('AppLog.write("cursor api: fetch failed and no cache")', 'AppLog.writeIfChanged("cursor-api-fallback", "cursor api: fetch failed and no cache")'))
# Linux 이식 패치는 원본을 다시 가져올 때마다 같은 결과를 만든다.
def replace_exact(s, before, after):
    assert s.count(before) == 1, f"패치 대상 개수 오류: {before[:80]!r}"
    return s.replace(before, after)

def platform_import(s, module, fallback):
    return replace_exact(s, f"import {module}\n",
        f"#if canImport({module})\nimport {module}\n#else\nimport {fallback}\n#endif\n")

# 타임아웃이 stdout 을 닫을 때 ObjC 예외 대신 읽기 오류로 처리한다.
edit("BinaryLocator", lambda s: replace_exact(s,
    "            box.data = handle.readDataToEndOfFile()",
    "            box.data = (try? handle.readToEnd()) ?? Data()"))

edit("OAuthLimitsProvider", lambda s: "#if os(macOS)\n" + s.rstrip() + "\n#endif\n")
edit("ClaudeAccountRoots", lambda s: replace_exact(
    platform_import(s, "CryptoKit", "Crypto"),
    "    static func keychainServices(for root: URL) -> [String] {\n"
    "        let path = root.standardizedFileURL.path\n"
    "        return [path, path + \"/\"].map { \"\\(OAuthCredentialData.claudeKeychainService)-\\(hashPrefix($0))\" }\n"
    "    }\n",
    "    #if os(macOS)\n"
    "    static func keychainServices(for root: URL) -> [String] {\n"
    "        let path = root.standardizedFileURL.path\n"
    "        return [path, path + \"/\"].map { \"\\(OAuthCredentialData.claudeKeychainService)-\\(hashPrefix($0))\" }\n"
    "    }\n"
    "    #endif\n"))
edit("CursorUsageAPI", lambda s: replace_exact(
    platform_import(s, "CryptoKit", "Crypto"), "import Foundation\n",
    "import Foundation\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n"))
edit("CustomScanRoots", lambda s: platform_import(s, "Darwin", "Glibc"))
for name in ("LocalAdditionalUsageProvider", "LocalAsideUsageReader", "LocalAntigravityUsageReader"):
    edit(name, lambda s: platform_import(s, "SQLite3", "CSQLite"))

def patch_cursor_roots(s):
    s = replace_exact(s, "    // MARK: Cursor database\n", """    // MARK: Cursor database

    /// YugiTokenBar 패치: OS 별 Cursor 기본 데이터 폴더. Linux 는 ~/.config (설계 문서 5.3)
    static func cursorStandardRoots(home: URL) -> [URL] {
        #if os(Linux)
        ["Cursor", "Cursor Nightly"].map { home.appendingPathComponent(".config/\\($0)/User/globalStorage") }
        #else
        ["Cursor", "Cursor Nightly"].map { home.appendingPathComponent("Library/Application Support/\\($0)/User/globalStorage") }
        #endif
    }
""")
    s = replace_exact(s, """        environmentPaths("CURSOR_DATA_DIR") ?? [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Cursor Nightly/User/globalStorage"),
        ]""", """        environmentPaths("CURSOR_DATA_DIR")
            ?? Self.cursorStandardRoots(home: FileManager.default.homeDirectoryForCurrentUser)""")
    return replace_exact(s, """        let curated = environmentPaths("CURSOR_DATA_DIR") ?? [
            home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage"),
            home.appendingPathComponent("Library/Application Support/Cursor Nightly/User/globalStorage"),
        ]""", """        let curated = environmentPaths("CURSOR_DATA_DIR") ?? Self.cursorStandardRoots(home: home)""")
edit("LocalAdditionalUsageProvider", patch_cursor_roots)

def patch_cache_zlib(s):
    s = replace_exact(s,
        "        let data = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw",
        "        #if canImport(Darwin)\n        let data = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw\n        #else\n        let data = raw\n        #endif")
    return replace_exact(s,
        "            let out = (try? (data as NSData).compressed(using: .zlib) as Data) ?? data",
        "            #if canImport(Darwin)\n            let out = (try? (data as NSData).compressed(using: .zlib) as Data) ?? data\n            #else\n            let out = data\n            #endif")
edit("LocalUsageCache", patch_cache_zlib)
edit("AppLog", lambda s: replace_exact(s,
    "        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]\n"
    "            .appendingPathComponent(\"Logs\")",
    "        #if os(Linux)\n"
    "        let dir = AppStatePaths.directory()  // YugiTokenBar 패치: Linux 는 ~/Library 가 없어 세이브 폴더에 둔다\n"
    "        #else\n"
    "        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]\n"
    "            .appendingPathComponent(\"Logs\")\n"
    "        #endif"))
edit("AppEnv", lambda s: replace_exact(s,
    """    static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }
""",
    """    static var isBundledApp: Bool {
        #if os(Linux)
        isInstalledRun(executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        #else
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
        #endif
    }

    #if os(Linux)
    /// YugiTokenBar 패치: Linux 는 번들이 없어 실행 파일 위치로 본다. `/.build`(swift run·swift test·.build-linux) 아래면 개발 실행
    static func isInstalledRun(executablePath: String) -> Bool { !executablePath.contains("/.build") }
    #endif
"""))
PY
