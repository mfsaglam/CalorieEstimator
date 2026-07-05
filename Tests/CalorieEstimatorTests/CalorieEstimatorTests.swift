import Testing
import Foundation
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

// MARK: - MealEstimate (phrase-based) validation

/// A stub table that always resolves to a fixed value, to test the override path.
private struct StubNutritionTable: NutritionTable {
    let value: Int?
    func caloriesPer100g(for foodName: String) -> Int? { value }
}

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

// MARK: - Local Nutrition Table

@Suite("Local Nutrition Table")
struct LocalNutritionTableTests {

    private let table = LocalNutritionTable()

    @Test("Exact match resolves")
    func exactMatch() {
        #expect(table.caloriesPer100g(for: "banana") == 89)
    }

    @Test("Plural resolves to the singular key")
    func pluralMatch() {
        #expect(table.caloriesPer100g(for: "eggs") == 155)
        #expect(table.caloriesPer100g(for: "almonds") == 579)
    }

    @Test("Case and punctuation are ignored")
    func normalisation() {
        #expect(table.caloriesPer100g(for: "  White Rice! ") == 130)
    }

    @Test("Modifier words resolve via the longest contained key")
    func substringMatch() {
        // "grilled chicken breast" → prefers "chicken breast" (165) over "chicken" (190).
        #expect(table.caloriesPer100g(for: "grilled chicken breast") == 165)
    }

    @Test("A whole-word match does not fire on a partial word")
    func noPartialWordMatch() {
        // "eggplant" must not match the "egg" key.
        #expect(table.caloriesPer100g(for: "eggplant") == 25)
    }

    @Test("Unknown foods miss")
    func unknownMisses() {
        #expect(table.caloriesPer100g(for: "grandma's mystery stew") == nil)
    }
}

// MARK: - Phrase-Based Estimation (on-device model)
//
// These tests exercise the real on-device model, so their exact numbers are
// non-deterministic. They assert on invariants (non-empty food name, no digits
// in the name, sane gram range, positive calories) rather than exact values.
// They require a device with Apple Intelligence available.

@Suite("Phrase-Based Estimation")
struct PhraseBasedEstimationTests {

    private let estimator = CalorieEstimator()

    /// Shared invariants every phrase estimate must satisfy.
    private func assertInvariants(_ estimate: MealEstimate, gramRange: ClosedRange<Int>) {
        let trimmedName = estimate.foodName.trimmingCharacters(in: .whitespaces)
        let hasDigits = estimate.foodName.contains(where: \.isNumber)
        #expect(!trimmedName.isEmpty)
        #expect(!hasDigits, "Food name should not contain digits: \(estimate.foodName)")
        #expect(gramRange.contains(estimate.grams), "grams \(estimate.grams) outside expected range \(gramRange)")
        #expect(estimate.calories > 0)
    }

    @Test("Weight phrase: 200 grams of chicken")
    func weightPhrase() async throws {
        let estimate = try await estimator.estimate(phrase: "200 grams of grilled chicken")
        assertInvariants(estimate, gramRange: 150...260)
        #expect(estimate.foodName.localizedCaseInsensitiveContains("chicken"))
    }

    @Test("Word-number weight phrase: eight ounces of salmon")
    func wordNumberWeightPhrase() async throws {
        // Eight ounces ≈ 227 g.
        let estimate = try await estimator.estimate(phrase: "eight ounces of salmon")
        assertInvariants(estimate, gramRange: 150...320)
        #expect(estimate.foodName.localizedCaseInsensitiveContains("salmon"))
    }

    @Test("Volume phrase: 250 ml orange juice")
    func volumePhrase() async throws {
        // 250 ml of juice ≈ 250 g.
        let estimate = try await estimator.estimate(phrase: "250 ml orange juice")
        assertInvariants(estimate, gramRange: 150...400)
    }

    @Test("Count phrase: two eggs")
    func countPhrase() async throws {
        let estimate = try await estimator.estimate(phrase: "two eggs")
        assertInvariants(estimate, gramRange: 60...200)
        #expect(estimate.foodName.localizedCaseInsensitiveContains("egg"))
    }

    @Test("Bare food with no amount: banana")
    func bareFood() async throws {
        // No amount stated → a single typical serving.
        let estimate = try await estimator.estimate(phrase: "banana")
        assertInvariants(estimate, gramRange: 50...400)
        #expect(estimate.foodName.localizedCaseInsensitiveContains("banana"))
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
