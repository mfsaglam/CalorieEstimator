enum MealQuantityUnit: String, Sendable, Equatable {
    case gram
    case kilogram
    case ounce
    case pound
    case milliliter
    case liter
    case serving
    case bowl
    case cup
    case slice
    case piece
    case item
}

struct MealQuantity: Sendable, Equatable {
    let amount: Double
    let unit: MealQuantityUnit
    let estimatedGrams: Int?

    static func grams(_ value: Int) -> Self {
        Self(amount: Double(value), unit: .gram, estimatedGrams: value)
    }
}

enum MealModificationKind: String, Sendable, Equatable {
    case add
    case remove
    case increase
    case decrease
}

struct MealModification: Sendable, Equatable {
    let kind: MealModificationKind
    let ingredientName: String
    let ingredientNameEnglish: String
    let estimatedGrams: Int?
}

struct ModelIngredientProposal: Sendable, Equatable {
    let name: String
    let nameEnglish: String
    let ratio: Double
}

struct MealRequest: Sendable, Equatable {
    let displayName: String
    let lookupName: String
    /// The unmodified dish identity used for trusted recipe lookup. This remains
    /// distinct from `displayName`, which may include explicit modifiers.
    let baseDisplayName: String
    let baseLookupName: String
    let recipeID: RecipeID?
    let languageCode: String?
    let localeIdentifier: String?
    let cuisine: String?
    let quantity: MealQuantity
    let modifications: [MealModification]
    let isCompositeDish: Bool
    let proposedIngredients: [ModelIngredientProposal]
    let modelCaloriesPer100g: Int?
}
