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
    @Guide(description: "Use add/remove for an ingredient absent from or removed from the recipe. Use increase/decrease for changing the amount of an ingredient already in the recipe.")
    var kind: GeneratedModificationKind
    @Guide(description: "One ingredient only, without quantity; never return the dish name")
    var ingredientName: String
    @Guide(description: "One common English ingredient name only; for an existing recipe ingredient use the supplied canonical ingredient name")
    var ingredientNameEnglish: String
    @Guide(description: "Grams explicitly attached to this ingredient change; never copy the whole meal weight here; use 0 for qualitative changes", .range(0...1000))
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
    @Guide(description: "True only when the user explicitly states a mass for the whole food or meal, not merely for one ingredient")
    var hasExplicitTotalMass: Bool
    var modifications: [GeneratedMealModification]
    @Guide(description: "True for a prepared dish made from multiple ingredients")
    var isCompositeDish: Bool
    @Guide(description: "Only for an unknown composite recipe: a short ingredient composition whose ratios approximately total one. Empty for simple foods or a recipe found by the tool.")
    var proposedIngredients: [GeneratedIngredientProposal]
    @Guide(description: "Lowest-trust calories per 100 grams for the whole food, used only if every local lookup and local-nutrition decomposition fails", .range(1...900))
    var fallbackCaloriesPer100g: Int
}

@Generable
struct GeneratedNewIngredientAddition {
    @Guide(description: "Exact text copied from the original or translated description that explicitly requests this one change")
    var evidenceText: String
    @Guide(description: "Name of the genuinely new ingredient in the input language")
    var ingredientName: String
    @Guide(description: "Common English nutrition name of the genuinely new ingredient")
    var ingredientNameEnglish: String
    @Guide(description: "True only when a separate numeric gram amount directly quantifies this ingredient change")
    var hasExplicitGrams: Bool
    @Guide(description: "The separate explicit grams for this ingredient change; use 0 when hasExplicitGrams is false", .range(0...1000))
    var explicitGrams: Int
}

@Generable
struct GeneratedModifierPreservingTranslation {
    @Guide(description: "Faithful English rendering that preserves every ingredient modifier, its direction or intensity, and every number and unit")
    var englishDescription: String
    @Guide(description: "Every explicit mass in the description converted to grams, in source order; empty when no mass is stated")
    var explicitMassesGrams: [Int]
}

@Generable
enum GeneratedExistingIngredientChangeDirection {
    case useMore
    case useLess
    case removeEntirely
}

@Generable
struct GeneratedExistingIngredientChangeDecision {
    @Guide(description: "True only when the user explicitly requests a change to the supplied target ingredient beyond naming it as part of the dish")
    var hasExplicitChange: Bool
    @Guide(description: "Shortest exact contiguous phrase copied from the original description that expresses both the change and its target; empty when unchanged")
    var evidenceText: String
}

@Generable
struct GeneratedChangeEvidenceInterpretation {
    @Guide(description: "Faithful English translation of the complete evidence phrase, preserving its ingredient, direction, and any number")
    var englishTranslation: String
    var direction: GeneratedExistingIngredientChangeDirection
    @Guide(description: "True only when the evidence phrase contains a separate gram amount that directly quantifies its ingredient change")
    var hasExplicitGrams: Bool
    @Guide(description: "Explicit grams contained in the evidence phrase; use 0 when absent", .range(0...1000))
    var explicitGrams: Int
}

@Generable
struct ParsedKnownRecipeModificationsResponse {
    @Guide(description: "True only when the user explicitly states a gram mass for the whole base dish or final meal")
    var hasExplicitWholeMealGrams: Bool
    @Guide(description: "True only when the user clearly states that explicit modifier grams are added outside the stated base-recipe quantity. False when the stated quantity is the final meal mass or intent is uncertain.")
    var quantityExcludesModifierMass: Bool
    @Guide(description: "Only genuinely new ingredients the user explicitly asks to add")
    var addedNewIngredients: [GeneratedNewIngredientAddition]
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
