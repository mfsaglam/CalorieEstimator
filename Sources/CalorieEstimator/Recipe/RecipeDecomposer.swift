import Foundation

enum RecipeDecomposer {
    static func estimate(
        recipe: Recipe,
        grams: Int,
        displayName: String,
        nutritionTable: NutritionTable,
        modifications: [MealModification] = []
    ) -> MealEstimate? {
        guard grams > 0 else { return nil }
        guard let ingredients = applying(modifications, to: recipe.ingredients, totalGrams: grams),
              !ingredients.isEmpty else {
            return nil
        }

        let reservedTotal = ingredients.reduce(0) { $0 + $1.reservedGrams }
        guard reservedTotal <= grams else { return nil }
        let baseGrams = grams - reservedTotal
        let baseAllocations = baseGrams == 0
            ? Array(repeating: 0, count: ingredients.count)
            : allocate(total: baseGrams, ratios: ingredients.map(\.ingredient.ratio))
        guard baseAllocations.count == ingredients.count else { return nil }
        var allocations = zip(baseAllocations, ingredients).map { base, item in
            base + item.reservedGrams
        }

        // Explicit decreases are applied after the base allocation, then the
        // released mass is deterministically redistributed across other base
        // ingredients so the requested final mass remains unchanged.
        for index in ingredients.indices where ingredients[index].decreaseGrams > 0 {
            let decrease = min(ingredients[index].decreaseGrams, max(0, allocations[index] - 1))
            guard decrease > 0 else { continue }
            allocations[index] -= decrease
            let redistributionRatios = ingredients.indices.map { recipient in
                recipient == index ? 0 : ingredients[recipient].ingredient.ratio
            }
            let redistributed = allocate(total: decrease, ratios: redistributionRatios)
            guard redistributed.reduce(0, +) == decrease else { return nil }
            for recipient in allocations.indices {
                allocations[recipient] += redistributed[recipient]
            }
        }

        // Central deterministic boundary: no recipe estimate may escape with
        // component masses different from its declared total.
        guard allocations.reduce(0, +) == grams else { return nil }
        var estimates: [IngredientEstimate] = []
        estimates.reserveCapacity(ingredients.count)

        for (item, ingredientGrams) in zip(ingredients, allocations) where ingredientGrams > 0 {
            let ingredient = item.ingredient
            guard let density = nutritionTable.caloriesPer100g(for: ingredient.nutritionLookupName) else {
                return nil
            }
            estimates.append(
                IngredientEstimate(
                    name: ingredient.canonicalName,
                    grams: ingredientGrams,
                    calories: calories(density: density, grams: ingredientGrams),
                    source: .database,
                    ingredientID: ingredient.id
                )
            )
        }

        return MealEstimate(
            foodName: displayName,
            grams: grams,
            calories: estimates.reduce(0) { $0 + $1.calories },
            source: .decomposed,
            confidence: modifications.isEmpty ? .high : .medium,
            ingredients: estimates,
            provenance: .localRecipe,
            recipeID: recipe.id
        )
    }

    static func estimate(
        proposedIngredients: [ModelIngredientProposal],
        grams: Int,
        displayName: String,
        nutritionTable: NutritionTable
    ) -> MealEstimate? {
        let usable = proposedIngredients.filter { !$0.nameEnglish.isEmpty && $0.ratio > 0 }
        guard grams > 0, !usable.isEmpty, usable.count <= 12 else { return nil }
        let totalRatio = usable.reduce(0) { $0 + $1.ratio }
        guard totalRatio > 0 else { return nil }
        let allocations = allocate(total: grams, ratios: usable.map { $0.ratio / totalRatio })
        var estimates: [IngredientEstimate] = []

        for (ingredient, ingredientGrams) in zip(usable, allocations) {
            guard let density = nutritionTable.caloriesPer100g(for: ingredient.nameEnglish) else {
                return nil
            }
            estimates.append(
                IngredientEstimate(
                    name: ingredient.name,
                    grams: ingredientGrams,
                    calories: calories(density: density, grams: ingredientGrams),
                    source: .database
                )
            )
        }

        guard estimates.reduce(0, { $0 + $1.grams }) == grams else { return nil }

        return MealEstimate(
            foodName: displayName,
            grams: grams,
            calories: estimates.reduce(0) { $0 + $1.calories },
            source: .decomposed,
            confidence: .medium,
            ingredients: estimates,
            provenance: .modelAssistedRecipe
        )
    }

    /// Largest-remainder allocation guarantees the component masses exactly equal `total`.
    static func allocate(total: Int, ratios: [Double]) -> [Int] {
        guard total > 0, !ratios.isEmpty else { return [] }
        let positive = ratios.map { max(0, $0) }
        let ratioTotal = positive.reduce(0, +)
        guard ratioTotal > 0 else { return Array(repeating: 0, count: ratios.count) }

        let raw = positive.map { Double(total) * $0 / ratioTotal }
        var values = raw.map { Int($0.rounded(.down)) }
        var remainder = total - values.reduce(0, +)
        let order = raw.indices.sorted {
            let lhs = raw[$0] - Double(values[$0])
            let rhs = raw[$1] - Double(values[$1])
            return lhs == rhs ? $0 < $1 : lhs > rhs
        }
        for index in order where remainder > 0 {
            values[index] += 1
            remainder -= 1
        }
        return values
    }

    static func calories(density: Int, grams: Int) -> Int {
        Int((Double(density) * Double(grams) / 100).rounded())
    }

    private struct ModifiedIngredient {
        var ingredient: RecipeIngredient
        var reservedGrams: Int
        var decreaseGrams: Int
    }

    private static func applying(
        _ modifications: [MealModification],
        to base: [RecipeIngredient],
        totalGrams: Int
    ) -> [ModifiedIngredient]? {
        var result = base.map {
            ModifiedIngredient(ingredient: $0, reservedGrams: 0, decreaseGrams: 0)
        }
        for modification in modifications {
            let index: Int?
            if let ingredientID = modification.ingredientID {
                // A canonical modifier's stable ID is its sole authority. Names
                // remain metadata for display and legacy nutrition lookup only.
                index = result.firstIndex { $0.ingredient.id == ingredientID }
            } else {
                let localized = FoodNameNormalizer.normalize(modification.ingredientName)
                let english = FoodNameNormalizer.normalize(modification.ingredientNameEnglish)
                index = result.firstIndex {
                    let names = [
                        FoodNameNormalizer.normalize($0.ingredient.canonicalName),
                        FoodNameNormalizer.normalize($0.ingredient.nutritionLookupName),
                        FoodNameNormalizer.normalize($0.ingredient.id.rawValue)
                    ]
                    return names.contains(localized) || names.contains(english)
                }
            }
            let explicitGrams = modification.estimatedGrams.flatMap { $0 > 0 ? $0 : nil }
            let qualitativeDelta = min(
                0.5,
                max(0.01, Double(max(1, totalGrams / 10)) / Double(totalGrams))
            )

            switch modification.kind {
            case .remove:
                if let index { result.remove(at: index) }
            case .add, .increase:
                if let index {
                    if let explicitGrams {
                        result[index].reservedGrams += explicitGrams
                    } else {
                        let item = result[index].ingredient
                        result[index].ingredient = RecipeIngredient(
                            id: item.id,
                            canonicalName: item.canonicalName,
                            nutritionLookupName: item.nutritionLookupName,
                            ratio: item.ratio + qualitativeDelta
                        )
                    }
                } else if modification.kind == .add,
                          let ingredientID = modification.ingredientID,
                          !modification.ingredientNameEnglish.isEmpty {
                    result.append(
                        ModifiedIngredient(
                            ingredient: RecipeIngredient(
                                id: ingredientID,
                                canonicalName: modification.ingredientName,
                                nutritionLookupName: modification.ingredientNameEnglish,
                                ratio: explicitGrams == nil ? qualitativeDelta : 0
                            ),
                            reservedGrams: explicitGrams ?? 0,
                            decreaseGrams: 0
                        )
                    )
                } else if modification.kind == .add {
                    // Preserve the existing non-canonical long-tail path, but do
                    // not confuse generated names with trusted IngredientIDs.
                    let english = FoodNameNormalizer.normalize(modification.ingredientNameEnglish)
                    guard !english.isEmpty else { continue }
                    result.append(
                        ModifiedIngredient(
                            ingredient: RecipeIngredient(
                                id: IngredientID(rawValue: "explicit.\(english.replacingOccurrences(of: " ", with: "_"))"),
                                canonicalName: modification.ingredientName,
                                nutritionLookupName: modification.ingredientNameEnglish,
                                ratio: explicitGrams == nil ? qualitativeDelta : 0
                            ),
                            reservedGrams: explicitGrams ?? 0,
                            decreaseGrams: 0
                        )
                    )
                }
            case .decrease:
                if let index {
                    if let explicitGrams {
                        result[index].decreaseGrams += explicitGrams
                    } else {
                        let item = result[index].ingredient
                        let reduced = max(0.001, item.ratio - qualitativeDelta)
                        result[index].ingredient = RecipeIngredient(
                            id: item.id,
                            canonicalName: item.canonicalName,
                            nutritionLookupName: item.nutritionLookupName,
                            ratio: reduced
                        )
                    }
                }
            }
        }
        let reservedTotal = result.reduce(0) { $0 + $1.reservedGrams }
        guard reservedTotal <= totalGrams else { return nil }
        return result
    }
}
