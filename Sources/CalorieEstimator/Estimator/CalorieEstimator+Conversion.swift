import Foundation

// MARK: - Internal Conversion (testable)
//
// Pure table resolution, single-food building, and weight scaling. Kept separate
// from inference so it can be unit-tested without Apple Intelligence.

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
            calories: RecipeDecomposer.calories(density: caloriesPer100g, grams: grams),
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
    /// ``MealEstimate/Source/model`` (with ``Confidence/low``) otherwise.
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
            calories: RecipeDecomposer.calories(density: resolved.value, grams: grams),
            source: resolved.fromTable ? .database : .model,
            confidence: resolved.fromTable ? .high : .low,
            ingredients: nil
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
        let scaledGrams = estimate.ingredients.map {
            RecipeDecomposer.allocate(total: target, ratios: $0.map { Double($0.grams) })
        }
        let scaledIngredients = estimate.ingredients?.enumerated().map { index, ingredient in
            IngredientEstimate(
                name: ingredient.name,
                grams: scaledGrams?[index] ?? Int((Double(ingredient.grams) * factor).rounded()),
                calories: Int((Double(ingredient.calories) * factor).rounded()),
                source: ingredient.source,
                ingredientID: ingredient.ingredientID
            )
        }
        return MealEstimate(
            foodName: estimate.foodName,
            grams: target,
            calories: Int((Double(estimate.calories) * factor).rounded()),
            source: estimate.source,
            confidence: estimate.confidence,
            ingredients: scaledIngredients,
            provenance: estimate.provenance,
            recipeID: estimate.recipeID
        )
    }

}
