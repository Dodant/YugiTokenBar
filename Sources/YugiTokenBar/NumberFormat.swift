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

/// 1,000 미만은 그대로 (0.5K 를 "0K" 로 보이지 않게)
func shortTokens(_ n: Int) -> String {
    n < 1_000 ? "\(n)" : n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : String(format: "%.0fK", Double(n) / 1e3)
}
