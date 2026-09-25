import Foundation

struct MealResolver: Sendable {
    let nutritionTable: any NutritionTable
    let recipeDatabase: any RecipeDatabase

    func knownEstimate(name: String, grams: Int) async throws -> MealEstimate? {
        let query = RecipeQuery(name: name)
        if let recipe = try await recipeDatabase.recipe(matching: query) {
            return RecipeDecomposer.estimate(
                recipe: recipe,
                grams: grams,
                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                nutritionTable: nutritionTable
            )
        }
        guard let density = nutritionTable.caloriesPer100g(for: name) else { return nil }
        return CalorieEstimator.makeTableEstimate(foodName: name, grams: grams, caloriesPer100g: density)
    }

    func resolve(_ request: MealRequest, overridingGrams: Int? = nil) async throws -> MealEstimate {
        let name = request.displayName.isEmpty ? request.lookupName : request.displayName
        guard !name.isEmpty else {
            throw CalorieEstimatorError.parsingFailed(response: "empty normalized food name")
        }

        // Recipe resolution uses only explicit semantic identities, never arbitrary
        // substrings. The unmodified base dish is authoritative when modifiers exist.
        let recipeCandidates = uniqueNames([
            request.baseDisplayName,
            request.baseLookupName,
            request.displayName,
            request.lookupName
        ])
        for candidate in recipeCandidates {
            if let recipe = try await recipe(matching: candidate, request: request) {
                return try makeRecipeEstimate(recipe, request: request, name: name, overridingGrams: overridingGrams)
            }
        }

        if let density = nutritionTable.caloriesPer100g(for: request.displayName) {
            let grams = try resolveGrams(request.quantity, defaultServingGrams: nil, override: overridingGrams)
            return CalorieEstimator.makeTableEstimate(foodName: name, grams: grams, caloriesPer100g: density)
        }
        let lookup = request.lookupName.isEmpty ? name : request.lookupName
        let grams = try resolveGrams(request.quantity, defaultServingGrams: nil, override: overridingGrams)
        if let density = nutritionTable.caloriesPer100g(for: lookup) {
            return CalorieEstimator.makeTableEstimate(foodName: name, grams: grams, caloriesPer100g: density)
        }

        if request.isCompositeDish,
           let estimate = RecipeDecomposer.estimate(
               proposedIngredients: request.proposedIngredients,
               grams: grams,
               displayName: name,
               nutritionTable: nutritionTable
           ) {
            return estimate
        }

        guard let density = request.modelCaloriesPer100g, density > 0 else {
            throw CalorieEstimatorError.parsingFailed(response: "no local or model nutrition for \(name)")
        }
        return MealEstimate(
            foodName: name,
            grams: grams,
            calories: RecipeDecomposer.calories(density: density, grams: grams),
            source: .model,
            confidence: .low,
            ingredients: nil,
            provenance: .modelNutrition
        )
    }

    private func uniqueNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = FoodNameNormalizer.normalize(trimmed)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return trimmed
        }
    }

    private func recipe(matching name: String, request: MealRequest) async throws -> Recipe? {
        let candidate = try await recipeDatabase.recipe(
            matching: RecipeQuery(
                name: name,
                languageCode: request.languageCode,
                localeIdentifier: request.localeIdentifier,
                cuisine: request.cuisine
            )
        )
        // The recipe database's independent alias match is authoritative. A generated
        // ID is accepted only when the exact row corroborates that alias match.
        if let candidate,
           let proposedID = request.recipeID,
           let proposed = try await recipeDatabase.recipe(id: proposedID),
           proposed.id == candidate.id {
            return proposed
        }
        return candidate
    }

    private func makeRecipeEstimate(
        _ recipe: Recipe,
        request: MealRequest,
        name: String,
        overridingGrams: Int?
    ) throws -> MealEstimate {
        let grams = try resolveGrams(
            request.quantity,
            defaultServingGrams: recipe.defaultServingGrams,
            override: overridingGrams
        )
        guard let estimate = RecipeDecomposer.estimate(
            recipe: recipe,
            grams: grams,
            displayName: name,
            nutritionTable: nutritionTable,
            modifications: request.modifications
        ) else {
            throw CalorieEstimatorError.parsingFailed(
                response: "local recipe \(recipe.id.rawValue) contains an ingredient missing from NutritionTable"
            )
        }
        return estimate
    }

    private func resolveGrams(
        _ quantity: MealQuantity,
        defaultServingGrams: Int?,
        override: Int?
    ) throws -> Int {
        if let override, override > 0 { return override }
        let value: Double
        switch quantity.unit {
        case .gram: value = quantity.amount
        case .kilogram: value = quantity.amount * 1_000
        case .ounce: value = quantity.amount * 28.349_523_125
        case .pound: value = quantity.amount * 453.592_37
        case .milliliter:
            if let estimated = quantity.estimatedGrams {
                value = Double(estimated)
            } else {
                value = quantity.amount
            }
        case .liter:
            if let estimated = quantity.estimatedGrams {
                value = Double(estimated)
            } else {
                value = quantity.amount * 1_000
            }
        case .serving, .bowl:
            if let defaultServingGrams {
                value = quantity.amount * Double(defaultServingGrams)
            } else if let estimated = quantity.estimatedGrams {
                value = Double(estimated)
            } else {
                throw CalorieEstimatorError.parsingFailed(response: "portion has no resolvable gram weight")
            }
        case .cup, .slice, .piece, .item:
            if let estimated = quantity.estimatedGrams {
                value = Double(estimated)
            } else if let defaultServingGrams {
                value = quantity.amount * Double(defaultServingGrams)
            } else {
                throw CalorieEstimatorError.parsingFailed(response: "portion has no resolvable gram weight")
            }
        }
        let grams = Int(value.rounded())
        guard grams > 0 else {
            throw CalorieEstimatorError.parsingFailed(response: "resolved weight must be positive")
        }
        return grams
    }
}
