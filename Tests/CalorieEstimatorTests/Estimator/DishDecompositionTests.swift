import Testing
@testable import CalorieEstimator

// MARK: - Dish Decomposition

@Suite("Dish Decomposition")
struct DishDecompositionTests {

    private let table = LocalNutritionTable()

    /// A creamy-mushroom-pasta breakdown; all ingredients resolve from the table.
    private func creamyMushroomPasta(holistic: Int) -> RecipeResponse {
        RecipeResponse(
            dishName: "kremalı mantarlı makarna",
            ingredients: [
                RecipeIngredientResponse(name: "makarna", nameEnglish: "pasta", grams: 120, caloriesPer100g: 999),
                RecipeIngredientResponse(name: "krema", nameEnglish: "cream", grams: 40, caloriesPer100g: 999),
                RecipeIngredientResponse(name: "mantar", nameEnglish: "mushroom", grams: 60, caloriesPer100g: 999),
            ],
            holisticCalories: holistic
        )
    }

    @Test("Sums ingredient calories from the table into a decomposed estimate")
    func summation() throws {
        // pasta 157*120/100=188, cream 340*40/100=136, mushroom 22*60/100=13 → 337.
        let estimate = try #require(CalorieEstimator.makeDecomposedEstimate(from: creamyMushroomPasta(holistic: 340), using: table))
        #expect(estimate.calories == 337)
        #expect(estimate.grams == 220)
        #expect(estimate.source == .decomposed)
        #expect(estimate.foodName == "kremalı mantarlı makarna")
        let ingredients = try #require(estimate.ingredients)
        #expect(ingredients.count == 3)
        #expect(ingredients.allSatisfy { $0.source == .database })
    }

    @Test("Full table coverage + holistic agreement → high confidence")
    func highConfidence() throws {
        // Sum 337 vs holistic 340 → divergence ~1%, coverage 100%.
        let estimate = try #require(CalorieEstimator.makeDecomposedEstimate(from: creamyMushroomPasta(holistic: 340), using: table))
        #expect(estimate.confidence == .high)
    }

    @Test("Ingredient sum wildly off the holistic estimate → low confidence")
    func divergenceLowersConfidence() throws {
        // Sum 337 vs holistic 1500 → divergence > 0.75 → low, despite full coverage.
        let estimate = try #require(CalorieEstimator.makeDecomposedEstimate(from: creamyMushroomPasta(holistic: 1500), using: table))
        #expect(estimate.confidence == .low)
    }

    @Test("Implausible energy density → low confidence")
    func implausibleDensity() throws {
        // A single model-only ingredient at 950 kcal/100g → dish density 950 > 900 → low.
        let response = RecipeResponse(
            dishName: "mystery",
            ingredients: [
                RecipeIngredientResponse(name: "goo", nameEnglish: "unknownsubstance", grams: 10, caloriesPer100g: 950),
            ],
            holisticCalories: 95
        )
        let estimate = try #require(CalorieEstimator.makeDecomposedEstimate(from: response, using: table))
        #expect(estimate.confidence == .low)
    }

    @Test("Model-only ingredients (no table hits) cap confidence below high")
    func modelOnlyIngredients() throws {
        let response = RecipeResponse(
            dishName: "enginarlı pilav",
            ingredients: [
                RecipeIngredientResponse(name: "enginar", nameEnglish: "artichoke", grams: 80, caloriesPer100g: 47),
                RecipeIngredientResponse(name: "safran", nameEnglish: "saffron", grams: 1, caloriesPer100g: 310),
            ],
            holisticCalories: 40
        )
        let estimate = try #require(CalorieEstimator.makeDecomposedEstimate(from: response, using: table))
        let ingredients = try #require(estimate.ingredients)
        #expect(ingredients.allSatisfy { $0.source == .model })
        #expect(estimate.confidence != .high)
    }

    @Test("Empty or unusable breakdown returns nil")
    func emptyBreakdown() {
        let response = RecipeResponse(dishName: "nothing", ingredients: [], holisticCalories: 100)
        #expect(CalorieEstimator.makeDecomposedEstimate(from: response, using: table) == nil)
    }

    @Test("Ensemble returns the median-total breakdown")
    func ensembleMedian() throws {
        let low = try #require(CalorieEstimator.makeDecomposedEstimate(from: creamyMushroomPasta(holistic: 337), using: table))
        let mid = MealEstimate(foodName: "d", grams: 200, calories: 500, source: .decomposed, confidence: .high, ingredients: low.ingredients)
        let high = MealEstimate(foodName: "d", grams: 200, calories: 900, source: .decomposed, confidence: .high, ingredients: low.ingredients)
        let combined = try #require(CalorieEstimator.combineEstimates([high, low, mid]))
        #expect(combined.calories == 500) // median of {337, 500, 900}
    }

    @Test("Wide disagreement across attempts downgrades confidence")
    func ensembleSpreadDowngrades() {
        // Totals 300 / 600 / 900 → mean 600, CV ≈ 0.41 (> 0.35) → forced to low.
        #expect(CalorieEstimator.downgrade(.high, forSpread: 0.41) == .low)
        // Moderate spread downgrades high → medium.
        #expect(CalorieEstimator.downgrade(.high, forSpread: 0.25) == .medium)
        // Tight agreement leaves it unchanged.
        #expect(CalorieEstimator.downgrade(.high, forSpread: 0.05) == .high)
    }

    // MARK: - Weight scaling (text-field path)

    @Test("Scales a decomposed serving's calories and ingredients to a target weight")
    func scalesToTargetWeight() throws {
        // Serving: 220 g / 337 kcal. Scale to 440 g → 2× → 674 kcal, ingredient grams doubled.
        let serving = try #require(CalorieEstimator.makeDecomposedEstimate(from: creamyMushroomPasta(holistic: 340), using: table))
        let scaled = CalorieEstimator.scale(serving, toGrams: 440)
        #expect(scaled.grams == 440)
        #expect(scaled.calories == 674)
        #expect(scaled.source == .decomposed)
        #expect(scaled.confidence == serving.confidence)
        let ingredients = try #require(scaled.ingredients)
        #expect(ingredients.first?.grams == 240) // pasta 120 → 240
    }

    @Test("Scaling to the same weight is a no-op")
    func scaleNoOp() throws {
        let serving = try #require(CalorieEstimator.makeDecomposedEstimate(from: creamyMushroomPasta(holistic: 340), using: table))
        let scaled = CalorieEstimator.scale(serving, toGrams: serving.grams)
        #expect(scaled == serving)
    }
}
