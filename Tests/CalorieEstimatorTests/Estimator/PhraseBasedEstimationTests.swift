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
    .enabled(if: ProcessInfo.processInfo.environment["CALORIE_ESTIMATOR_RUN_MODEL_TESTS"] == "1"),
    .serialized
)
struct PhraseBasedEstimationTests {

    private let estimator = CalorieEstimator()

    @Test("Italian Carbonara canonicalizes parmesan removal")
    func italianCarbonaraCanonicalization() async throws {
        try await assertCanonicalSemantics(
            phrase: "200 grammi di spaghetti alla carbonara senza parmigiano",
            recipeID: "it.spaghetti_carbonara.roman",
            ingredientID: "parmesan",
            acceptedKinds: [.remove]
        )
    }

    @Test("Spanish Paella canonicalizes extra shrimp")
    func spanishPaellaCanonicalization() async throws {
        try await assertCanonicalSemantics(
            phrase: "200 gramos de paella con extra de gambas",
            recipeID: "es.paella.seafood",
            ingredientID: "shrimp",
            acceptedKinds: [.add, .increase]
        )
    }

    @Test("Russian Borscht canonicalizes sour cream removal")
    func russianBorschtCanonicalization() async throws {
        try await assertCanonicalSemantics(
            phrase: "200 граммов борща без сметаны",
            recipeID: "ru.borscht.default",
            ingredientID: "sour_cream",
            acceptedKinds: [.remove]
        )
    }

    @Test("Korean Bibimbap canonicalizes egg removal")
    func koreanBibimbapCanonicalization() async throws {
        try await assertCanonicalSemantics(
            phrase: "비빔밥 200그램, 계란 빼고",
            recipeID: "kr.bibimbap.default",
            ingredientID: "egg",
            acceptedKinds: [.remove]
        )
    }

    @Test("Japanese Ramen canonicalizes corn addition")
    func japaneseRamenCanonicalization() async throws {
        try await assertCanonicalSemantics(
            phrase: "ラーメン200グラム、コーン入り",
            recipeID: "jp.ramen.shoyu",
            ingredientID: "corn",
            acceptedKinds: [.add]
        )
    }

    private func assertCanonicalSemantics(
        phrase: String,
        recipeID: RecipeID,
        ingredientID: IngredientID,
        acceptedKinds: [MealModificationKind]
    ) async throws {
        let request = try await FoundationModelMealParser().parse(
            phrase,
            recipeDatabase: LocalRecipeDatabase()
        )
        let canonical = try #require(request.canonicalRequest)
        #expect(canonical.recipeID == recipeID, Comment(rawValue: phrase))
        let matched = request.modifications.contains { modification in
            modification.ingredientID == ingredientID
                && acceptedKinds.contains(modification.kind)
        }
        #expect(matched, Comment(rawValue: phrase))
    }

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

    @Test("Known-recipe increase and decrease modifiers survive live semantic parsing")
    func qualitativeModifierRegressions() async throws {
        let baseline = try await estimator.estimate(phrase: "tavuklu pilav 200g")
        report(baseline, phrase: "tavuklu pilav 200g", requestedGrams: 200)
        let baselineChicken = try #require(ingredient(named: "chicken", in: baseline)?.grams)
        #expect(baselineChicken == 74)

        let increaseCases: [(phrase: String, recipeID: RecipeID)] = [
            ("tavuklu pilav ekstra tavuklu 200g", "tr.tavuklu_pilav.default"),
            ("tavuklu pilav bol tavuklu 200g", "tr.tavuklu_pilav.default"),
            ("200g chicken rice with extra chicken", "global.chicken_rice.default")
        ]
        for (phrase, recipeID) in increaseCases {
            let estimate = try await estimator.estimate(phrase: phrase)
            report(estimate, phrase: phrase, requestedGrams: 200)
            let chicken = try #require(ingredient(named: "chicken", in: estimate)?.grams)
            #expect(chicken > baselineChicken, Comment(rawValue: phrase))
            assertTrustedRecipe(estimate, recipeID: recipeID, requestedGrams: 200)
        }

        let decreased = try await estimator.estimate(phrase: "200g chicken rice with less chicken")
        report(decreased, phrase: "200g chicken rice with less chicken", requestedGrams: 200)
        let decreasedChicken = try #require(ingredient(named: "chicken", in: decreased)?.grams)
        #expect(decreasedChicken < baselineChicken)
        assertTrustedRecipe(decreased, recipeID: "global.chicken_rice.default", requestedGrams: 200)

        let carbonara = try await estimator.estimate(
            phrase: "spaghetti carbonara with extra pancetta 150g"
        )
        report(
            carbonara,
            phrase: "spaghetti carbonara with extra pancetta 150g",
            requestedGrams: 150
        )
        let carbonaraRecipe = try #require(
            await LocalRecipeDatabase().recipe(id: "it.spaghetti_carbonara.roman")
        )
        let carbonaraBaseline = try #require(RecipeDecomposer.estimate(
            recipe: carbonaraRecipe,
            grams: 150,
            displayName: "spaghetti carbonara",
            nutritionTable: LocalNutritionTable()
        ))
        let pancetta = try #require(ingredient(named: "pancetta or bacon", in: carbonara)?.grams)
        let baselinePancetta = try #require(
            ingredient(named: "pancetta or bacon", in: carbonaraBaseline)?.grams
        )
        #expect(pancetta > baselinePancetta)
        assertTrustedRecipe(carbonara, recipeID: "it.spaghetti_carbonara.roman", requestedGrams: 150)
    }

    @Test("Explicit modifier grams and combined modifiers survive live semantic parsing")
    func quantitativeAndCombinedModifierRegressions() async throws {
        let explicit = try await estimator.estimate(
            phrase: "tavuklu pilav 30g ekstra mantar 200g"
        )
        report(
            explicit,
            phrase: "tavuklu pilav 30g ekstra mantar 200g",
            requestedGrams: 200
        )
        let mushroom = try #require(explicit.ingredients?.first {
            let name = FoodNameNormalizer.normalize($0.name)
            return name == "mantar" || name == "mushroom"
        })
        #expect(mushroom.grams == 30)
        #expect(explicit.ingredients?.filter { $0 != mushroom }.reduce(0) { $0 + $1.grams } == 170)
        assertTrustedRecipe(explicit, recipeID: "tr.tavuklu_pilav.default", requestedGrams: 200)

        let combined = try await estimator.estimate(
            phrase: "tavuklu pilav tereyağsız mantarlı 200g"
        )
        report(
            combined,
            phrase: "tavuklu pilav tereyağsız mantarlı 200g",
            requestedGrams: 200
        )
        let names = Set(try #require(combined.ingredients).map {
            FoodNameNormalizer.normalize($0.name)
        })
        #expect(!names.contains("butter"))
        #expect(names.contains("mantar") || names.contains("mushroom"))
        assertTrustedRecipe(combined, recipeID: "tr.tavuklu_pilav.default", requestedGrams: 200)
    }

    @Test("Unknown global food terminates through a bounded fallback")
    func unknownFoodTerminates() async {
        let phrase = "beef stroganoff 200g"
        let clock = ContinuousClock()
        let started = clock.now

        do {
            let estimate = try await estimator.estimate(phrase: phrase)
            let elapsed = started.duration(to: clock.now)
            report(estimate, phrase: phrase, requestedGrams: 200)
            print("elapsed: \(elapsed)")
            #expect(estimate.grams == 200)
            #expect(estimate.provenance == .modelAssistedRecipe || estimate.provenance == .modelNutrition)
            #expect(elapsed < .seconds(65))
        } catch let error as CalorieEstimatorError {
            let elapsed = started.duration(to: clock.now)
            print("""
            LIVE RESULT | \(phrase)
            requested grams: 200
            sum of ingredient grams: unavailable (controlled error)
            provenance: unavailable (controlled error)
            confidence: unavailable (controlled error)
            recipe ID: none
            error: \(error.localizedDescription)
            elapsed: \(elapsed)
            """)
            #expect(elapsed < .seconds(65))
        } catch {
            Issue.record("Unexpected unknown-food error: \(error)")
        }
    }

    private func assertTrustedRecipe(
        _ estimate: MealEstimate,
        recipeID: RecipeID,
        requestedGrams: Int
    ) {
        #expect(estimate.grams == requestedGrams)
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == requestedGrams)
        #expect(estimate.recipeID == recipeID)
        #expect(estimate.provenance == .localRecipe)
    }

    private func ingredient(named name: String, in estimate: MealEstimate) -> IngredientEstimate? {
        let normalized = FoodNameNormalizer.normalize(name)
        return estimate.ingredients?.first { FoodNameNormalizer.normalize($0.name) == normalized }
    }

    private func report(_ estimate: MealEstimate, phrase: String, requestedGrams: Int) {
        let componentMass = estimate.ingredients?.reduce(0) { $0 + $1.grams } ?? estimate.grams
        let ingredientLines = estimate.ingredients?.map {
            "\($0.name): \($0.grams)g / \($0.calories) kcal"
        }.joined(separator: "\n") ?? "whole-food estimate (no ingredient decomposition)"
        print("""
        LIVE RESULT | \(phrase)
        requested grams: \(requestedGrams)
        sum of ingredient grams: \(componentMass)
        provenance: \(estimate.provenance)
        confidence: \(String(describing: estimate.confidence))
        recipe ID: \(estimate.recipeID?.rawValue ?? "none")
        calories: \(estimate.calories)
        \(ingredientLines)
        """)
    }
}
