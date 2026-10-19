import Foundation

enum LocalizationArgument: Sendable {
    case int(Int)
    case text(String)

    fileprivate var value: String {
        switch self {
        case .int(let value): String(value)
        case .text(let value): value
        }
    }

    fileprivate var specifier: String {
        switch self {
        case .int: "lld"
        case .text: "@"
        }
    }
}

/// Matches the keys emitted for String(localized:) by the Swift compiler.
struct LocalizationKey: ExpressibleByStringInterpolation, Equatable, Sendable {
    let pattern: String
    let arguments: [String]

    init(stringLiteral value: String) {
        pattern = value
        arguments = []
    }

    init(stringInterpolation: StringInterpolation) {
        pattern = stringInterpolation.pattern
        arguments = stringInterpolation.arguments
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var pattern = ""
        var arguments: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            pattern.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }

        mutating func appendLiteral(_ literal: String) { pattern += literal }
        mutating func appendInterpolation(_ value: Int) {
            pattern += "%lld"
            arguments.append(String(value))
        }
        mutating func appendInterpolation<T>(_ value: T) {
            pattern += "%@"
            arguments.append("\(value)")
        }
    }
}

struct Localizer: Sendable {
    private let translations: [String: String]

    init(table: [String: String]) { translations = table }

    static func parseStrings(_ text: String) -> [String: String] {
        let entry = #/^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$/#
        func unescape(_ value: Substring) -> String {
            var result = ""
            var escaped = false
            for character in value {
                if escaped {
                    switch character {
                    case "n": result.append("\n")
                    case "\"", "\\": result.append(character)
                    default: result.append("\\"); result.append(character)
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    result.append(character)
                }
            }
            if escaped { result.append("\\") }
            return result
        }
        var table: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let match = line.trimmingCharacters(in: .whitespacesAndNewlines).wholeMatch(of: entry) else { continue }
            table[unescape(match.output.1)] = unescape(match.output.2)
        }
        return table
    }

    static func table(lang: String) -> [String: String] {
        guard let text = try? String(contentsOf: PlatformPaths.resource("\(lang).lproj/Localizable.strings"), encoding: .utf8) else { return [:] }
        return parseStrings(text)
    }

    func string(_ key: LocalizationKey) -> String {
        render(key.pattern, arguments: key.arguments)
    }

    func string(_ pattern: String, arguments: [LocalizationArgument]) -> String {
        render(pattern, arguments: arguments.map(\.value), specifiers: arguments.map(\.specifier))
    }

    private func render(_ pattern: String, arguments: [String], specifiers: [String]? = nil) -> String {
        let value = translations[pattern] ?? pattern
        var next = 0
        return value.replacing(#/%%|%(?:(\d+)\$)?(lld|@)/#) { match in
            if match.output.0 == "%%" { return "%" }
            let index: Int
            if let position = match.output.1 {
                guard let number = Int(position), number > 0 else { return String(match.output.0) }
                index = number - 1
            } else {
                index = next
                next += 1
            }
            guard arguments.indices.contains(index),
                  specifiers == nil || specifiers?[index] == String(match.output.2 ?? "") else {
                return String(match.output.0)
            }
            return arguments[index]
        }
    }

    static let shared = Localizer(table: table(lang: AppLanguage.current))
}

#if os(Linux)
extension String {
    init(localized key: LocalizationKey) { self = Localizer.shared.string(key) }
}

func L(_ key: StaticString, _ arguments: LocalizationArgument...) -> String {
    Localizer.shared.string(key.description, arguments: arguments)
}
#endif
