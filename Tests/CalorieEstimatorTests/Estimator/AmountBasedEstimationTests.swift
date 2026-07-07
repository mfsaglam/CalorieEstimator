import Testing
@testable import CalorieEstimator

// MARK: - Amount-Based Estimation (makeEstimation from AmountNutritionResponse)

@Suite("Amount-Based Estimation")
struct AmountBasedEstimationTests {

    private let noTable = EmptyNutritionTable()

    @Test("Computes calories, explanation, and estimatedGrams")
    func basicEstimation() {
        let response = AmountNutritionResponse(caloriesPer100g: 155, estimatedGrams: 120, foodName: "Nonexistentfood")
        let result = CalorieEstimator.makeEstimation(from: response, using: noTable)
        #expect(result.calories == 186) // 155 * 120 / 100
        #expect(result.estimatedGrams == 120)
        #expect(result.explanation == "Nonexistentfood has ~155 kcal per 100g.")
        #expect(result.confidence == .medium)
    }

    @Test("Returns zero calories when estimatedGrams is zero")
    func zeroEstimatedGrams() {
        let response = AmountNutritionResponse(caloriesPer100g: 200, estimatedGrams: 0, foodName: "Nonexistentfood")
        let result = CalorieEstimator.makeEstimation(from: response, using: noTable)
        #expect(result.calories == 0)
        #expect(result.estimatedGrams == 0)
    }

    @Test("Returns zero calories when caloriesPer100g is zero")
    func zeroCaloriesPer100g() {
        let response = AmountNutritionResponse(caloriesPer100g: 0, estimatedGrams: 250, foodName: "Nonexistentfood")
        let result = CalorieEstimator.makeEstimation(from: response, using: noTable)
        #expect(result.calories == 0)
        #expect(result.estimatedGrams == 250)
    }

    @Test("Integer division truncates fractional calories")
    func integerTruncation() {
        // 155 * 33 / 100 = 5115 / 100 = 51
        let response = AmountNutritionResponse(caloriesPer100g: 155, estimatedGrams: 33, foodName: "Nonexistentfood")
        let result = CalorieEstimator.makeEstimation(from: response, using: noTable)
        #expect(result.calories == 51)
    }

    @Test("Handles very large values")
    func largeValues() {
        let response = AmountNutritionResponse(caloriesPer100g: 9000, estimatedGrams: 500, foodName: "Nonexistentfood")
        let result = CalorieEstimator.makeEstimation(from: response, using: noTable)
        #expect(result.calories == 45000)
        #expect(result.estimatedGrams == 500)
    }

    @Test("Prefers the table value and reports high confidence")
    func tableOverridesModel() {
        // Table says egg is 155/100g; the model's 900 is ignored. 155 * 100 / 100 = 155.
        let response = AmountNutritionResponse(caloriesPer100g: 900, estimatedGrams: 100, foodName: "eggs")
        let result = CalorieEstimator.makeEstimation(from: response, using: LocalNutritionTable())
        #expect(result.calories == 155)
        #expect(result.confidence == .high)
    }
}
