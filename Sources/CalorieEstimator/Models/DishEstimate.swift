/// A single ingredient within a decomposed dish estimate.
public struct IngredientEstimate: Sendable, Equatable {
    /// The ingredient name, in the user's language (e.g. "krema").
    public let name: String
    /// The approximate mass in grams of this ingredient in one serving.
    public let grams: Int
    /// The estimated calories (kcal) contributed by this ingredient.
    public let calories: Int
    /// Whether this ingredient's calories-per-100g came from the database or the model.
    public let source: MealEstimate.Source

    public init(name: String, grams: Int, calories: Int, source: MealEstimate.Source) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.source = source
    }
}

/// The result of estimating a composite dish by reverse-engineering its ingredients.
///
/// Rather than guessing a dish's calories directly, the model breaks it into its
/// main ingredients; each ingredient's calories are resolved through the same
/// nutrition table used elsewhere and summed in code. See
/// ``CalorieEstimator/estimate(dish:attempts:)``.
public struct DishEstimate: Sendable, Equatable {
    /// The dish name, in the user's language (e.g. "kremalı mantarlı makarna").
    public let dishName: String
    /// The total approximate mass in grams of one serving.
    public let grams: Int
    /// The estimated total calories (kcal) — the sum of the ingredient calories.
    public let calories: Int
    /// The ingredient breakdown the estimate was built from.
    public let ingredients: [IngredientEstimate]
    /// How much to trust the estimate, from ingredient coverage, self-consistency,
    /// and plausibility (and, for ensembles, agreement across attempts).
    public let confidence: Confidence

    public init(dishName: String, grams: Int, calories: Int, ingredients: [IngredientEstimate], confidence: Confidence) {
        self.dishName = dishName
        self.grams = grams
        self.calories = calories
        self.ingredients = ingredients
        self.confidence = confidence
    }
}
