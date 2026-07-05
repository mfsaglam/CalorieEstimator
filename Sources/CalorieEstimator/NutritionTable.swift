import Foundation

/// Supplies a food's typical calories per 100 grams from a known data source,
/// independent of any language model.
///
/// This is the pluggable seam that lets ``CalorieEstimator`` resolve nutrition
/// numbers from real data (a bundled table, a remote database, …) and fall back
/// to the model only when the food isn't found.
public protocol NutritionTable: Sendable {
    /// Returns the typical kcal per 100 grams for `foodName`, or `nil` if the
    /// food isn't in this source.
    ///
    /// - Parameter foodName: A normalised food name without quantity
    ///   (e.g. "grilled chicken", "eggs", "white rice").
    func caloriesPer100g(for foodName: String) -> Int?
}

/// A ``NutritionTable`` that never resolves a value — every lookup misses.
///
/// Useful as a default when you want the model to supply every number, and in
/// tests that exercise the pure computation path.
public struct EmptyNutritionTable: NutritionTable {
    public init() {}
    public func caloriesPer100g(for foodName: String) -> Int? { nil }
}

/// An offline, bundled ``NutritionTable`` covering common foods.
///
/// Values are typical calories per 100 grams **as the food is usually eaten**
/// (e.g. rice and pasta are cooked). Lookups are matched leniently: the name is
/// normalised, then tried as an exact key, as a singular/plural variant, and
/// finally as the longest whole-word key contained in the phrase — so
/// "grilled chicken breast" still resolves via "chicken breast" or "chicken".
public struct LocalNutritionTable: NutritionTable {

    public init() {}

    public func caloriesPer100g(for foodName: String) -> Int? {
        let normalized = Self.normalize(foodName)
        guard !normalized.isEmpty else { return nil }

        // 1. Exact match on the normalised name.
        if let value = Self.table[normalized] { return value }

        // 2. Singular/plural variant of the whole name.
        let singular = Self.singularize(normalized)
        if singular != normalized, let value = Self.table[singular] { return value }

        // 3. Longest whole-word key contained in the phrase, e.g.
        //    "grilled chicken" → "chicken". Longest wins so a more specific
        //    key ("chicken breast") beats a broader one ("chicken").
        var best: (key: String, value: Int)?
        for (key, value) in Self.table where Self.phrase(normalized, containsKey: key) {
            if best == nil || key.count > best!.key.count {
                best = (key, value)
            }
        }
        return best?.value
    }

    // MARK: - Matching helpers

    /// Lowercase, strip punctuation, and collapse whitespace.
    static func normalize(_ name: String) -> String {
        let lowered = name.lowercased()
        let stripped = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(stripped)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }

    /// A naive English singularizer good enough for food names.
    static func singularize(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 3 {
            return String(word.dropLast(3)) + "y"        // berries → berry
        }
        if word.hasSuffix("oes"), word.count > 3 {
            return String(word.dropLast(2))              // tomatoes → tomato
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 1 {
            return String(word.dropLast())               // eggs → egg
        }
        return word
    }

    /// Whether `key` appears as a whole word (or word run) inside `phrase`.
    /// Padding with spaces prevents "egg" from matching "eggplant".
    static func phrase(_ phrase: String, containsKey key: String) -> Bool {
        " \(phrase) ".contains(" \(key) ")
    }

    // MARK: - Bundled data
    //
    // Typical kcal per 100 g, as commonly eaten. Keys are stored singular and
    // lowercase; the matcher handles plurals and modifiers like "grilled".

    static let table: [String: Int] = [
        // Poultry & meat (cooked)
        "chicken": 190, "chicken breast": 165, "grilled chicken": 165,
        "chicken thigh": 209, "fried chicken": 246, "chicken nugget": 296,
        "turkey": 135, "beef": 250, "ground beef": 250, "steak": 271,
        "pork": 242, "bacon": 541, "ham": 145, "sausage": 301,
        "hot dog": 290, "lamb": 294, "meatball": 197,

        // Fish & seafood (cooked)
        "salmon": 208, "tuna": 130, "cod": 105, "shrimp": 99, "prawn": 99,
        "sardine": 208, "crab": 97, "fish": 130,

        // Eggs & plant protein
        "egg": 155, "egg white": 52, "tofu": 76, "tempeh": 192,
        "lentil": 116, "chickpea": 164, "black bean": 132, "kidney bean": 127,
        "hummus": 166,

        // Grains & starches (cooked / as eaten)
        "rice": 130, "white rice": 130, "brown rice": 123, "fried rice": 163,
        "pasta": 157, "spaghetti": 157, "noodle": 138, "macaroni": 157,
        "bread": 265, "white bread": 265, "whole wheat bread": 247,
        "bagel": 250, "toast": 313, "tortilla": 218, "roll": 307,
        "oatmeal": 68, "oats": 389, "quinoa": 120, "couscous": 112,
        "cereal": 379, "granola": 471, "pancake": 227, "waffle": 291,
        "potato": 87, "mashed potato": 113, "french fries": 312, "fries": 312,
        "sweet potato": 90, "corn": 96,

        // Dairy
        "milk": 60, "whole milk": 61, "skim milk": 34, "cheese": 402,
        "cheddar cheese": 402, "cheddar": 402, "mozzarella": 280,
        "parmesan": 431, "feta": 264, "yogurt": 59, "greek yogurt": 73,
        "butter": 717, "cream": 340, "ice cream": 207,

        // Fruit
        "apple": 52, "banana": 89, "orange": 47, "grape": 69, "strawberry": 32,
        "blueberry": 57, "raspberry": 52, "watermelon": 30, "melon": 34,
        "mango": 60, "pineapple": 50, "pear": 57, "peach": 39, "plum": 46,
        "cherry": 63, "avocado": 160, "grapefruit": 42, "kiwi": 61,
        "lemon": 29, "pomegranate": 83, "date": 282, "raisin": 299,

        // Vegetables
        "broccoli": 34, "carrot": 41, "spinach": 23, "lettuce": 15,
        "tomato": 18, "cucumber": 15, "onion": 40, "bell pepper": 20,
        "pepper": 20, "mushroom": 22, "zucchini": 17, "eggplant": 25,
        "cauliflower": 25, "green bean": 31, "pea": 81, "cabbage": 25,
        "kale": 49, "asparagus": 20, "celery": 16, "beet": 43,

        // Nuts, seeds & fats
        "almond": 579, "walnut": 654, "peanut": 567, "peanut butter": 588,
        "cashew": 553, "pistachio": 560, "hazelnut": 628, "chia seed": 486,
        "olive oil": 884, "oil": 884, "honey": 304, "sugar": 387, "jam": 278,

        // Beverages
        "orange juice": 45, "apple juice": 46, "juice": 45, "soda": 41,
        "cola": 41, "coffee": 2, "tea": 1, "beer": 43, "wine": 83,
        "smoothie": 60,

        // Prepared dishes & snacks
        "pizza": 266, "hamburger": 295, "cheeseburger": 303, "burger": 295,
        "sandwich": 250, "burrito": 206, "taco": 217, "sushi": 145,
        "lasagna": 135, "mac and cheese": 164, "macaroni and cheese": 164,
        "curry": 150, "soup": 50, "ramen": 436, "risotto": 166,
        "chips": 536, "potato chips": 536, "popcorn": 375, "pretzel": 380,
        "cracker": 502, "guacamole": 155, "salsa": 36, "ketchup": 101,
        "mayonnaise": 680, "mustard": 66,

        // Sweets & baked goods
        "chocolate": 546, "cookie": 502, "cake": 350, "chocolate cake": 371,
        "muffin": 377, "croissant": 406, "donut": 452, "doughnut": 452,
        "brownie": 466, "pie": 265, "cheesecake": 321, "candy": 394,
    ]
}
