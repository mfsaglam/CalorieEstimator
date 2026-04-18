import Foundation
import Testing
@testable import CalorieEstimator

// MARK: - Parsing & Calorie Calculation

@Suite("Response Parsing")
struct ResponseParsingTests {

    @Test("Parses clean number with food name on second line")
    func cleanResponse() throws {
        let result = try CalorieEstimator.parseResponse("200\nChicken breast", meal: "chicken", grams: 100)
        #expect(result.calories == 200)
        #expect(result.explanation == "Chicken breast has ~200 kcal per 100g.")
    }

    @Test("Extracts digits when first line contains surrounding text")
    func digitsWithSurroundingText() throws {
        let result = try CalorieEstimator.parseResponse("About 250 kcal\nRice", meal: "rice", grams: 100)
        #expect(result.calories == 250)
    }

    @Test("Concatenates scattered digits on the first line")
    func scatteredDigits() throws {
        // "1 cup: 50" → digits become "150"
        let result = try CalorieEstimator.parseResponse("1 cup: 50\nOats", meal: "oats", grams: 100)
        #expect(result.calories == 150)
    }

    @Test("Falls back to meal name when response has a single line")
    func singleLineResponse() throws {
        let result = try CalorieEstimator.parseResponse("300", meal: "banana", grams: 100)
        #expect(result.calories == 300)
        #expect(result.explanation == "banana has ~300 kcal per 100g.")
    }

    @Test("Throws parsingFailed for empty response")
    func emptyResponse() throws {
        #expect(throws: CalorieEstimatorError.self) {
            try CalorieEstimator.parseResponse("", meal: "anything", grams: 100)
        }
    }

    @Test("Throws parsingFailed when first line has no digits")
    func noDigitsOnFirstLine() throws {
        #expect(throws: CalorieEstimatorError.self) {
            try CalorieEstimator.parseResponse("no numbers here\nChicken", meal: "chicken", grams: 100)
        }
    }

    @Test("Throws parsingFailed when first line is whitespace before newline")
    func whitespaceOnlyFirstLine() throws {
        // split keeps "   " as first element when followed by content
        #expect(throws: CalorieEstimatorError.self) {
            try CalorieEstimator.parseResponse("   \n200", meal: "egg", grams: 100)
        }
    }

    @Test("Handles leading newline (empty first subsequence is dropped by split)")
    func leadingNewline() throws {
        // split omits empty subsequences, so "\n200" → ["200"]
        let result = try CalorieEstimator.parseResponse("\n200", meal: "egg", grams: 50)
        #expect(result.calories == 100)
        #expect(result.explanation == "egg has ~200 kcal per 100g.")
    }

    @Test("Trims whitespace from food name on second line")
    func foodNameWhitespaceTrimming() throws {
        let result = try CalorieEstimator.parseResponse("100\n   Broccoli   ", meal: "broccoli", grams: 100)
        #expect(result.explanation == "Broccoli has ~100 kcal per 100g.")
    }

    @Test("Handles zero calories (e.g. water)")
    func zeroCalories() throws {
        let result = try CalorieEstimator.parseResponse("0\nWater", meal: "water", grams: 250)
        #expect(result.calories == 0)
        #expect(result.explanation == "Water has ~0 kcal per 100g.")
    }

    @Test("Handles very large calorie value")
    func largeCalorieValue() throws {
        let result = try CalorieEstimator.parseResponse("9000\nPure fat", meal: "fat", grams: 100)
        #expect(result.calories == 9000)
    }
}

// MARK: - Calorie Arithmetic

@Suite("Calorie Arithmetic")
struct CalorieArithmeticTests {

    @Test("Scales correctly for 100g (identity)")
    func hundredGrams() throws {
        let result = try CalorieEstimator.parseResponse("250\nPasta", meal: "pasta", grams: 100)
        #expect(result.calories == 250)
    }

    @Test("Scales correctly for amounts above 100g")
    func aboveHundredGrams() throws {
        let result = try CalorieEstimator.parseResponse("200\nRice", meal: "rice", grams: 350)
        #expect(result.calories == 700)
    }

    @Test("Scales correctly for amounts below 100g")
    func belowHundredGrams() throws {
        let result = try CalorieEstimator.parseResponse("200\nRice", meal: "rice", grams: 50)
        #expect(result.calories == 100)
    }

    @Test("Returns zero calories for zero grams")
    func zeroGrams() throws {
        let result = try CalorieEstimator.parseResponse("500\nChocolate", meal: "chocolate", grams: 0)
        #expect(result.calories == 0)
    }

    @Test("Integer division truncates fractional calories")
    func integerTruncation() throws {
        // 155 * 33 / 100 = 5115 / 100 = 51 (truncated from 51.15)
        let result = try CalorieEstimator.parseResponse("155\nEgg", meal: "egg", grams: 33)
        #expect(result.calories == 51)
    }

    @Test("Handles 1 gram correctly")
    func oneGram() throws {
        // 200 * 1 / 100 = 2
        let result = try CalorieEstimator.parseResponse("200\nBread", meal: "bread", grams: 1)
        #expect(result.calories == 2)
    }

    @Test("Handles very large gram value")
    func veryLargeGrams() throws {
        let result = try CalorieEstimator.parseResponse("100\nApple", meal: "apple", grams: 10000)
        #expect(result.calories == 10000)
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
    }

    @Test("Explanation can be nil")
    func nilExplanation() {
        let estimation = CalorieEstimation(calories: 0, explanation: nil)
        #expect(estimation.calories == 0)
        #expect(estimation.explanation == nil)
    }
}

// MARK: - CalorieEstimatorError

@Suite("CalorieEstimatorError")
struct CalorieEstimatorErrorTests {

    @Test("parsingFailed includes original response in description")
    func parsingFailedDescription() {
        let error = CalorieEstimatorError.parsingFailed(response: "bad response")
        #expect(error.errorDescription?.contains("bad response") == true)
    }

    @Test("parsingFailed conforms to LocalizedError")
    func conformsToLocalizedError() {
        let error: LocalizedError = CalorieEstimatorError.parsingFailed(response: "test")
        #expect(error.errorDescription != nil)
    }
}
