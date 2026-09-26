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

enum MealQuantityScope: String, Sendable, Equatable {
    /// The stated quantity is the final mass after all modifiers are applied.
    case finalMeal
    /// The stated quantity is the base recipe mass; explicit additions are extra.
    case baseRecipe
}

enum MealModificationKind: String, Sendable, Equatable {
    case add
    case remove
    case increase
    case decrease
}

/// A semantic choice constrained to a one-based position in a trusted recipe.
/// Swift, never the model, maps this selection to its stable IngredientID.
struct TrustedIngredientSelection: Sendable, Equatable {
    let kind: MealModificationKind
    let candidateNumber: Int
    let grams: Int?
}

struct MealModification: Sendable, Equatable {
    let kind: MealModificationKind
    /// Trusted identity when this modification crossed the canonical boundary.
    /// Legacy/model fallback requests may leave it nil and retain name-based behavior.
    let ingredientID: IngredientID?
    let ingredientName: String
    let ingredientNameEnglish: String
    let estimatedGrams: Int?

    init(
        kind: MealModificationKind,
        ingredientID: IngredientID? = nil,
        ingredientName: String,
        ingredientNameEnglish: String,
        estimatedGrams: Int?
    ) {
        self.kind = kind
        self.ingredientID = ingredientID
        self.ingredientName = ingredientName
        self.ingredientNameEnglish = ingredientNameEnglish
        self.estimatedGrams = estimatedGrams
    }
}

enum CanonicalMealModification: Sendable, Equatable {
    case add(ingredientID: IngredientID, grams: Int?)
    case remove(ingredientID: IngredientID)
    case increase(ingredientID: IngredientID, grams: Int?)
    case decrease(ingredientID: IngredientID, grams: Int?)

    init?(_ modification: MealModification) {
        guard let ingredientID = modification.ingredientID else { return nil }
        switch modification.kind {
        case .add:
            self = .add(ingredientID: ingredientID, grams: modification.estimatedGrams)
        case .remove:
            self = .remove(ingredientID: ingredientID)
        case .increase:
            self = .increase(ingredientID: ingredientID, grams: modification.estimatedGrams)
        case .decrease:
            self = .decrease(ingredientID: ingredientID, grams: modification.estimatedGrams)
        }
    }
}

struct CanonicalMealRequest: Sendable, Equatable {
    let recipeID: RecipeID?
    let quantity: MealQuantity
    let modifications: [CanonicalMealModification]

    init(recipeID: RecipeID?, quantity: MealQuantity, modifications: [MealModification]) {
        self.recipeID = recipeID
        self.quantity = quantity
        self.modifications = modifications.compactMap(CanonicalMealModification.init)
    }
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
    let quantityScope: MealQuantityScope
    let modifications: [MealModification]
    let isCompositeDish: Bool
    let proposedIngredients: [ModelIngredientProposal]
    let modelCaloriesPer100g: Int?
    /// Present only after trusted recipe/ingredient canonicalization.
    var canonicalRequest: CanonicalMealRequest? = nil
}
