import Foundation

/// 코인 표기: ⓒ 1,000
/// 만 단위부터 K·M (34,200 → 34K, 2,400,000 → 2.4M). 소수는 줄인 수가 한 자리일 때만. 메뉴바와 `coinText`가 같이 쓴다
/// 좁은 개봉 배지는 `from: 1_000`으로 천 단위부터 줄인다 (SE 1,200 → 1.2K)
func shortCoins(_ n: Int, from: Int = 10_000) -> String {
    guard abs(n) >= from else { return n.formatted() }
    let oneDigit = String(n.magnitude).count % 3 == 1
    return n.formatted(.number.notation(.compactName).precision(.fractionLength(0...(oneDigit ? 1 : 0))).locale(Locale(identifier: "en_US")))
}

func coinText(_ n: Int) -> String { "ⓒ \(shortCoins(n))" }

/// 토큰 표기: 코인과 같은 줄임을 천 단위부터 (52.1M → 52M, 2,032.5M → 2B). 1,000 미만은 그대로
func shortTokens(_ n: Int) -> String { shortCoins(n, from: 1_000) }
