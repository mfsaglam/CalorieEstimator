import Testing
@testable import CalorieEstimator

@Suite("Bounded Fallback Termination")
struct FallbackTerminationTests {
    @Test("Failed model decomposition falls through once to model nutrition")
    func decompositionFailureUsesModelNutrition() async throws {
        let request = unknownRequest(modelCalories: 175)
        let estimator = CalorieEstimator(
            nutritionTable: EmptyNutritionTable(),
            recipeDatabase: EmptyRecipeDatabase(),
            mealParser: StubMealRequestParser(request: request)
        )

        let estimate = try await estimator.estimate(phrase: "unknown global dish 200g")

        #expect(estimate.grams == 200)
        #expect(estimate.calories == 350)
        #expect(estimate.provenance == .modelNutrition)
        #expect(estimate.confidence == .low)
    }

    @Test("Failed model decomposition and nutrition terminate with a controlled error")
    func exhaustedFallbacksThrow() async {
        let estimator = CalorieEstimator(
            nutritionTable: EmptyNutritionTable(),
            recipeDatabase: EmptyRecipeDatabase(),
            mealParser: StubMealRequestParser(request: unknownRequest(modelCalories: nil))
        )

        await #expect(throws: CalorieEstimatorError.self) {
            try await estimator.estimate(phrase: "unknown global dish 200g")
        }
    }

    @Test("A suspended semantic parser terminates at the deadline")
    func parserTimeout() async {
        let estimator = CalorieEstimator(
            nutritionTable: EmptyNutritionTable(),
            recipeDatabase: EmptyRecipeDatabase(),
            mealParser: SuspendingMealRequestParser(),
            modelTimeout: .milliseconds(20)
        )

        do {
            _ = try await estimator.estimate(phrase: "unknown global dish 200g")
            Issue.record("Expected the bounded parser deadline to throw")
        } catch CalorieEstimatorError.modelTimedOut {
            // Expected controlled terminal state.
        } catch {
            Issue.record("Unexpected timeout error: \(error)")
        }
    }

    @Test("Cancellation propagates through the parser timeout boundary")
    func cancellationPropagation() async {
        let estimator = CalorieEstimator(
            nutritionTable: EmptyNutritionTable(),
            recipeDatabase: EmptyRecipeDatabase(),
            mealParser: SuspendingMealRequestParser(),
            modelTimeout: .seconds(60)
        )
        let task = Task {
            try await estimator.estimate(phrase: "unknown global dish 200g")
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    @Test("Explicit plus construction may add modifier mass outside the base quantity")
    func baseQuantityPlusModifierMass() async throws {
        let request = MealRequest(
            displayName: "chicken rice plus 30g mushroom",
            lookupName: "chicken rice plus 30g mushroom",
            baseDisplayName: "chicken rice",
            baseLookupName: "chicken rice",
            recipeID: "global.chicken_rice.default",
            languageCode: "en",
            localeIdentifier: nil,
            cuisine: nil,
            quantity: .grams(200),
            quantityScope: .baseRecipe,
            modifications: [
                MealModification(
                    kind: .add,
                    ingredientName: "mushroom",
                    ingredientNameEnglish: "mushroom",
                    estimatedGrams: 30
                )
            ],
            isCompositeDish: true,
            proposedIngredients: [],
            modelCaloriesPer100g: nil
        )
        let estimator = CalorieEstimator(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: LocalRecipeDatabase(),
            mealParser: StubMealRequestParser(request: request)
        )

        let estimate = try await estimator.estimate(phrase: "200g chicken rice plus 30g mushroom")
        let ingredients = try #require(estimate.ingredients)

        #expect(estimate.grams == 230)
        #expect(ingredients.first { FoodNameNormalizer.normalize($0.name) == "mushroom" }?.grams == 30)
        #expect(ingredients.filter { FoodNameNormalizer.normalize($0.name) != "mushroom" }
            .reduce(0) { $0 + $1.grams } == 200)
        #expect(ingredients.reduce(0) { $0 + $1.grams } == 230)
    }

    private func unknownRequest(modelCalories: Int?) -> MealRequest {
        MealRequest(
            displayName: "unknown global dish",
            lookupName: "unknown global dish",
            baseDisplayName: "unknown global dish",
            baseLookupName: "unknown global dish",
            recipeID: nil,
            languageCode: "en",
            localeIdentifier: nil,
            cuisine: nil,
            quantity: .grams(200),
            quantityScope: .finalMeal,
            modifications: [],
            isCompositeDish: true,
            proposedIngredients: [
                ModelIngredientProposal(name: "unknown component", nameEnglish: "unknown component", ratio: 1)
            ],
            modelCaloriesPer100g: modelCalories
        )
    }
}

private struct SuspendingMealRequestParser: MealRequestParsing {
    func parse(_ input: String, recipeDatabase: any RecipeDatabase) async throws -> MealRequest {
        try await Task.sleep(for: .seconds(60))
        throw CalorieEstimatorError.parsingFailed(response: "unexpected parser wake-up")
    }
}
