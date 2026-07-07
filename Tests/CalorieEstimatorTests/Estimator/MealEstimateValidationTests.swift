import Testing
@testable import CalorieEstimator

// MARK: - MealEstimate (phrase-based) validation

@Suite("MealEstimate Validation")
struct MealEstimateValidationTests {

    private let noTable = EmptyNutritionTable()

    @Test("Computes calories from the model's caloriesPer100g when the table misses")
    func validResponse() throws {
        // 165 kcal/100g * 200 g / 100 = 330 kcal
        let response = PhraseNutritionResponse(foodName: "grilled chicken", grams: 200, caloriesPer100g: 165)
        let estimate = try CalorieEstimator.makeMealEstimate(from: response, using: noTable)
        #expect(estimate.foodName == "grilled chicken")
        #expect(estimate.grams == 200)
        #expect(estimate.calories == 330)
        #expect(estimate.source == .modelEstimate)
    }

    @Test("Prefers the table value over the model and marks the source as database")
    func tableOverridesModel() throws {
        // Table says 150/100g; the model's 999 is ignored. 150 * 100 / 100 = 150.
        let response = PhraseNutritionResponse(foodName: "eggs", grams: 100, caloriesPer100g: 999)
        let estimate = try CalorieEstimator.makeMealEstimate(from: response, using: StubNutritionTable(value: 150))
        #expect(estimate.calories == 150)
        #expect(estimate.source == .database)
    }

    @Test("Looks up the table by English name and keeps the localized display name")
    func translatedLookup() throws {
        // Turkish "yumurta" → English "eggs" → table 155/100g. 155 * 100 / 100 = 155.
        let response = PhraseNutritionResponse(foodName: "yumurta", foodNameEnglish: "eggs", grams: 100, caloriesPer100g: 999)
        let estimate = try CalorieEstimator.makeMealEstimate(from: response, using: LocalNutritionTable())
        #expect(estimate.calories == 155)
        #expect(estimate.source == .database)
        #expect(estimate.confidence == .high)
        // The display name stays in the user's language.
        #expect(estimate.foodName == "yumurta")
    }

    @Test("Trims whitespace from the food name")
    func trimsFoodName() throws {
        let response = PhraseNutritionResponse(foodName: "  salmon \n", grams: 227, caloriesPer100g: 208)
        let estimate = try CalorieEstimator.makeMealEstimate(from: response, using: noTable)
        #expect(estimate.foodName == "salmon")
    }

    @Test("Throws on an empty food name")
    func emptyFoodNameThrows() {
        let response = PhraseNutritionResponse(foodName: "   ", grams: 100, caloriesPer100g: 200)
        #expect(throws: CalorieEstimatorError.self) {
            try CalorieEstimator.makeMealEstimate(from: response, using: noTable)
        }
    }

    @Test("Throws on non-positive grams")
    func zeroGramsThrows() {
        let response = PhraseNutritionResponse(foodName: "rice", grams: 0, caloriesPer100g: 130)
        #expect(throws: CalorieEstimatorError.self) {
            try CalorieEstimator.makeMealEstimate(from: response, using: noTable)
        }
    }

    @Test("Throws when neither table nor model gives a positive figure")
    func zeroCaloriesThrows() {
        let response = PhraseNutritionResponse(foodName: "rice", grams: 100, caloriesPer100g: 0)
        #expect(throws: CalorieEstimatorError.self) {
            try CalorieEstimator.makeMealEstimate(from: response, using: noTable)
        }
    }
}
