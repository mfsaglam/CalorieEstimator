import FoundationModels

// MARK: - Semantic parsing

@Generable
enum GeneratedQuantityUnit {
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

@Generable
enum GeneratedModificationKind {
    case add
    case remove
    case increase
    case decrease
}

@Generable
struct GeneratedMealModification {
    var kind: GeneratedModificationKind
    @Guide(description: "Ingredient in the input language, without quantity")
    var ingredientName: String
    @Guide(description: "Common English ingredient name for local nutrition lookup")
    var ingredientNameEnglish: String
    @Guide(description: "Estimated grams explicitly stated or clearly implied; 0 if unspecified", .range(0...1000))
    var estimatedGrams: Int
}

@Generable
struct GeneratedIngredientProposal {
    @Guide(description: "Ingredient name in the same language as the dish")
    var name: String
    @Guide(description: "Common English ingredient name for local nutrition lookup")
    var nameEnglish: String
    @Guide(description: "Fraction of total dish mass, greater than zero and at most one", .range(0.001...1.0))
    var ratio: Double
}

/// The model describes meaning only. Local databases and Swift decide which
/// composition and nutritional values are authoritative.
@Generable
struct ParsedMealResponse {
    @Guide(description: "Food or dish only, normalized, with no quantity, in the input language")
    var foodName: String
    @Guide(description: "Common English name used only as a local lookup candidate")
    var foodNameEnglish: String
    @Guide(description: "A recipe ID returned by the recipe lookup tool, or an empty string")
    var recipeID: String
    @Guide(description: "BCP-47 language code, or an empty string when unknown")
    var languageCode: String
    @Guide(description: "Locale identifier when inferable, or an empty string")
    var localeIdentifier: String
    @Guide(description: "Cuisine hint when explicit or unambiguous, or an empty string")
    var cuisine: String
    @Guide(description: "Numeric amount stated by the user; use 1 for an unstated single portion", .range(0.01...10000))
    var amount: Double
    var unit: GeneratedQuantityUnit
    @Guide(description: "Estimated total grams for volume/count/portion units; use 0 for mass units", .range(0...5000))
    var estimatedGrams: Int
    var modifications: [GeneratedMealModification]
    @Guide(description: "True for a prepared dish made from multiple ingredients")
    var isCompositeDish: Bool
    @Guide(description: "Only for an unknown composite recipe: a short ingredient composition whose ratios approximately total one. Empty for simple foods or a recipe found by the tool.")
    var proposedIngredients: [GeneratedIngredientProposal]
    @Guide(description: "Lowest-trust calories per 100 grams for the whole food, used only if every local lookup and local-nutrition decomposition fails", .range(1...900))
    var fallbackCaloriesPer100g: Int
}

/// A smaller semantic contract used after Swift has already identified a
/// trusted recipe. The model can only describe presentation, quantity, and
/// explicit changes; it cannot replace the recipe identity or composition.
@Generable
struct ParsedKnownRecipeResponse {
    @Guide(description: "The complete requested dish including explicit modifiers, without quantity, in the input language")
    var foodName: String
    @Guide(description: "Common English name for the complete requested dish including explicit modifiers, without quantity")
    var foodNameEnglish: String
    @Guide(description: "Numeric amount stated by the user; use 1 for an unstated single portion", .range(0.01...10000))
    var amount: Double
    var unit: GeneratedQuantityUnit
    @Guide(description: "Estimated total grams for volume/count/portion units; use 0 for mass units", .range(0...5000))
    var estimatedGrams: Int
    var modifications: [GeneratedMealModification]
}

@Generable
struct RecipeLookupArguments {
    @Guide(description: "Food or dish name without quantity")
    var name: String
    @Guide(description: "BCP-47 language code, or empty")
    var languageCode: String
    @Guide(description: "Locale identifier, or empty")
    var localeIdentifier: String
    @Guide(description: "Cuisine hint, or empty")
    var cuisine: String
}
