// ponytail: PokeTokenBar OAuthLimitsProvider.swift 에서 ClaudeAccountRoots 가 쓰는 두 선언만 발췌
struct AccountIdentity: Equatable, Sendable {
    let email: String
    let organizationName: String?
}

enum OAuthCredentialData {
    static let claudeKeychainService = "Claude Code-credentials"
}
