import Foundation

/// 앱 언어 설정. 고른 언어는 앱 도메인 AppleLanguages 에 넣어, 다음 실행부터 macOS 가 번들 현지화(lproj)와
/// Locale.current 를 그 언어로 고른다(재시작 후 반영). 카드 파일(cards_XX.json)도 같은 언어를 쓴다.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ko, en, ja

    var id: String { rawValue }

    /// 설정 메뉴 이름. 언어 이름은 그 언어로 쓰고 번역하지 않는다
    var title: String {
        switch self {
        case .system: String(localized: "시스템 따르기")
        case .ko: "한국어"
        case .en: "English"
        case .ja: "日本語"
        }
    }

    /// 지원 언어. 맨 앞(en)이 지원하지 않는 시스템 언어의 대체다 (Info.plist CFBundleDevelopmentRegion 도 en)
    static let supported = ["en", "ko", "ja"]

    /// 사용자 언어 목록(nil 이면 앱 AppleLanguages → 시스템 순)에서 처음 지원하는 언어, 없으면 en
    static func resolve(_ preferences: [String]? = nil) -> String {
        Bundle.preferredLocalizations(from: supported, forPreferences: preferences).first ?? "en"
    }

    /// 이번 실행의 언어. 실행 중에 설정을 바꿔도 그대로다
    static let current = resolve()

    private static let key = "appLanguage"

    /// 설정 메뉴에 보일 선택. AppleLanguages 는 시스템 전체 값이 비쳐 보여서 따로 저장한 키를 읽는다
    static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: key).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    static func store(_ language: AppLanguage, in defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: key)
        if language == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    /// 이번 실행을 시작할 때의 선택 (설정에서 바꾸면 "다시 시작하면 적용돼요"를 보이는 기준)
    static let launchChoice = stored()
}
