import Foundation
import FoundationModels

/// The result of a calorie estimation.
public struct CalorieEstimation: Sendable {
    /// Estimated total calories (kcal).
    public let calories: Int
    /// A brief explanation of how the estimate was derived.
    public let explanation: String?
    /// The estimated weight in grams (populated only when using amount-based estimation).
    public let estimatedGrams: Int?

    public init(calories: Int, explanation: String?, estimatedGrams: Int? = nil) {
        self.calories = calories
        self.explanation = explanation
        self.estimatedGrams = estimatedGrams
    }
}

// MARK: - Generable Response Types

/// Model response for grams-based estimation.
@Generable
struct NutritionResponse {
    @Guide(description: "Approximate calories per 100 grams of this food")
    var caloriesPer100g: Int
    @Guide(description: "The name of the food item")
    var foodName: String
}

/// Model response for amount-based estimation.
@Generable
struct AmountNutritionResponse {
    @Guide(description: "Approximate calories per 100 grams of this food")
    var caloriesPer100g: Int
    @Guide(description: "Estimated total weight in grams for the given amount")
    var estimatedGrams: Int
    @Guide(description: "The name of the food item")
    var foodName: String
}

// MARK: - CalorieEstimator

/// Estimates calories for a given meal using on-device Apple Intelligence.
public struct CalorieEstimator: Sendable {

    public init() {}

    /// Estimate the calories in a meal.
    /// - Parameters:
    ///   - meal: The name of the meal or food item.
    ///   - grams: The weight in grams.
    /// - Returns: A ``CalorieEstimation`` with the calorie count and explanation.
    public func estimate(meal: String, grams: Int) async throws -> CalorieEstimation {
        let session = LanguageModelSession(
            model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
            instructions: "You are a food nutrition reference."
        )

        let prompt = "Calories per 100 grams of \(meal)."
        let response = try await session.respond(
            to: prompt,
            generating: NutritionResponse.self
        )

        return Self.makeEstimation(from: response.content, grams: grams)
    }

    /// Estimate the calories in a meal using a count-based amount.
    /// - Parameters:
    ///   - meal: The name of the meal or food item.
    ///   - amount: The number of items (e.g. 2 for "2 eggs").
    /// - Returns: A ``CalorieEstimation`` with the calorie count, explanation, and estimated grams.
    public func estimate(meal: String, amount: Int) async throws -> CalorieEstimation {
        let session = LanguageModelSession(
            model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
            instructions: "You are a food nutrition reference."
        )

        let prompt = "\(amount) of \(meal)."
        let response = try await session.respond(
            to: prompt,
            generating: AmountNutritionResponse.self
        )

        return Self.makeEstimation(from: response.content)
    }

    // MARK: - Internal Conversion (testable)

    /// Convert a ``NutritionResponse`` to a ``CalorieEstimation``.
    static func makeEstimation(from response: NutritionResponse, grams: Int) -> CalorieEstimation {
        let calories = response.caloriesPer100g * grams / 100
        let explanation = "\(response.foodName) has ~\(response.caloriesPer100g) kcal per 100g."
        return CalorieEstimation(calories: calories, explanation: explanation)
    }

    /// Convert an ``AmountNutritionResponse`` to a ``CalorieEstimation``.
    static func makeEstimation(from response: AmountNutritionResponse) -> CalorieEstimation {
        let calories = response.caloriesPer100g * response.estimatedGrams / 100
        let explanation = "\(response.foodName) has ~\(response.caloriesPer100g) kcal per 100g."
        return CalorieEstimation(
            calories: calories,
            explanation: explanation,
            estimatedGrams: response.estimatedGrams
        )
    }
}
