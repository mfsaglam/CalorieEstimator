import Testing
@testable import CalorieEstimator

@Suite("Deterministic Recipe Decomposition")
struct RecipeDecomposerTests {
    @Test("Largest-remainder allocation exactly preserves total mass")
    func exactMass() {
        for total in 1...500 {
            let values = RecipeDecomposer.allocate(total: total, ratios: [0.333, 0.333, 0.334])
            #expect(values.reduce(0, +) == total)
        }
    }

    @Test("Known carbonara contains only trusted ingredients")
    func carbonaraRegression() async throws {
        let database = LocalRecipeDatabase()
        let recipe = try #require(await database.recipe(id: "it.spaghetti_carbonara.roman"))
        let estimate = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 150,
            displayName: "spaghetti carbonara",
            nutritionTable: LocalNutritionTable()
        ))
        let names = try #require(estimate.ingredients).map { FoodNameNormalizer.normalize($0.name) }
        #expect(!names.contains("mushroom"))
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 150)
        #expect(estimate.provenance == .localRecipe)
        #expect(estimate.confidence == .high)
    }

    @Test("Explicit additions are allowed but never silently introduced")
    func explicitAddition() async throws {
        let database = LocalRecipeDatabase()
        let recipe = try #require(await database.recipe(id: "it.spaghetti_carbonara.roman"))
        let modification = MealModification(
            kind: .add,
            ingredientName: "mushroom",
            ingredientNameEnglish: "mushroom",
            estimatedGrams: 30
        )
        let estimate = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: "mushroom carbonara",
            nutritionTable: LocalNutritionTable(),
            modifications: [modification]
        ))
        #expect(estimate.ingredients?.contains { $0.name == "mushroom" } == true)
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 200)
        #expect(estimate.confidence == .medium)
    }

    @Test("Qualitative increase raises the target and preserves total mass")
    func qualitativeIncrease() async throws {
        let recipe = try #require(await LocalRecipeDatabase().recipe(id: "tr.tavuklu_pilav.default"))
        let baseline = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: "tavuklu pilav",
            nutritionTable: LocalNutritionTable()
        ))
        let estimate = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: "extra chicken tavuklu pilav",
            nutritionTable: LocalNutritionTable(),
            modifications: [modification(.increase, "chicken")]
        ))

        #expect(grams(of: "chicken", in: estimate) > grams(of: "chicken", in: baseline))
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 200)
        #expect(estimate.recipeID == recipe.id)
        #expect(estimate.provenance == .localRecipe)
    }

    @Test("Qualitative decrease lowers the target and preserves total mass")
    func qualitativeDecrease() async throws {
        let recipe = try #require(await LocalRecipeDatabase().recipe(id: "tr.tavuklu_pilav.default"))
        let baseline = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: "tavuklu pilav",
            nutritionTable: LocalNutritionTable()
        ))
        let estimate = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: "less chicken tavuklu pilav",
            nutritionTable: LocalNutritionTable(),
            modifications: [modification(.decrease, "chicken")]
        ))

        #expect(grams(of: "chicken", in: estimate) < grams(of: "chicken", in: baseline))
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 200)
    }

    @Test("Explicit new-ingredient mass is reserved before scaling the base")
    func explicitNewIngredientMass() async throws {
        let recipe = try #require(await LocalRecipeDatabase().recipe(id: "tr.tavuklu_pilav.default"))
        let estimate = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: "chicken rice with 30g mushroom",
            nutritionTable: LocalNutritionTable(),
            modifications: [modification(.add, "mushroom", grams: 30)]
        ))

        #expect(grams(of: "mushroom", in: estimate) == 30)
        #expect(estimate.ingredients?.filter { FoodNameNormalizer.normalize($0.name) != "mushroom" }
            .reduce(0) { $0 + $1.grams } == 170)
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 200)
    }

    @Test("Explicit existing-ingredient mass is added after scaling the base")
    func explicitExistingIngredientMass() async throws {
        let recipe = try #require(await LocalRecipeDatabase().recipe(id: "tr.tavuklu_pilav.default"))
        let scaledBase = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 170,
            displayName: "tavuklu pilav",
            nutritionTable: LocalNutritionTable()
        ))
        let estimate = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: "chicken rice with 30g extra chicken",
            nutritionTable: LocalNutritionTable(),
            modifications: [modification(.increase, "chicken", grams: 30)]
        ))

        #expect(grams(of: "chicken", in: estimate) == grams(of: "chicken", in: scaledBase) + 30)
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 200)
    }

    @Test("Remove, add, and increase survive together with exact mass")
    func combinedModifiers() async throws {
        let recipe = try #require(await LocalRecipeDatabase().recipe(id: "tr.tavuklu_pilav.default"))
        let withoutIncrease = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: "modified chicken rice",
            nutritionTable: LocalNutritionTable(),
            modifications: [
                modification(.remove, "butter"),
                modification(.add, "mushroom")
            ]
        ))
        let estimate = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: "modified chicken rice",
            nutritionTable: LocalNutritionTable(),
            modifications: [
                modification(.remove, "butter"),
                modification(.add, "mushroom"),
                modification(.increase, "chicken")
            ]
        ))

        #expect(estimate.ingredients?.contains { FoodNameNormalizer.normalize($0.name) == "butter" } == false)
        #expect(estimate.ingredients?.contains { FoodNameNormalizer.normalize($0.name) == "mushroom" } == true)
        #expect(grams(of: "chicken", in: estimate) > grams(of: "chicken", in: withoutIncrease))
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 200)
    }

    private func modification(
        _ kind: MealModificationKind,
        _ ingredient: String,
        grams: Int? = nil
    ) -> MealModification {
        MealModification(
            kind: kind,
            ingredientName: ingredient,
            ingredientNameEnglish: ingredient,
            estimatedGrams: grams
        )
    }

    private func grams(of ingredient: String, in estimate: MealEstimate) -> Int {
        estimate.ingredients?.first {
            FoodNameNormalizer.normalize($0.name) == FoodNameNormalizer.normalize(ingredient)
        }?.grams ?? 0
    }
}
