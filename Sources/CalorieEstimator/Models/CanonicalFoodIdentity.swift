import Foundation

/// A stable, locale-independent recipe identifier.
public struct RecipeID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// A stable, locale-independent ingredient identifier.
public struct IngredientID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

enum FoodNameNormalizer {
    static func normalize(_ value: String) -> String {
        let canonical = value.precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        let characters = canonical.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(characters)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}
