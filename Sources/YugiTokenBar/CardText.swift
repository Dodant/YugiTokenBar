import Foundation

extension CardInfo {
    /// "어둠 · ★7 · 드래곤족/융합/효과" (랭크·링크는 모든 언어에서 "Rank 4"·"Link 4", 펜듈럼은 "P스케일 2" 추가). 없는 칸은 뺀다.
    var summary: String {
        var parts: [String] = []
        if let attr { parts.append(attr) }
        if let levelText { parts.append(levelText) }
        if let scale { parts.append(String(localized: "P스케일 \(scale)")) }
        if let type { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    /// 업무 모드 개봉 줄의 둘째 줄: 몬스터는 "효과 · ★4 · 1600/1500"(종족을 뺀 분류 · 레벨/랭크/링크 · 공/수, 분류의 효과·일반은 뺀다), 마법·함정은 summary
    var workLine: String {
        guard let atk else { return summary }
        // 효과·일반은 너무 흔해서 뺀다 ("융합/효과" → "융합"). 카드 파일 언어마다 표기가 다르다
        let common: Set<Substring> = ["효과", "Effect", "効果", "일반", "Normal", "通常"]
        let kind = type.map { $0.split(separator: "/").dropFirst().filter { !common.contains($0) }.joined(separator: "/") }
        return [kind, levelText, def.map { "\(atk)/\($0)" } ?? atk]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var levelText: String? {
        level.map { level in
            switch levelKind {
            case .level: "★\(level)"
            case .rank: "Rank \(level)"
            case .link: "Link \(level)"
            }
        }
    }
}
