import Testing
import Foundation
@testable import CalorieEstimator

// MARK: - Phrase-Based Estimation (on-device model)
//
// These tests exercise the real on-device model, so their exact numbers are
// non-deterministic. They assert on invariants (non-empty food name, no digits
// in the name, sane gram range, positive calories) rather than exact values.
// They require a device with Apple Intelligence available.

@Suite(
    "Phrase-Based Estimation",
    .enabled(if: ProcessInfo.processInfo.environment["CALORIE_ESTIMATOR_RUN_MODEL_TESTS"] == "1")
)
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

    @Test("Modified known recipe retains its base and modifier in either Turkish word order", arguments: [
        "200 gram mantarlı tavuklu pilav",
        "200 gram tavuklu pilav mantarlı"
    ])
    func modifiedTurkishRecipe(_ phrase: String) async throws {
        let database = LocalRecipeDatabase()
        let request = try await FoundationModelMealParser().parse(phrase, recipeDatabase: database)
        print("Parsed MealRequest for '\(phrase)': \(request)")

        let estimator = CalorieEstimator(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: database,
            mealParser: StubMealRequestParser(request: request)
        )
        let estimate = try await estimator.estimate(phrase: phrase)

        #expect(FoodNameNormalizer.normalize(request.baseDisplayName) == "tavuklu pilav")
        #expect(request.modifications.contains {
            $0.kind == .add && FoodNameNormalizer.normalize($0.ingredientNameEnglish) == "mushroom"
        })
        #expect(estimate.recipeID == "tr.tavuklu_pilav.default")
        #expect(estimate.provenance == .localRecipe)
        #expect(estimate.ingredients?.contains {
            FoodNameNormalizer.normalize($0.name) == "mantar" || FoodNameNormalizer.normalize($0.name) == "mushroom"
        } == true)
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 200)
        #expect(estimate.calories == 351)

        let rows = try #require(estimate.ingredients).map {
            (FoodNameNormalizer.normalize($0.name), $0.grams, $0.calories)
        }
        #expect(rows.count == 5)
        #expect(rows[0].0 == "rice" && rows[0].1 == 104 && rows[0].2 == 135)
        #expect(rows[1].0 == "chicken" && rows[1].1 == 67 && rows[1].2 == 127)
        #expect(rows[2].0 == "butter" && rows[2].1 == 7 && rows[2].2 == 50)
        #expect(rows[3].0 == "olive oil" && rows[3].1 == 4 && rows[3].2 == 35)
        #expect((rows[4].0 == "mantar" || rows[4].0 == "mushroom") && rows[4].1 == 18 && rows[4].2 == 4)
    }
}
