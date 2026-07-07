import FoundationModels

// MARK: - Internal Conversion (testable)
//
// The pure logic that turns model responses into public estimates: table resolution,
// dish summation, confidence scoring, and ensemble combination. Kept separate from the
// inference-driving methods in ``CalorieEstimator`` so it can be unit-tested without the
// on-device model.

extension CalorieEstimator {

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

    /// Build a ``DishEstimate`` from one decomposition, resolving each ingredient through
    /// the table and deriving confidence from coverage, self-consistency, and plausibility.
    ///
    /// Returns `nil` when the breakdown has no usable ingredients (empty, or all
    /// non-positive), so the caller can treat it as a failed attempt.
    static func makeDishEstimate(from response: RecipeResponse, using table: NutritionTable) -> DishEstimate? {
        let dishName = response.dishName.trimmingCharacters(in: .whitespacesAndNewlines)

        let ingredients: [IngredientEstimate] = response.ingredients.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, item.grams > 0 else { return nil }
            let resolved = resolveCaloriesPer100g(
                table: table,
                englishName: item.nameEnglish,
                displayName: name,
                modelValue: item.caloriesPer100g
            )
            guard resolved.value > 0 else { return nil }
            return IngredientEstimate(
                name: name,
                grams: item.grams,
                calories: resolved.value * item.grams / 100,
                source: resolved.fromTable ? .database : .modelEstimate
            )
        }

        guard !ingredients.isEmpty else { return nil }

        let totalGrams = ingredients.reduce(0) { $0 + $1.grams }
        let totalCalories = ingredients.reduce(0) { $0 + $1.calories }
        guard totalGrams > 0, totalCalories > 0 else { return nil }

        let confidence = classifyDishConfidence(
            ingredients: ingredients,
            totalGrams: totalGrams,
            sumCalories: totalCalories,
            holisticCalories: response.holisticCalories
        )

        return DishEstimate(
            dishName: dishName,
            grams: totalGrams,
            calories: totalCalories,
            ingredients: ingredients,
            confidence: confidence
        )
    }

    /// Score a single dish breakdown's confidence.
    ///
    /// - `coverage`: fraction of the dish's mass whose calories came from the database.
    /// - `divergence`: how far the ingredient sum sits from the model's independent
    ///   holistic estimate (relative). A large gap means the breakdown "doesn't add up".
    /// - `plausible`: whether the implied energy density (kcal per 100 g) is in a
    ///   sane range for food.
    static func classifyDishConfidence(
        ingredients: [IngredientEstimate],
        totalGrams: Int,
        sumCalories: Int,
        holisticCalories: Int
    ) -> Confidence {
        let coveredGrams = ingredients.filter { $0.source == .database }.reduce(0) { $0 + $1.grams }
        let coverage = Double(coveredGrams) / Double(totalGrams)

        let density = Double(sumCalories) * 100.0 / Double(totalGrams)
        let plausible = (20.0...900.0).contains(density)

        // No holistic reference (0 / absent) → lean on coverage + plausibility only.
        let divergence: Double? = holisticCalories > 0
            ? abs(Double(sumCalories) - Double(holisticCalories)) / Double(holisticCalories)
            : nil

        if !plausible { return .low }

        let consistent = divergence.map { $0 <= 0.25 } ?? false
        let looselyConsistent = divergence.map { $0 <= 0.5 } ?? true
        let wildlyOff = divergence.map { $0 > 0.75 } ?? false

        if wildlyOff { return .low }
        if coverage >= 0.6 && consistent { return .high }
        if coverage >= 0.3 || looselyConsistent { return .medium }
        return .low
    }

    /// Combine several independent breakdowns into one estimate.
    ///
    /// The breakdown whose total is the median is returned as the representative result;
    /// the spread across attempts then adjusts confidence — tight agreement can't raise a
    /// weak breakdown, but wide scatter downgrades an otherwise confident one, since a
    /// model that keeps changing its mind shouldn't be trusted. Returns `nil` for an empty
    /// input.
    static func combineDishEstimates(_ estimates: [DishEstimate]) -> DishEstimate? {
        guard !estimates.isEmpty else { return nil }
        guard estimates.count > 1 else { return estimates[0] }

        let sorted = estimates.sorted { $0.calories < $1.calories }
        let representative = sorted[sorted.count / 2]

        let totals = estimates.map { Double($0.calories) }
        let mean = totals.reduce(0, +) / Double(totals.count)
        let variance = totals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(totals.count)
        let spread = mean > 0 ? variance.squareRoot() / mean : 0  // coefficient of variation

        let adjusted = downgrade(representative.confidence, forSpread: spread)
        return DishEstimate(
            dishName: representative.dishName,
            grams: representative.grams,
            calories: representative.calories,
            ingredients: representative.ingredients,
            confidence: adjusted
        )
    }

    /// Lower a confidence level when independent attempts disagree too much.
    static func downgrade(_ confidence: Confidence, forSpread spread: Double) -> Confidence {
        if spread > 0.35 { return .low }
        if spread > 0.20 {
            switch confidence {
            case .high: return .medium
            case .medium, .low: return .low
            }
        }
        return confidence
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
}
