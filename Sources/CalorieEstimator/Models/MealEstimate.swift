/// The unified result of any calorie estimate, returned by both public entry points
/// (``CalorieEstimator/estimate(phrase:)`` and ``CalorieEstimator/estimate(meal:weight:)``).
///
/// The app renders every estimate the same way regardless of how it was produced. A
/// single food carries a `nil` ``ingredients`` list; a composite dish carries the
/// breakdown it was summed from.
public struct MealEstimate: Sendable, Equatable {
    /// How the estimate's calories were arrived at.
    public enum Source: Sendable, Equatable {
        /// Resolved directly from the nutrition table — computed in code, no model call.
        case database
        /// A last-resort calories-per-100g figure supplied by the model.
        case model
        /// A composite dish summed from a trusted recipe or a validated model proposal.
        case decomposed
    }

    /// The food or dish name, in the user's language (e.g. "yumurta", "lasagna").
    public let foodName: String
    /// The approximate mass in grams the calories are for.
    public let grams: Int
    /// The estimated total calories (kcal).
    public let calories: Int
    /// How the calories were arrived at.
    public let source: Source
    /// The trust boundary that produced this result.
    public let provenance: EstimateProvenance
    /// The stable local recipe identifier, when a trusted local recipe was used.
    public let recipeID: RecipeID?
    /// How much to trust the estimate, when a meaningful signal is available:
    /// ``Confidence/high`` for trusted local data, ``Confidence/medium`` for a model-assisted
    /// composition resolved through local nutrition, and ``Confidence/low`` for model nutrition.
    public let confidence: Confidence?
    /// The ingredient breakdown — non-`nil` only when ``source`` is ``Source/decomposed``.
    public let ingredients: [IngredientEstimate]?

    public init(
        foodName: String,
        grams: Int,
        calories: Int,
        source: Source,
        confidence: Confidence? = nil,
        ingredients: [IngredientEstimate]? = nil,
        provenance: EstimateProvenance? = nil,
        recipeID: RecipeID? = nil
    ) {
        self.foodName = foodName
        self.grams = grams
        self.calories = calories
        self.source = source
        self.provenance = provenance ?? Self.defaultProvenance(for: source)
        self.recipeID = recipeID
        self.confidence = confidence
        self.ingredients = ingredients
    }

    private static func defaultProvenance(for source: Source) -> EstimateProvenance {
        switch source {
        case .database: .localNutrition
        case .model: .modelNutrition
        case .decomposed: .modelAssistedRecipe
        }
    }
}
