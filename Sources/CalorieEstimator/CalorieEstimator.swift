import Foundation
import FoundationModels

/// The result of a calorie estimation.
public struct CalorieEstimation: Sendable {
    /// Estimated total calories (kcal).
    public let calories: Int
    /// A brief explanation of how the estimate was derived.
    public let explanation: String?
}

/// Estimates calories for a given meal using on-device Apple Intelligence.
public struct CalorieEstimator: Sendable {

    public init() {}

    /// Estimate the calories in a meal.
    /// - Parameters:
    ///   - meal: The name of the meal or food item.
    ///   - grams: The weight in grams.
    /// - Returns: A ``CalorieEstimation`` with the calorie count and explanation.
    public func estimate(meal: String, grams: Int) async throws -> CalorieEstimation {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(
            model: model,
            instructions: """
                You are a food nutrition reference. \
                Given a food item, provide the approximate calories per 100 grams. \
                Reply with ONLY a number on the first line, nothing else. \
                On the second line, the name of the food item.
                """
        )

        let prompt = "Calories per 100 grams of \(meal)."
        let options = GenerationOptions(sampling: .greedy)
        let response = try await session.respond(to: prompt, options: options)

        let lines = response.content.split(separator: "\n", maxSplits: 1)
        let firstLine = String(lines.first ?? "")
        let digits = firstLine.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        guard let caloriesPer100g = Int(digits), !digits.isEmpty else {
            throw CalorieEstimatorError.parsingFailed(response: response.content)
        }

        // Calculate actual calories based on weight — math done in code, not by the model.
        let calories = caloriesPer100g * grams / 100

        let foodName = if lines.count > 1 {
            String(lines[1]).trimmingCharacters(in: .whitespaces)
        } else {
            meal
        }

        let explanation = "\(foodName) has ~\(caloriesPer100g) kcal per 100g."

        return CalorieEstimation(calories: calories, explanation: explanation)
    }
}

/// Errors that can occur during calorie estimation.
public enum CalorieEstimatorError: LocalizedError {
    case parsingFailed(response: String)

    public var errorDescription: String? {
        switch self {
        case .parsingFailed(let response):
            "Could not parse calorie value from model response: \(response)"
        }
    }
}
