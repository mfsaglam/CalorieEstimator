import Foundation
import FoundationModels

/// Estimates calories for a meal using on-device Apple Intelligence.
///
/// Two entry points, matching how meals are logged:
/// - ``estimate(phrase:)`` — a natural-language phrase, any language ("iki yumurta",
///   "200 g grilled chicken", "kremalı mantarlı makarna"). For the Siri-intent path.
/// - ``estimate(meal:weight:)`` — a food name plus an explicit weight. For the
///   text-field path; units (oz/lb/kg) are converted to grams in code, never by the model.
///
/// Both return a unified ``MealEstimate`` the app renders identically. Calorie figures
/// are resolved through a ``NutritionTable`` (the bundled ``LocalNutritionTable`` by
/// default) and computed in code; the model is only consulted when the food isn't in the
/// table. Composite dishes are detected and broken into ingredients automatically — the
/// caller never chooses. The pure conversion logic lives in
/// `CalorieEstimator+Conversion.swift`.
public struct CalorieEstimator: Sendable {

    /// The nutrition source consulted before (and instead of) the model.
    let nutritionTable: NutritionTable

    /// Create an estimator.
    /// - Parameter nutritionTable: The source used to resolve calories-per-100g.
    ///   Defaults to the bundled ``LocalNutritionTable``; pass ``EmptyNutritionTable`` to
    ///   rely solely on the model, or a custom ``NutritionTable`` to plug in another database.
    public init(nutritionTable: NutritionTable = LocalNutritionTable()) {
        self.nutritionTable = nutritionTable
    }

    // MARK: - Public API

    /// Estimate a meal from a single natural-language phrase (the Siri-intent path).
    ///
    /// The phrase may describe the amount as a weight ("200 grams of grilled chicken"),
    /// a volume ("250 ml orange juice"), or a count ("two eggs", "a handful of almonds"),
    /// in any language. The model parses the food and amount; the calories-per-100g is
    /// then resolved from the nutrition table (falling back to the model) and multiplied
    /// in code. If the phrase names a composite dish, it is broken into ingredients
    /// automatically. If no amount is stated, a single typical serving is assumed.
    ///
    /// - Parameter phrase: A spoken/typed description of a food and its amount.
    /// - Returns: A ``MealEstimate``; ``MealEstimate/ingredients`` is populated only for
    ///   composite dishes.
    /// - Throws: ``CalorieEstimatorError/modelUnavailable(reason:)`` when the on-device
    ///   model can't be used, or ``CalorieEstimatorError/parsingFailed(response:)`` when
    ///   the model returns unusable output.
    public func estimate(phrase: String) async throws -> MealEstimate {
        let session = try makeSession(instructions: Self.phraseInstructions)
        let response = try await session.respond(
            to: "Food description: \(phrase)",
            generating: PhraseNutritionResponse.self,
            options: GenerationOptions(sampling: .greedy)
        ).content

        // A composite dish gets decomposed instead of trusting a single per-100g figure.
        if response.isCompositeDish {
            return try await estimate(dish: response.foodName)
        }

        return try Self.makeSingleFoodEstimate(
            foodName: response.foodName,
            englishName: response.foodNameEnglish,
            modelCaloriesPer100g: response.caloriesPer100g,
            grams: response.grams,
            table: nutritionTable
        )
    }

    /// Estimate a meal from a food name plus an explicit weight (the text-field path).
    ///
    /// The weight — grams, ounces, pounds, kilograms, anything — is converted to grams
    /// **in code** via `Measurement`; the model never parses units on this path.
    ///
    /// The food is looked up in the nutrition table **before any model session is
    /// created**: on a hit the calories are computed in code and returned immediately, so
    /// common foods cost zero model calls and work offline. Only on a miss is the model
    /// consulted — for the per-100g figure and whether the food is a composite dish, in a
    /// single call. Composite dishes are decomposed and scaled to the stated weight.
    ///
    /// - Parameters:
    ///   - meal: The food or dish name, in any language.
    ///   - weight: The amount, in any mass unit; converted to grams internally.
    /// - Returns: A ``MealEstimate``; ``MealEstimate/ingredients`` is populated only for
    ///   composite dishes.
    /// - Throws: ``CalorieEstimatorError/parsingFailed(response:)`` for a non-positive
    ///   weight or unusable model output, or
    ///   ``CalorieEstimatorError/modelUnavailable(reason:)`` when a model call is needed
    ///   but the model can't be used. A table hit never touches the model and never throws
    ///   ``CalorieEstimatorError/modelUnavailable(reason:)``.
    public func estimate(meal: String, weight: Measurement<UnitMass>) async throws -> MealEstimate {
        let grams = Int(weight.converted(to: .grams).value.rounded())
        guard grams > 0 else {
            throw CalorieEstimatorError.parsingFailed(response: "weight must be positive, got \(weight)")
        }

        // TABLE-FIRST SHORT-CIRCUIT: no session, no model, works offline.
        if let caloriesPer100g = nutritionTable.caloriesPer100g(for: meal) {
            return Self.makeTableEstimate(foodName: meal, grams: grams, caloriesPer100g: caloriesPer100g)
        }

        // Miss → one model call for the per-100g figure and the composite-dish signal.
        let session = try makeSession(instructions: Self.lookupInstructions)
        let response = try await session.respond(
            to: "Food: \(meal)",
            generating: FoodLookupResponse.self,
            options: GenerationOptions(sampling: .greedy)
        ).content

        // A composite dish is decomposed at one serving, then scaled to the stated weight.
        if response.isCompositeDish {
            let serving = try await estimate(dish: meal)
            return Self.scale(serving, toGrams: grams)
        }

        return try Self.makeSingleFoodEstimate(
            foodName: meal,
            englishName: response.foodNameEnglish,
            modelCaloriesPer100g: response.caloriesPer100g,
            grams: grams,
            table: nutritionTable
        )
    }

    /// Convenience overload of ``estimate(meal:weight:)`` taking a gram weight directly.
    ///
    /// - Parameters:
    ///   - meal: The food or dish name, in any language.
    ///   - grams: The weight in grams.
    public func estimate(meal: String, grams: Int) async throws -> MealEstimate {
        try await estimate(meal: meal, weight: Measurement(value: Double(grams), unit: .grams))
    }

    // MARK: - Internal Dish Decomposition

    /// Estimate a composite dish by reverse-engineering its ingredients.
    ///
    /// Internal: reached automatically from the public methods when the model flags the
    /// input as a composite dish. The model breaks the dish into its main ingredients
    /// with an approximate mass each; every ingredient's calories-per-100g is resolved
    /// through the nutrition table (falling back to the model) and summed in code.
    ///
    /// Confidence blends ingredient coverage, agreement with an independent holistic
    /// estimate, and plausibility. When `attempts > 1`, several independent breakdowns
    /// are generated (seeded random) and their agreement becomes an additional signal;
    /// the median-total breakdown is returned.
    ///
    /// - Parameters:
    ///   - dish: The dish name, in any language.
    ///   - attempts: How many independent decompositions to generate. `1` (default) is a
    ///     single fast, reproducible pass; higher values trade latency for accuracy.
    /// - Returns: A decomposed ``MealEstimate`` (``MealEstimate/Source/decomposed``).
    func estimate(dish: String, attempts: Int = 1) async throws -> MealEstimate {
        let model = try Self.availableModel()

        let rounds = max(1, attempts)
        var estimates: [MealEstimate] = []
        estimates.reserveCapacity(rounds)

        for attempt in 0..<rounds {
            // A fresh session per attempt keeps the decompositions independent. One attempt
            // is greedy (reproducible); multiple attempts vary the seed so the model
            // re-thinks the breakdown, and their agreement feeds confidence.
            let session = LanguageModelSession(model: model, instructions: Self.dishInstructions)
            let options = rounds == 1
                ? GenerationOptions(sampling: .greedy)
                : GenerationOptions(sampling: .random(top: 30, seed: UInt64(attempt)))

            let response = try await session.respond(
                to: "Dish: \(dish)",
                generating: RecipeResponse.self,
                options: options
            ).content

            if let estimate = Self.makeDecomposedEstimate(from: response, using: nutritionTable) {
                estimates.append(estimate)
            }
        }

        guard let combined = Self.combineEstimates(estimates) else {
            throw CalorieEstimatorError.parsingFailed(response: "no usable ingredients for dish=\"\(dish)\"")
        }
        return combined
    }

    // MARK: - Model Session Factory

    /// Check on-device model availability and build a session with the shared guardrails.
    ///
    /// Every model-touching path goes through this, so the availability guard is never
    /// skipped and the guardrail configuration stays in one place.
    private func makeSession(instructions: String) throws -> LanguageModelSession {
        LanguageModelSession(model: try Self.availableModel(), instructions: instructions)
    }

    /// The on-device model, or a throw describing why it's unavailable.
    static func availableModel() throws -> SystemLanguageModel {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else {
            throw CalorieEstimatorError.modelUnavailable(reason: description(for: model.availability))
        }
        return model
    }

    // MARK: - Instructions

    private static let phraseInstructions = """
    You convert a short food description into structured nutrition data.
    Keep the food name in the input language and also give its common English name for \
    database lookup. Convert the stated amount — weights (g, kg, oz, lb), volumes \
    (ml, l, cup, tbsp, tsp), or counts such as "two eggs" or "a handful" — into an \
    approximate mass in grams using typical densities and serving sizes; if no amount is \
    stated, assume one typical serving. Report the food's typical calories per 100 grams \
    (do NOT multiply by the amount). Set isCompositeDish to true only for a prepared dish \
    of several ingredients where a single per-100g value would be unreliable.
    """

    private static let lookupInstructions = """
    You are a food nutrition reference. Given a food name in any language, report its \
    typical calories per 100 grams and its common English name for database lookup. Do \
    not consider any quantity; report the per-100-gram value only. Set isCompositeDish to \
    true only for a prepared dish of several ingredients where a single per-100g value \
    would be unreliable.
    """

    private static let dishInstructions = """
    You estimate a dish's calories by breaking it into its main ingredients.
    Given a dish name in any language, list the main ingredients of ONE typical serving, \
    each with an approximate mass in grams and its common English name for lookup. Keep \
    the dish and ingredient names in the input language. Account for calorie-dense \
    additions such as oil, butter, cream, and sauces that a recipe normally includes. \
    Separately, give an INDEPENDENT holistic estimate of the serving's total calories, \
    judged from the whole dish without adding up the ingredients.
    """
}
