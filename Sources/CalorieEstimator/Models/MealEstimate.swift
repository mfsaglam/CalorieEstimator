/// The result of estimating a meal from a single natural-language phrase.
///
/// Returned by ``CalorieEstimator/estimate(phrase:)``.
public struct MealEstimate: Sendable, Equatable {
    /// Where the calories-per-100g figure behind an estimate came from.
    public enum Source: Sendable, Equatable {
        /// Resolved from the bundled nutrition table — the more reliable case.
        case database
        /// The food wasn't in the table, so the model's recalled figure was used.
        case modelEstimate
    }

    /// The cleaned food name, without the quantity (e.g. "grilled chicken").
    public let foodName: String
    /// The approximate mass in grams for the described amount.
    public let grams: Int
    /// The estimated calories (kcal) for that amount.
    public let calories: Int
    /// Where the underlying calories-per-100g figure came from.
    public let source: Source

    /// How much to trust this estimate: ``Confidence/high`` for a database hit,
    /// ``Confidence/medium`` for a model guess.
    public var confidence: Confidence {
        source == .database ? .high : .medium
    }

    public init(foodName: String, grams: Int, calories: Int, source: Source = .modelEstimate) {
        self.foodName = foodName
        self.grams = grams
        self.calories = calories
        self.source = source
    }
}
