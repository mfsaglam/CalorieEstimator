import Foundation
import Testing
@testable import CalorieEstimator

@Suite("Meal Evaluation Fixtures")
struct MealEvaluationTests {
    struct Fixture: Decodable {
        let input: String
        let lookupName: String
        let expectedRecipeID: String
        let grams: Int
        let forbiddenIngredients: [String]
    }

    @Test("Known recipes obey fixture identity, ingredient, and mass invariants")
    func fixtures() async throws {
        let url = try #require(Bundle.module.url(forResource: "MealEvaluations", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        let database = LocalRecipeDatabase()
        for fixture in fixtures {
            let recipe = try #require(await database.recipe(matching: RecipeQuery(name: fixture.lookupName)), "Missing recipe for \(fixture.input)")
            #expect(recipe.id.rawValue == fixture.expectedRecipeID)
            let estimate = try #require(RecipeDecomposer.estimate(
                recipe: recipe,
                grams: fixture.grams,
                displayName: fixture.lookupName,
                nutritionTable: LocalNutritionTable()
            ))
            let names = Set(try #require(estimate.ingredients).map { FoodNameNormalizer.normalize($0.name) })
            #expect(fixture.forbiddenIngredients.allSatisfy { !names.contains(FoodNameNormalizer.normalize($0)) })
            #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == fixture.grams)
        }
    }
}
