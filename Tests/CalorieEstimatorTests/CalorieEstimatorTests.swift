import Testing
@testable import CalorieEstimator

// MARK: - Grams-Based Estimation (makeEstimation from NutritionResponse)

@Suite("Grams-Based Estimation")
struct GramsBasedEstimationTests {

    @Test("Computes calories and explanation from NutritionResponse")
    func basicEstimation() {
        let response = NutritionResponse(caloriesPer100g: 200, foodName: "Chicken breast")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 100)
        #expect(result.calories == 200)
        #expect(result.explanation == "Chicken breast has ~200 kcal per 100g.")
        #expect(result.estimatedGrams == nil)
    }

    @Test("Scales correctly for amounts above 100g")
    func aboveHundredGrams() {
        let response = NutritionResponse(caloriesPer100g: 200, foodName: "Rice")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 350)
        #expect(result.calories == 700)
    }

    @Test("Scales correctly for amounts below 100g")
    func belowHundredGrams() {
        let response = NutritionResponse(caloriesPer100g: 200, foodName: "Rice")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 50)
        #expect(result.calories == 100)
    }

    @Test("Returns zero calories for zero grams")
    func zeroGrams() {
        let response = NutritionResponse(caloriesPer100g: 500, foodName: "Chocolate")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 0)
        #expect(result.calories == 0)
    }

    @Test("Returns zero calories for zero kcal/100g")
    func zeroCaloriesPer100g() {
        let response = NutritionResponse(caloriesPer100g: 0, foodName: "Water")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 250)
        #expect(result.calories == 0)
    }

    @Test("Integer division truncates fractional calories")
    func integerTruncation() {
        // 155 * 33 / 100 = 5115 / 100 = 51
        let response = NutritionResponse(caloriesPer100g: 155, foodName: "Egg")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 33)
        #expect(result.calories == 51)
    }

    @Test("Handles 1 gram correctly")
    func oneGram() {
        let response = NutritionResponse(caloriesPer100g: 200, foodName: "Bread")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 1)
        #expect(result.calories == 2)
    }

    @Test("Handles very large gram value")
    func veryLargeGrams() {
        let response = NutritionResponse(caloriesPer100g: 100, foodName: "Apple")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 10000)
        #expect(result.calories == 10000)
    }

    @Test("Handles very large calorie value")
    func largeCalorieValue() {
        let response = NutritionResponse(caloriesPer100g: 9000, foodName: "Pure fat")
        let result = CalorieEstimator.makeEstimation(from: response, grams: 100)
        #expect(result.calories == 9000)
    }
}

// MARK: - Amount-Based Estimation (makeEstimation from AmountNutritionResponse)

@Suite("Amount-Based Estimation")
struct AmountBasedEstimationTests {

    @Test("Computes calories, explanation, and estimatedGrams")
    func basicEstimation() {
        let response = AmountNutritionResponse(caloriesPer100g: 155, estimatedGrams: 120, foodName: "Eggs")
        let result = CalorieEstimator.makeEstimation(from: response)
        #expect(result.calories == 186) // 155 * 120 / 100
        #expect(result.estimatedGrams == 120)
        #expect(result.explanation == "Eggs has ~155 kcal per 100g.")
    }

    @Test("Returns zero calories when estimatedGrams is zero")
    func zeroEstimatedGrams() {
        let response = AmountNutritionResponse(caloriesPer100g: 200, estimatedGrams: 0, foodName: "Water")
        let result = CalorieEstimator.makeEstimation(from: response)
        #expect(result.calories == 0)
        #expect(result.estimatedGrams == 0)
    }

    @Test("Returns zero calories when caloriesPer100g is zero")
    func zeroCaloriesPer100g() {
        let response = AmountNutritionResponse(caloriesPer100g: 0, estimatedGrams: 250, foodName: "Water")
        let result = CalorieEstimator.makeEstimation(from: response)
        #expect(result.calories == 0)
        #expect(result.estimatedGrams == 250)
    }

    @Test("Integer division truncates fractional calories")
    func integerTruncation() {
        // 155 * 33 / 100 = 5115 / 100 = 51
        let response = AmountNutritionResponse(caloriesPer100g: 155, estimatedGrams: 33, foodName: "Egg")
        let result = CalorieEstimator.makeEstimation(from: response)
        #expect(result.calories == 51)
    }

    @Test("Handles very large values")
    func largeValues() {
        let response = AmountNutritionResponse(caloriesPer100g: 9000, estimatedGrams: 500, foodName: "Butter")
        let result = CalorieEstimator.makeEstimation(from: response)
        #expect(result.calories == 45000)
        #expect(result.estimatedGrams == 500)
    }
}

// MARK: - CalorieEstimation

@Suite("CalorieEstimation")
struct CalorieEstimationTests {

    @Test("Stores calories and explanation")
    func initWithValues() {
        let estimation = CalorieEstimation(calories: 300, explanation: "Some explanation")
        #expect(estimation.calories == 300)
        #expect(estimation.explanation == "Some explanation")
        #expect(estimation.estimatedGrams == nil)
    }

    @Test("Stores estimatedGrams when provided")
    func initWithEstimatedGrams() {
        let estimation = CalorieEstimation(calories: 300, explanation: "test", estimatedGrams: 150)
        #expect(estimation.estimatedGrams == 150)
    }

    @Test("Explanation can be nil")
    func nilExplanation() {
        let estimation = CalorieEstimation(calories: 0, explanation: nil)
        #expect(estimation.calories == 0)
        #expect(estimation.explanation == nil)
    }
}
