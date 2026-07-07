import Testing
import Foundation
@testable import CalorieEstimator

// MARK: - Weight-based estimation (text-field path)
//
// These exercise the public `estimate(meal:weight:)` end to end. They rely on a
// nutrition-table HIT, which short-circuits before any LanguageModelSession is created —
// so they run deterministically with no device / Apple Intelligence. A `.database`
// source and the absence of a `modelUnavailable` throw together prove the model was
// never touched.

@Suite("Weight-Based Estimation")
struct WeightBasedEstimationTests {

    @Test("Table hit short-circuits without creating a model session")
    func tableHitShortCircuits() async throws {
        let estimator = CalorieEstimator(nutritionTable: StubNutritionTable(value: 200))
        let result = try await estimator.estimate(meal: "anything", weight: .init(value: 150, unit: .grams))
        #expect(result.calories == 300)   // 200 * 150 / 100
        #expect(result.grams == 150)
        #expect(result.source == .database) // never reached the model
        #expect(result.confidence == .high)
        #expect(result.ingredients == nil)
        #expect(result.foodName == "anything")
    }

    @Test("Ounces are converted to grams in code")
    func ouncesConvertToGrams() async throws {
        // 8 oz = 226.796… g → 227 g. Table 100/100g → 227 kcal.
        let estimator = CalorieEstimator(nutritionTable: StubNutritionTable(value: 100))
        let result = try await estimator.estimate(meal: "x", weight: .init(value: 8, unit: .ounces))
        #expect(result.grams == 227)
        #expect(result.calories == 227)
    }

    @Test("Pounds are converted to grams in code")
    func poundsConvertToGrams() async throws {
        // 1 lb = 453.59… g → 454 g.
        let estimator = CalorieEstimator(nutritionTable: StubNutritionTable(value: 100))
        let result = try await estimator.estimate(meal: "x", weight: .init(value: 1, unit: .pounds))
        #expect(result.grams == 454)
        #expect(result.calories == 454)
    }

    @Test("Kilograms are converted to grams in code")
    func kilogramsConvertToGrams() async throws {
        let estimator = CalorieEstimator(nutritionTable: StubNutritionTable(value: 100))
        let result = try await estimator.estimate(meal: "x", weight: .init(value: 0.2, unit: .kilograms))
        #expect(result.grams == 200)
        #expect(result.calories == 200)
    }

    @Test("Gram convenience overload matches the Measurement version")
    func gramsConvenienceOverload() async throws {
        let estimator = CalorieEstimator(nutritionTable: StubNutritionTable(value: 130))
        let result = try await estimator.estimate(meal: "white rice", grams: 250)
        #expect(result.grams == 250)
        #expect(result.calories == 325) // 130 * 250 / 100
        #expect(result.source == .database)
    }

    @Test("Non-positive weight throws before any model call")
    func nonPositiveWeightThrows() async {
        let estimator = CalorieEstimator(nutritionTable: StubNutritionTable(value: 100))
        await #expect(throws: CalorieEstimatorError.self) {
            _ = try await estimator.estimate(meal: "x", weight: .init(value: 0, unit: .grams))
        }
    }
}
