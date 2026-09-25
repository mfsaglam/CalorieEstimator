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
        let ingredients = applying(modifications, to: recipe.ingredients, totalGrams: grams)
        guard !ingredients.isEmpty else { return nil }
        let allocations = allocate(total: grams, ratios: ingredients.map(\.ratio))
        var estimates: [IngredientEstimate] = []
        estimates.reserveCapacity(ingredients.count)

        for (ingredient, ingredientGrams) in zip(ingredients, allocations) {
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

    private static func applying(
        _ modifications: [MealModification],
        to base: [RecipeIngredient],
        totalGrams: Int
    ) -> [RecipeIngredient] {
        var result = base
        for modification in modifications {
            let localized = FoodNameNormalizer.normalize(modification.ingredientName)
            let english = FoodNameNormalizer.normalize(modification.ingredientNameEnglish)
            let index = result.firstIndex {
                let names = [
                    FoodNameNormalizer.normalize($0.canonicalName),
                    FoodNameNormalizer.normalize($0.nutritionLookupName),
                    FoodNameNormalizer.normalize($0.id.rawValue)
                ]
                return names.contains(localized) || names.contains(english)
            }
            let delta = min(0.5, max(0.01, Double(modification.estimatedGrams ?? max(1, totalGrams / 10)) / Double(totalGrams)))

            switch modification.kind {
            case .remove:
                if let index { result.remove(at: index) }
            case .add, .increase:
                if let index {
                    let item = result[index]
                    result[index] = RecipeIngredient(
                        id: item.id,
                        canonicalName: item.canonicalName,
                        nutritionLookupName: item.nutritionLookupName,
                        ratio: item.ratio + delta
                    )
                } else if modification.kind == .add, !english.isEmpty {
                    result.append(
                        RecipeIngredient(
                            id: IngredientID(rawValue: "explicit.\(english.replacingOccurrences(of: " ", with: "_"))"),
                            canonicalName: modification.ingredientName,
                            nutritionLookupName: modification.ingredientNameEnglish,
                            ratio: delta
                        )
                    )
                }
            case .decrease:
                if let index {
                    let item = result[index]
                    let reduced = max(0.001, item.ratio - delta)
                    result[index] = RecipeIngredient(
                        id: item.id,
                        canonicalName: item.canonicalName,
                        nutritionLookupName: item.nutritionLookupName,
                        ratio: reduced
                    )
                }
            }
        }
        return result
    }
}
