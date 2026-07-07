import FoundationModels

/// Estimates calories for a given meal using on-device Apple Intelligence.
///
/// Four entry points, from simplest to richest:
/// - ``estimate(meal:grams:)`` / ``estimate(meal:amount:)`` — a known food and quantity.
/// - ``estimate(phrase:)`` — a single natural-language phrase ("two eggs").
/// - ``estimate(dish:attempts:)`` — a composite dish, decomposed into ingredients.
///
/// All calorie figures are resolved through a ``NutritionTable`` (the bundled
/// ``LocalNutritionTable`` by default) and computed in code; the model supplies figures
/// only when a food isn't in the table. The pure conversion logic lives in
/// `CalorieEstimator+Conversion.swift`.
public struct CalorieEstimator: Sendable {

    /// The nutrition source consulted before falling back to the model.
    let nutritionTable: NutritionTable

    /// Create an estimator.
    /// - Parameter nutritionTable: The source used to resolve calories-per-100g.
    ///   Defaults to the bundled ``LocalNutritionTable``; pass ``EmptyNutritionTable`` to
    ///   rely solely on the model, or a custom ``NutritionTable`` to plug in another database.
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
    /// food, normalises the amount to an approximate gram weight, and reports the food's
    /// per-100g figure in a single inference call. If no amount is stated, a single
    /// typical serving is assumed.
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

    /// Estimate a composite dish by reverse-engineering its ingredients.
    ///
    /// For a dish where a single calories-per-100g figure is meaningless
    /// ("kremalı mantarlı makarna", "lasagna", "tahdig"), the model breaks the dish into
    /// its main ingredients with an approximate mass each. Every ingredient's
    /// calories-per-100g is resolved through the same nutrition table used elsewhere —
    /// falling back to the model per ingredient — and the totals are summed in code.
    ///
    /// Confidence blends three signals: how much of the dish's mass came from the
    /// database, how closely the ingredient sum matches an independent holistic estimate
    /// the model makes, and whether the implied energy density is plausible. When
    /// `attempts > 1`, several independent breakdowns are generated and their agreement
    /// becomes an additional signal — a breakdown the model keeps changing is trusted
    /// less. The median-total breakdown is returned.
    ///
    /// - Parameters:
    ///   - dish: The dish name, in any language.
    ///   - attempts: How many independent decompositions to generate. `1` (default) is a
    ///     single fast, reproducible pass; higher values trade latency for accuracy and a
    ///     stronger confidence signal.
    /// - Returns: A ``DishEstimate`` with the ingredient breakdown, total calories, and confidence.
    /// - Throws: ``CalorieEstimatorError/modelUnavailable(reason:)`` when the on-device
    ///   model can't be used, or ``CalorieEstimatorError/parsingFailed(response:)`` when
    ///   the model returns no usable ingredients.
    public func estimate(dish: String, attempts: Int = 1) async throws -> DishEstimate {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

        guard case .available = model.availability else {
            throw CalorieEstimatorError.modelUnavailable(reason: Self.description(for: model.availability))
        }

        let instructions = """
        You estimate a dish's calories by breaking it into its main ingredients.
        Given a dish name in any language, list the main ingredients of ONE typical \
        serving, each with an approximate mass in grams and its common English name for \
        lookup. Keep the dish and ingredient names in the input language. Account for \
        calorie-dense additions such as oil, butter, cream, and sauces that a recipe \
        normally includes. Separately, give an INDEPENDENT holistic estimate of the \
        serving's total calories, judged from the whole dish without adding up the \
        ingredients.
        """

        let rounds = max(1, attempts)
        var estimates: [DishEstimate] = []
        estimates.reserveCapacity(rounds)

        for attempt in 0..<rounds {
            // A fresh session per attempt keeps the decompositions independent. One attempt
            // is greedy (reproducible); multiple attempts vary the seed so the model
            // re-thinks the breakdown, and their agreement feeds confidence.
            let session = LanguageModelSession(model: model, instructions: instructions)
            let options = rounds == 1
                ? GenerationOptions(sampling: .greedy)
                : GenerationOptions(sampling: .random(top: 30, seed: UInt64(attempt)))

            let response = try await session.respond(
                to: "Dish: \(dish)",
                generating: RecipeResponse.self,
                options: options
            )

            if let estimate = Self.makeDishEstimate(from: response.content, using: nutritionTable) {
                estimates.append(estimate)
            }
        }

        guard let combined = Self.combineDishEstimates(estimates) else {
            throw CalorieEstimatorError.parsingFailed(response: "no usable ingredients for dish=\"\(dish)\"")
        }
        return combined
    }
}
