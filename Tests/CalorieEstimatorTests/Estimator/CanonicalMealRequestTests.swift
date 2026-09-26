import Testing
@testable import CalorieEstimator

@Suite("Multilingual Canonical Meal Request")
struct CanonicalMealRequestTests {
    private let database = LocalRecipeDatabase()

    @Test("Trusted ingredient selections become stable IngredientID operations")
    func trustedSelections() async throws {
        let cases: [(
            recipeID: RecipeID,
            ingredientID: IngredientID,
            kind: MealModificationKind,
            expected: CanonicalMealModification
        )] = [
            (
                "it.spaghetti_carbonara.roman",
                "parmesan",
                .remove,
                .remove(ingredientID: "parmesan")
            ),
            (
                "es.paella.seafood",
                "shrimp",
                .increase,
                .increase(ingredientID: "shrimp", grams: nil)
            ),
            (
                "ru.borscht.default",
                "sour_cream",
                .remove,
                .remove(ingredientID: "sour_cream")
            ),
            (
                "kr.bibimbap.default",
                "egg",
                .remove,
                .remove(ingredientID: "egg")
            )
        ]

        for testCase in cases {
            let recipe = try #require(await database.recipe(id: testCase.recipeID))
            let index = try #require(recipe.ingredients.firstIndex { $0.id == testCase.ingredientID })
            let selection = TrustedIngredientSelection(
                kind: testCase.kind,
                candidateNumber: index + 1,
                grams: nil
            )
            let modification = try #require(
                FoundationModelMealParser.canonicalModification(from: selection, in: recipe)
            )
            let request = CanonicalMealRequest(
                recipeID: recipe.id,
                quantity: .grams(200),
                modifications: [modification]
            )

            #expect(request.recipeID == testCase.recipeID)
            #expect(request.modifications == [testCase.expected])
            #expect(modification.ingredientID == testCase.ingredientID)
        }
    }

    @Test("A trusted localized new ingredient becomes a canonical add")
    func trustedAddition() async throws {
        let ramen = try #require(await database.recipe(id: "jp.ramen.shoyu"))
        let additions = try await FoundationModelMealParser.resolveNewIngredientAdditions(
            [
                GeneratedNewIngredientAddition(
                    evidenceText: "コーン入り",
                    ingredientName: "コーン",
                    ingredientNameEnglish: "corn",
                    hasExplicitGrams: false,
                    explicitGrams: 0
                )
            ],
            trustedRecipe: ramen,
            recipeDatabase: database,
            languageCode: "ja",
            localeIdentifier: "ja-JP",
            sourceDescriptions: ["ラーメン200グラム、コーン入り"]
        )
        let modification = try #require(additions.first)
        let request = CanonicalMealRequest(
            recipeID: ramen.id,
            quantity: .grams(200),
            modifications: [modification]
        )

        #expect(request.recipeID == "jp.ramen.shoyu")
        #expect(additions.count == 1)
        #expect(request.modifications == [.add(ingredientID: "corn", grams: nil)])
        #expect(modification.ingredientID == "corn")
    }

    @Test("Deterministic modification identity uses IngredientID instead of names")
    func decomposerUsesIngredientID() async throws {
        let bibimbap = try #require(await database.recipe(id: "kr.bibimbap.default"))
        let misleadingNames = MealModification(
            kind: .remove,
            ingredientID: "egg",
            ingredientName: "Rice",
            ingredientNameEnglish: "rice",
            estimatedGrams: nil
        )
        let estimate = try #require(RecipeDecomposer.estimate(
            recipe: bibimbap,
            grams: 200,
            displayName: "비빔밥",
            nutritionTable: LocalNutritionTable(),
            modifications: [misleadingNames]
        ))

        let ids = Set(try #require(estimate.ingredients).compactMap(\.ingredientID))
        #expect(!ids.contains("egg"))
        #expect(ids.contains("rice"))
    }
}
