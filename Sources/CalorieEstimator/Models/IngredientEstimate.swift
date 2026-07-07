/// A single ingredient within a decomposed dish estimate.
///
/// Populated on ``MealEstimate/ingredients`` only when a composite dish was broken
/// down and summed.
public struct IngredientEstimate: Sendable, Equatable {
    /// Where this ingredient's calories-per-100g figure came from.
    public enum Source: Sendable, Equatable {
        /// Resolved from the nutrition table.
        case database
        /// The ingredient wasn't in the table, so the model's figure was used.
        case model
    }

    /// The ingredient name, in the user's language (e.g. "krema").
    public let name: String
    /// The approximate mass in grams of this ingredient in the estimated portion.
    public let grams: Int
    /// The estimated calories (kcal) contributed by this ingredient.
    public let calories: Int
    /// Whether this ingredient's calories-per-100g came from the database or the model.
    public let source: Source

    public init(name: String, grams: Int, calories: Int, source: Source) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.source = source
    }
}
