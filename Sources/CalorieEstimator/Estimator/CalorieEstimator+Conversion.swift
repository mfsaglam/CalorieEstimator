import FoundationModels

// MARK: - Internal Conversion (testable)
//
// The pure logic that turns model responses (and table hits) into ``MealEstimate``s:
// table resolution, single-food and dish building, confidence scoring, ensemble
// combination, and weight scaling. Kept separate from the inference-driving methods in
// ``CalorieEstimator`` so it can be unit-tested without the on-device model.

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

    /// Build an estimate straight from a nutrition-table hit — no model involved.
    ///
    /// Used by the text-field short-circuit: the calories are computed in code and the
    /// result is marked ``MealEstimate/Source/database`` with ``Confidence/high``.
    static func makeTableEstimate(foodName: String, grams: Int, caloriesPer100g: Int) -> MealEstimate {
        MealEstimate(
            foodName: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            grams: grams,
            calories: caloriesPer100g * grams / 100,
            source: .database,
            confidence: .high,
            ingredients: nil
        )
    }

    /// Build a single-food estimate, resolving the per-100g figure from the table first
    /// and falling back to the model's figure only on a miss.
    ///
    /// The calories are computed in code (`caloriesPer100g * grams / 100`) so the
    /// arithmetic is always consistent with the grams. Source is
    /// ``MealEstimate/Source/database`` (with ``Confidence/high``) on a table hit and
    /// ``MealEstimate/Source/model`` (with ``Confidence/medium``) otherwise.
    ///
    /// Throws ``CalorieEstimatorError/parsingFailed(response:)`` rather than returning a
    /// zero/garbage estimate when the name is empty or the numbers are non-positive.
    static func makeSingleFoodEstimate(
        foodName: String,
        englishName: String,
        modelCaloriesPer100g: Int,
        grams: Int,
        table: NutritionTable
    ) throws -> MealEstimate {
        let name = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolveCaloriesPer100g(
            table: table,
            englishName: englishName,
            displayName: name,
            modelValue: modelCaloriesPer100g
        )
        guard !name.isEmpty, grams > 0, resolved.value > 0 else {
            throw CalorieEstimatorError.parsingFailed(
                response: "foodName=\"\(foodName)\", grams=\(grams), caloriesPer100g=\(resolved.value)"
            )
        }
        return MealEstimate(
            foodName: name,
            grams: grams,
            calories: resolved.value * grams / 100,
            source: resolved.fromTable ? .database : .model,
            confidence: resolved.fromTable ? .high : .medium,
            ingredients: nil
        )
    }

    /// Build a decomposed dish estimate from one breakdown, resolving each ingredient
    /// through the table and deriving confidence from coverage, self-consistency, and
    /// plausibility.
    ///
    /// Returns `nil` when the breakdown has no usable ingredients (empty, or all
    /// non-positive), so the caller can treat it as a failed attempt.
    static func makeDecomposedEstimate(from response: RecipeResponse, using table: NutritionTable) -> MealEstimate? {
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
                source: resolved.fromTable ? .database : .model
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

        return MealEstimate(
            foodName: dishName,
            grams: totalGrams,
            calories: totalCalories,
            source: .decomposed,
            confidence: confidence,
            ingredients: ingredients
        )
    }

    /// Scale a decomposed estimate's energy density to a target weight.
    ///
    /// The dish is decomposed at one typical serving; on the text-field path the user
    /// states an explicit weight, so grams, calories, and every ingredient are scaled
    /// proportionally to it. Source and confidence are preserved. A non-positive current
    /// or target weight is returned unchanged.
    static func scale(_ estimate: MealEstimate, toGrams target: Int) -> MealEstimate {
        guard estimate.grams > 0, target > 0, target != estimate.grams else { return estimate }
        let factor = Double(target) / Double(estimate.grams)
        let scaledIngredients = estimate.ingredients?.map { ingredient in
            IngredientEstimate(
                name: ingredient.name,
                grams: Int((Double(ingredient.grams) * factor).rounded()),
                calories: Int((Double(ingredient.calories) * factor).rounded()),
                source: ingredient.source
            )
        }
        return MealEstimate(
            foodName: estimate.foodName,
            grams: target,
            calories: Int((Double(estimate.calories) * factor).rounded()),
            source: estimate.source,
            confidence: estimate.confidence,
            ingredients: scaledIngredients
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

    /// Combine several independent decomposed breakdowns into one estimate.
    ///
    /// The breakdown whose total is the median is returned as the representative result;
    /// the spread across attempts then adjusts confidence — tight agreement can't raise a
    /// weak breakdown, but wide scatter downgrades an otherwise confident one, since a
    /// model that keeps changing its mind shouldn't be trusted. Returns `nil` for an empty
    /// input.
    static func combineEstimates(_ estimates: [MealEstimate]) -> MealEstimate? {
        guard !estimates.isEmpty else { return nil }
        guard estimates.count > 1 else { return estimates[0] }

        let sorted = estimates.sorted { $0.calories < $1.calories }
        let representative = sorted[sorted.count / 2]

        let totals = estimates.map { Double($0.calories) }
        let mean = totals.reduce(0, +) / Double(totals.count)
        let variance = totals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(totals.count)
        let spread = mean > 0 ? variance.squareRoot() / mean : 0  // coefficient of variation

        let adjusted = representative.confidence.map { downgrade($0, forSpread: spread) }
        return MealEstimate(
            foodName: representative.foodName,
            grams: representative.grams,
            calories: representative.calories,
            source: representative.source,
            confidence: adjusted,
            ingredients: representative.ingredients
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
