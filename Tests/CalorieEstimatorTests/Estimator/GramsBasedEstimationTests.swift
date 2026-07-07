import Testing
@testable import CalorieEstimator

// MARK: - Grams-Based Estimation (makeEstimation from NutritionResponse)

@Suite("Grams-Based Estimation")
struct GramsBasedEstimationTests {

    // A made-up food name that the bundled table won't resolve, so these tests
    // exercise the pure model-figure math.
    private let noTable = EmptyNutritionTable()

    @Test("Computes calories and explanation from NutritionResponse")
    func basicEstimation() {
        let response = NutritionResponse(caloriesPer100g: 200, foodName: "Chicken breast")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 100, using: noTable)
        #expect(result.calories == 200)
        #expect(result.explanation == "Chicken breast has ~200 kcal per 100g.")
        #expect(result.estimatedGrams == nil)
        #expect(result.confidence == .medium)
    }

    @Test("Scales correctly for amounts above 100g")
    func aboveHundredGrams() {
        let response = NutritionResponse(caloriesPer100g: 200, foodName: "Rice")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 350, using: noTable)
        #expect(result.calories == 700)
    }

    @Test("Scales correctly for amounts below 100g")
    func belowHundredGrams() {
        let response = NutritionResponse(caloriesPer100g: 200, foodName: "Rice")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 50, using: noTable)
        #expect(result.calories == 100)
    }

    @Test("Returns zero calories for zero grams")
    func zeroGrams() {
        let response = NutritionResponse(caloriesPer100g: 500, foodName: "Chocolate")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 0, using: noTable)
        #expect(result.calories == 0)
    }

    @Test("Returns zero calories for zero kcal/100g")
    func zeroCaloriesPer100g() {
        let response = NutritionResponse(caloriesPer100g: 0, foodName: "Water")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 250, using: noTable)
        #expect(result.calories == 0)
    }

    @Test("Integer division truncates fractional calories")
    func integerTruncation() {
        // 155 * 33 / 100 = 5115 / 100 = 51
        let response = NutritionResponse(caloriesPer100g: 155, foodName: "Egg")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 33, using: noTable)
        #expect(result.calories == 51)
    }

    @Test("Handles 1 gram correctly")
    func oneGram() {
        let response = NutritionResponse(caloriesPer100g: 200, foodName: "Bread")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 1, using: noTable)
        #expect(result.calories == 2)
    }

    @Test("Handles very large gram value")
    func veryLargeGrams() {
        let response = NutritionResponse(caloriesPer100g: 100, foodName: "Apple")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 10000, using: noTable)
        #expect(result.calories == 10000)
    }

    @Test("Handles very large calorie value")
    func largeCalorieValue() {
        let response = NutritionResponse(caloriesPer100g: 9000, foodName: "Pure fat")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 100, using: noTable)
        #expect(result.calories == 9000)
    }

    @Test("Prefers the table value and reports high confidence")
    func tableOverridesModel() {
        // Table says banana is 89/100g; the model's 500 is ignored. 89 * 200 / 100 = 178.
        let response = NutritionResponse(caloriesPer100g: 500, foodName: "banana")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 200, using: LocalNutritionTable())
        #expect(result.calories == 178)
        #expect(result.confidence == .high)
    }

    @Test("Looks up the table by English name for a non-English food")
    func translatedLookup() {
        // Turkish "muz" → English "banana" → table 89/100g. 89 * 200 / 100 = 178.
        let response = NutritionResponse(caloriesPer100g: 500, foodName: "muz", foodNameEnglish: "banana")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 200, using: LocalNutritionTable())
        #expect(result.calories == 178)
        #expect(result.confidence == .high)
        // The display name stays in the user's language.
        #expect(result.explanation == "muz has ~89 kcal per 100g.")
    }
}
