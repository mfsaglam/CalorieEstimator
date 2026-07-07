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

    @Test("Sums ingredient calories from the table and keeps the breakdown")
    func summation() throws {
        // pasta 157*120/100=188, cream 340*40/100=136, mushroom 22*60/100=13 → 337.
        let estimate = try #require(CalorieEstimator.makeDishEstimate(from: creamyMushroomPasta(holistic: 340), using: table))
        #expect(estimate.calories == 337)
        #expect(estimate.grams == 220)
        #expect(estimate.ingredients.count == 3)
        #expect(estimate.ingredients.allSatisfy { $0.source == .database })
        #expect(estimate.dishName == "kremalı mantarlı makarna")
    }

    @Test("Full table coverage + holistic agreement → high confidence")
    func highConfidence() throws {
        // Sum 337 vs holistic 340 → divergence ~1%, coverage 100%.
        let estimate = try #require(CalorieEstimator.makeDishEstimate(from: creamyMushroomPasta(holistic: 340), using: table))
        #expect(estimate.confidence == .high)
    }

    @Test("Ingredient sum wildly off the holistic estimate → low confidence")
    func divergenceLowersConfidence() throws {
        // Sum 337 vs holistic 1500 → divergence > 0.75 → low, despite full coverage.
        let estimate = try #require(CalorieEstimator.makeDishEstimate(from: creamyMushroomPasta(holistic: 1500), using: table))
        #expect(estimate.confidence == .low)
    }

    @Test("Implausible energy density → low confidence")
    func implausibleDensity() throws {
        // A single model-only ingredient at 950 kcal/100g → dish density 950 > 900 upper
        // bound → implausible → low, regardless of other signals.
        let response = RecipeResponse(
            dishName: "mystery",
            ingredients: [
                RecipeIngredientResponse(name: "goo", nameEnglish: "unknownsubstance", grams: 10, caloriesPer100g: 950),
            ],
            holisticCalories: 95
        )
        let estimate = try #require(CalorieEstimator.makeDishEstimate(from: response, using: table))
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
        let estimate = try #require(CalorieEstimator.makeDishEstimate(from: response, using: table))
        #expect(estimate.ingredients.allSatisfy { $0.source == .modelEstimate })
        #expect(estimate.confidence != .high)
    }

    @Test("Empty or unusable breakdown returns nil")
    func emptyBreakdown() {
        let response = RecipeResponse(dishName: "nothing", ingredients: [], holisticCalories: 100)
        #expect(CalorieEstimator.makeDishEstimate(from: response, using: table) == nil)
    }

    @Test("Ensemble returns the median-total breakdown")
    func ensembleMedian() throws {
        let low = try #require(CalorieEstimator.makeDishEstimate(from: creamyMushroomPasta(holistic: 337), using: table))
        let mid = DishEstimate(dishName: "d", grams: 200, calories: 500, ingredients: low.ingredients, confidence: .high)
        let high = DishEstimate(dishName: "d", grams: 200, calories: 900, ingredients: low.ingredients, confidence: .high)
        let combined = try #require(CalorieEstimator.combineDishEstimates([high, low, mid]))
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
}
