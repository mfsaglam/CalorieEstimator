/// The result of a calorie estimation.
///
/// Returned by ``CalorieEstimator/estimate(meal:grams:)`` and
/// ``CalorieEstimator/estimate(meal:amount:)``.
public struct CalorieEstimation: Sendable {
    /// Estimated total calories (kcal).
    public let calories: Int
    /// A brief explanation of how the estimate was derived.
    public let explanation: String?
    /// The estimated weight in grams (populated only when using amount-based estimation).
    public let estimatedGrams: Int?
    /// How much to trust this estimate — ``Confidence/high`` when the calories came
    /// from the nutrition database, ``Confidence/medium`` when the model supplied them.
    public let confidence: Confidence

    public init(calories: Int, explanation: String?, estimatedGrams: Int? = nil, confidence: Confidence = .medium) {
        self.calories = calories
        self.explanation = explanation
        self.estimatedGrams = estimatedGrams
        self.confidence = confidence
    }
}
