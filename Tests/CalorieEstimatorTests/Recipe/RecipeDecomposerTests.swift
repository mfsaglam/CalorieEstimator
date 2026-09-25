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
}
