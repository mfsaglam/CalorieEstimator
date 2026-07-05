import Foundation
import FoundationModels

/// How much to trust a calorie estimate, based on where its calories-per-100g
/// figure came from.
public enum Confidence: Sendable, Equatable {
    /// The figure was resolved from the bundled nutrition database.
    case high
    /// The food wasn't in the database, so the model's recalled figure was used.
    case medium
}

/// The result of a calorie estimation.
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

/// The result of estimating a meal from a single natural-language phrase.
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

// MARK: - Errors

/// Errors thrown by ``CalorieEstimator``.
public enum CalorieEstimatorError: LocalizedError {
    /// The model returned output that couldn't be turned into a usable estimate.
    case parsingFailed(response: String)
    /// The on-device model is unavailable (e.g. Apple Intelligence disabled or still downloading).
    case modelUnavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .parsingFailed(let response):
            return "The model returned an unusable estimate: \(response)"
        case .modelUnavailable(let reason):
            return "The on-device model is unavailable: \(reason)"
        }
    }
}

// MARK: - Generable Response Types

/// Model response for grams-based estimation.
@Generable
struct NutritionResponse {
    @Guide(description: "Approximate calories per 100 grams of this food")
    var caloriesPer100g: Int
    @Guide(description: "The name of the food item, in the same language as the input")
    var foodName: String
    @Guide(description: "The food's common English name in lowercase, for database lookup. Translate if the input is in another language. E.g. \"yumurta\" → \"eggs\", \"pollo\" → \"chicken\", \"Reis\" → \"rice\".")
    var foodNameEnglish: String = ""
}

/// Model response for amount-based estimation.
@Generable
struct AmountNutritionResponse {
    @Guide(description: "Approximate calories per 100 grams of this food")
    var caloriesPer100g: Int
    @Guide(description: "Estimated total weight in grams for the given amount")
    var estimatedGrams: Int
    @Guide(description: "The name of the food item, in the same language as the input")
    var foodName: String
    @Guide(description: "The food's common English name in lowercase, for database lookup. Translate if the input is in another language. E.g. \"yumurta\" → \"eggs\", \"pollo\" → \"chicken\", \"Reis\" → \"rice\".")
    var foodNameEnglish: String = ""
}

/// Model response for phrase-based estimation.
///
/// A single guided generation produces the cleaned food name, an approximate
/// mass in grams, and the calories for that mass — so the whole phrase is parsed
/// and estimated in one inference call.
@Generable
struct PhraseNutritionResponse {
    @Guide(description: "The food only, normalised, with NO quantity, number, or unit, in the SAME language as the description. E.g. \"grilled chicken\", \"somon\", \"weißer Reis\".")
    var foodName: String
    @Guide(description: "The food's common English name in lowercase, with NO quantity, for database lookup. Translate if the description is in another language. E.g. \"yumurta\" → \"eggs\", \"somon\" → \"salmon\", \"beyaz pilav\" → \"white rice\".")
    var foodNameEnglish: String = ""
    @Guide(description: "Approximate mass in grams for the stated amount. Convert using typical food densities and serving sizes. Anchors: 1 kg = 1000 g; 1 oz ≈ 28 g; 1 lb ≈ 454 g; watery foods and drinks are about 1 g per ml, so 250 ml ≈ 250 g and 1 litre ≈ 1000 g; 1 cup ≈ 240 g; 1 tbsp ≈ 15 g; 1 tsp ≈ 5 g. For counts, use one typical item (e.g. 1 egg ≈ 50 g, a handful ≈ 30 g). If no amount is stated, assume a single typical serving. This value is grams only — do not multiply by calories.", .range(1...3000))
    var grams: Int
    @Guide(description: "Typical calories (kcal) per 100 grams of this food — a stable nutritional fact independent of the amount. E.g. eggs ≈ 155, white rice (cooked) ≈ 130, grilled chicken ≈ 165, almonds ≈ 580. Do NOT multiply by the amount; report the per-100-gram value only.", .range(1...900))
    var caloriesPer100g: Int
}

// MARK: - CalorieEstimator

/// Estimates calories for a given meal using on-device Apple Intelligence.
public struct CalorieEstimator: Sendable {

    /// The nutrition source consulted before falling back to the model.
    let nutritionTable: NutritionTable

    /// Create an estimator.
    /// - Parameter nutritionTable: The source used to resolve calories-per-100g
    ///   for phrase-based estimates. Defaults to the bundled ``LocalNutritionTable``;
    ///   pass ``EmptyNutritionTable`` to rely solely on the model, or a custom
    ///   ``NutritionTable`` to plug in another database.
    public init(nutritionTable: NutritionTable = LocalNutritionTable()) {
        self.nutritionTable = nutritionTable
    }

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
            generating: NutritionResponse.self,
            options: GenerationOptions(sampling: .greedy)
        )

        return Self.makeEstimation(from: response.content, grams: grams, using: nutritionTable)
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
            generating: AmountNutritionResponse.self,
            options: GenerationOptions(sampling: .greedy)
        )

        return Self.makeEstimation(from: response.content, using: nutritionTable)
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
            an approximate mass in grams, and report the food's typical calories per 100 \
            grams. Do NOT compute a total for the amount — that arithmetic is done \
            separately. The description may be in any language: keep the food name in that \
            language, and also provide its common English name for database lookup. Handle \
            weights (g, kg, oz, lb), volumes (ml, l, cup, tbsp, tsp) and counts such as \
            "two eggs" or "a handful" using typical food densities and serving sizes. \
            Word-number quantities like "eight ounces" count as amounts. If no amount is \
            stated, assume one typical serving.
            """
        )

        // Greedy sampling makes the estimate reproducible: the same phrase always yields
        // the same numbers, instead of swinging between retries.
        let response = try await session.respond(
            to: "Food description: \(phrase)",
            generating: PhraseNutritionResponse.self,
            options: GenerationOptions(sampling: .greedy)
        )

        return try Self.makeMealEstimate(from: response.content, using: nutritionTable)
    }

    // MARK: - Internal Conversion (testable)

    /// Resolve the calories-per-100g to use, preferring the nutrition table over the
    /// model's own figure.
    ///
    /// The table (English-only) is looked up by `englishName` — the model's English
    /// translation of the food — so a non-English input like "yumurta" still finds
    /// "eggs" in the database. When the English name is blank, the display name is tried
    /// as a fallback. Returns the chosen value and whether it came from the table.
    static func resolveCaloriesPer100g(
        table: NutritionTable,
        englishName: String,
        displayName: String,
        modelValue: Int
    ) -> (value: Int, fromTable: Bool) {
        let english = englishName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookupName = english.isEmpty ? displayName : english
        if let tableValue = table.caloriesPer100g(for: lookupName) {
            return (tableValue, true)
        }
        return (modelValue, false)
    }

    /// Convert a ``NutritionResponse`` to a ``CalorieEstimation``.
    ///
    /// The calories-per-100g figure is resolved from `table` (looked up by the food's
    /// English name) first, falling back to the model's figure only when the food isn't
    /// found. Confidence is ``Confidence/high`` for a database hit and
    /// ``Confidence/medium`` for a model guess.
    static func makeEstimation(from response: NutritionResponse, grams: Int, using table: NutritionTable) -> CalorieEstimation {
        let resolved = resolveCaloriesPer100g(
            table: table,
            englishName: response.foodNameEnglish,
            displayName: response.foodName,
            modelValue: response.caloriesPer100g
        )
        let calories = resolved.value * grams / 100
        let explanation = "\(response.foodName) has ~\(resolved.value) kcal per 100g."
        return CalorieEstimation(
            calories: calories,
            explanation: explanation,
            confidence: resolved.fromTable ? .high : .medium
        )
    }

    /// Validate a ``PhraseNutritionResponse`` and convert it to a ``MealEstimate``.
    ///
    /// The calories-per-100g figure is resolved from `table` first, falling back to the
    /// model's recalled figure only when the food isn't found — real data beats a
    /// memorized guess. The total calories are then computed here
    /// (`caloriesPer100g * grams / 100`) rather than trusting a total emitted by the
    /// model, so the (error-prone) multiplication happens deterministically in code and
    /// the calories are always consistent with the grams.
    ///
    /// Throws ``CalorieEstimatorError/parsingFailed(response:)`` rather than returning a
    /// zero/garbage estimate when the food name is empty or the numbers are non-positive.
    static func makeMealEstimate(from response: PhraseNutritionResponse, using table: NutritionTable) throws -> MealEstimate {
        let foodName = response.foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolveCaloriesPer100g(
            table: table,
            englishName: response.foodNameEnglish,
            displayName: foodName,
            modelValue: response.caloriesPer100g
        )
        guard !foodName.isEmpty, response.grams > 0, resolved.value > 0 else {
            throw CalorieEstimatorError.parsingFailed(
                response: "foodName=\"\(response.foodName)\", grams=\(response.grams), caloriesPer100g=\(resolved.value)"
            )
        }
        let calories = resolved.value * response.grams / 100
        let source: MealEstimate.Source = resolved.fromTable ? .database : .modelEstimate
        return MealEstimate(foodName: foodName, grams: response.grams, calories: calories, source: source)
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
    ///
    /// The calories-per-100g figure is resolved from `table` first, falling back to the
    /// model's figure only when the food isn't found. Confidence is ``Confidence/high``
    /// for a database hit and ``Confidence/medium`` for a model guess.
    static func makeEstimation(from response: AmountNutritionResponse, using table: NutritionTable) -> CalorieEstimation {
        let resolved = resolveCaloriesPer100g(
            table: table,
            englishName: response.foodNameEnglish,
            displayName: response.foodName,
            modelValue: response.caloriesPer100g
        )
        let calories = resolved.value * response.estimatedGrams / 100
        let explanation = "\(response.foodName) has ~\(resolved.value) kcal per 100g."
        return CalorieEstimation(
            calories: calories,
            explanation: explanation,
            estimatedGrams: response.estimatedGrams,
            confidence: resolved.fromTable ? .high : .medium
        )
    }
}
