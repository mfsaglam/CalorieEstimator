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

/// The result of estimating a meal from a single natural-language phrase.
public struct MealEstimate: Sendable, Equatable {
    /// The cleaned food name, without the quantity (e.g. "grilled chicken").
    public let foodName: String
    /// The approximate mass in grams for the described amount.
    public let grams: Int
    /// The estimated calories (kcal) for that amount.
    public let calories: Int

    public init(foodName: String, grams: Int, calories: Int) {
        self.foodName = foodName
        self.grams = grams
        self.calories = calories
    }
}

// MARK: - Errors

/// Errors thrown by ``CalorieEstimator``.
public enum CalorieEstimatorError: LocalizedError {
    /// The model returned output that couldn't be turned into a usable estimate.
    case parsingFailed(response: String)
    /// The on-device model is unavailable (e.g. Apple Intelligence disabled or still downloading).
    case modelUnavailable(reason: String)
    /// The image classifier found no food to estimate.
    case noFoodDetected

    public var errorDescription: String? {
        switch self {
        case .parsingFailed(let response):
            return "The model returned an unusable estimate: \(response)"
        case .modelUnavailable(let reason):
            return "The on-device model is unavailable: \(reason)"
        case .noFoodDetected:
            return "No food could be detected in the image."
        }
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

/// Model response for phrase-based estimation.
///
/// A single guided generation produces the cleaned food name, an approximate
/// mass in grams, and the calories for that mass — so the whole phrase is parsed
/// and estimated in one inference call.
@Generable
struct PhraseNutritionResponse {
    @Guide(description: "The food only, normalised, with NO quantity, number, or unit. E.g. \"grilled chicken\", \"salmon\", \"white rice\", \"eggs\", \"almonds\".")
    var foodName: String
    @Guide(description: "Approximate mass in grams for the stated amount. Convert using typical food densities and serving sizes. Anchors: 1 kg = 1000 g; 1 oz ≈ 28 g; 1 lb ≈ 454 g; watery foods and drinks are about 1 g per ml, so 250 ml ≈ 250 g and 1 litre ≈ 1000 g; 1 cup ≈ 240 g; 1 tbsp ≈ 15 g; 1 tsp ≈ 5 g. For counts, use one typical item (e.g. 1 egg ≈ 50 g, a handful ≈ 30 g). If no amount is stated, assume a single typical serving. This value is grams only — do not multiply by calories.", .range(1...3000))
    var grams: Int
    @Guide(description: "Estimated calories (kcal) for that gram amount, consistent with the food's typical calories per 100 grams.", .minimum(1))
    var calories: Int
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

    /// Estimate a meal from a single natural-language phrase.
    ///
    /// The phrase can describe the amount as a weight ("200 grams of grilled chicken"),
    /// a volume ("250 ml orange juice"), or a count ("two eggs", "a handful of almonds"),
    /// including word-number quantities ("eight ounces of salmon"). The model parses the
    /// food, normalises the amount to an approximate gram weight, and estimates the
    /// calories for that weight in a single inference call. If no amount is stated, a
    /// single typical serving is assumed.
    ///
    /// The model is instructed to estimate calories consistently with a food's typical
    /// calories-per-100g — the same nutrition knowledge ``estimate(meal:grams:)`` relies
    /// on — so the two entry points agree in methodology while keeping this to one call.
    ///
    /// - Parameter phrase: A spoken/typed description of a food and its amount.
    /// - Returns: A ``MealEstimate`` with the cleaned food name, grams, and calories.
    /// - Throws: ``CalorieEstimatorError/modelUnavailable(reason:)`` when the on-device
    ///   model can't be used, or ``CalorieEstimatorError/parsingFailed(response:)`` when
    ///   the model returns unusable output.
    public func estimate(phrase: String) async throws -> MealEstimate {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

        guard case .available = model.availability else {
            throw CalorieEstimatorError.modelUnavailable(reason: Self.description(for: model.availability))
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You convert a short description of a food into structured nutrition data.
            Extract the food itself without any quantity, convert the stated amount into \
            an approximate mass in grams, and estimate the calories for that mass. Handle \
            weights (g, kg, oz, lb), volumes (ml, l, cup, tbsp, tsp) and counts such as \
            "two eggs" or "a handful" using typical food densities and serving sizes. \
            Word-number quantities like "eight ounces" count as amounts. If no amount is \
            stated, assume one typical serving. Estimate calories consistently with the \
            food's typical calories per 100 grams.
            """
        )

        let response = try await session.respond(
            to: "Food description: \(phrase)",
            generating: PhraseNutritionResponse.self
        )

        return try Self.makeMealEstimate(from: response.content)
    }

    // MARK: - Internal Conversion (testable)

    /// Convert a ``NutritionResponse`` to a ``CalorieEstimation``.
    static func makeEstimation(from response: NutritionResponse, grams: Int) -> CalorieEstimation {
        let calories = response.caloriesPer100g * grams / 100
        let explanation = "\(response.foodName) has ~\(response.caloriesPer100g) kcal per 100g."
        return CalorieEstimation(calories: calories, explanation: explanation)
    }

    /// Validate a ``PhraseNutritionResponse`` and convert it to a ``MealEstimate``.
    ///
    /// Throws ``CalorieEstimatorError/parsingFailed(response:)`` rather than returning a
    /// zero/garbage estimate when the food name is empty or the numbers are non-positive.
    static func makeMealEstimate(from response: PhraseNutritionResponse) throws -> MealEstimate {
        let foodName = response.foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !foodName.isEmpty, response.grams > 0, response.calories > 0 else {
            throw CalorieEstimatorError.parsingFailed(
                response: "foodName=\"\(response.foodName)\", grams=\(response.grams), calories=\(response.calories)"
            )
        }
        return MealEstimate(foodName: foodName, grams: response.grams, calories: response.calories)
    }

    /// A human-readable description of the model's availability status.
    static func description(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(.deviceNotEligible):
            return "this device does not support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled in Settings"
        case .unavailable(.modelNotReady):
            return "the on-device model is not ready yet (it may still be downloading)"
        case .unavailable(let other):
            return "unavailable for an unknown reason (\(other))"
        }
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
