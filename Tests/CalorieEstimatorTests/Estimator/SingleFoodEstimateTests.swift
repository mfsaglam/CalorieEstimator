import Testing
@testable import CalorieEstimator

// MARK: - Single-food estimate building (makeSingleFoodEstimate / makeTableEstimate)

@Suite("Single-Food Estimate")
struct SingleFoodEstimateTests {

    private let noTable = EmptyNutritionTable()

    @Test("Computes calories from the model's figure when the table misses")
    func modelFigureWhenTableMisses() throws {
        // 165 kcal/100g * 200 g / 100 = 330 kcal
        let estimate = try CalorieEstimator.makeSingleFoodEstimate(
            foodName: "grilled chicken", englishName: "grilled chicken",
            modelCaloriesPer100g: 165, grams: 200, table: noTable
        )
        #expect(estimate.foodName == "grilled chicken")
        #expect(estimate.grams == 200)
        #expect(estimate.calories == 330)
        #expect(estimate.source == .model)
        #expect(estimate.confidence == .medium)
        #expect(estimate.ingredients == nil)
    }

    @Test("Prefers the table value over the model and marks the source as database")
    func tableOverridesModel() throws {
        // Table says 150/100g; the model's 999 is ignored. 150 * 100 / 100 = 150.
        let estimate = try CalorieEstimator.makeSingleFoodEstimate(
            foodName: "eggs", englishName: "eggs",
            modelCaloriesPer100g: 999, grams: 100, table: StubNutritionTable(value: 150)
        )
        #expect(estimate.calories == 150)
        #expect(estimate.source == .database)
        #expect(estimate.confidence == .high)
    }

    @Test("Looks up the table by English name and keeps the localized display name")
    func translatedLookup() throws {
        // Turkish "yumurta" → English "eggs" → table 155/100g. 155 * 100 / 100 = 155.
        let estimate = try CalorieEstimator.makeSingleFoodEstimate(
            foodName: "yumurta", englishName: "eggs",
            modelCaloriesPer100g: 999, grams: 100, table: LocalNutritionTable()
        )
        #expect(estimate.calories == 155)
        #expect(estimate.source == .database)
        #expect(estimate.confidence == .high)
        #expect(estimate.foodName == "yumurta") // display name stays in the user's language
    }

    @Test("Trims whitespace from the food name")
    func trimsFoodName() throws {
        let estimate = try CalorieEstimator.makeSingleFoodEstimate(
            foodName: "  salmon \n", englishName: "salmon",
            modelCaloriesPer100g: 208, grams: 227, table: noTable
        )
        #expect(estimate.foodName == "salmon")
    }

    @Test("Throws on an empty food name")
    func emptyFoodNameThrows() {
        #expect(throws: CalorieEstimatorError.self) {
            try CalorieEstimator.makeSingleFoodEstimate(
                foodName: "   ", englishName: "", modelCaloriesPer100g: 200, grams: 100, table: noTable
            )
        }
    }

    @Test("Throws on non-positive grams")
    func zeroGramsThrows() {
        #expect(throws: CalorieEstimatorError.self) {
            try CalorieEstimator.makeSingleFoodEstimate(
                foodName: "rice", englishName: "rice", modelCaloriesPer100g: 130, grams: 0, table: noTable
            )
        }
    }

    @Test("Throws when neither table nor model gives a positive figure")
    func zeroCaloriesThrows() {
        #expect(throws: CalorieEstimatorError.self) {
            try CalorieEstimator.makeSingleFoodEstimate(
                foodName: "rice", englishName: "rice", modelCaloriesPer100g: 0, grams: 100, table: EmptyNutritionTable()
            )
        }
    }

    @Test("Table estimate builds a database-sourced result")
    func tableEstimate() {
        // 130 kcal/100g * 250 g / 100 = 325 kcal
        let estimate = CalorieEstimator.makeTableEstimate(foodName: "white rice", grams: 250, caloriesPer100g: 130)
        #expect(estimate.calories == 325)
        #expect(estimate.source == .database)
        #expect(estimate.confidence == .high)
        #expect(estimate.ingredients == nil)
    }
}
