import Testing
@testable import CalorieEstimator

@Suite("Local Recipe Database")
struct LocalRecipeDatabaseTests {
    private let database = LocalRecipeDatabase()

    @Test("Canonical and multilingual aliases resolve to stable identities")
    func multilingualAliases() async throws {
        let english = try await database.recipe(matching: RecipeQuery(name: "chicken rice", languageCode: "en"))
        let german = try await database.recipe(matching: RecipeQuery(name: "Hähnchen mit Reis", languageCode: "de"))
        let japanese = try await database.recipe(matching: RecipeQuery(name: "チキンライス", languageCode: "ja"))
        #expect(english?.id == "global.chicken_rice.default")
        #expect(german?.id == english?.id)
        #expect(japanese?.id == english?.id)
    }

    @Test("Regional identity remains distinct from a generic dish")
    func regionalIdentity() async throws {
        let turkish = try await database.recipe(matching: RecipeQuery(name: "tavuklu pilav", languageCode: "tr"))
        let generic = try await database.recipe(matching: RecipeQuery(name: "chicken rice", languageCode: "en"))
        #expect(turkish?.id == "tr.tavuklu_pilav.default")
        #expect(turkish?.id != generic?.id)
    }

    @Test("Every bundled recipe has valid ratios and nutrition coverage")
    func validSeedRecipes() async throws {
        let ids: [RecipeID] = [
            "global.chicken_rice.default", "tr.tavuklu_pilav.default",
            "it.spaghetti_carbonara.roman", "jp.ramen.shoyu",
            "cn.fried_rice.egg", "in.chicken_biryani.default",
            "mx.beef_taco.default", "me.hummus.default", "us.cheeseburger.default",
            "kr.bibimbap.default", "th.pad_thai.shrimp", "vn.pho.beef",
            "es.paella.seafood", "fr.ratatouille.default", "de.schnitzel.pork"
        ]
        let nutrition = LocalNutritionTable()
        for id in ids {
            let recipe = try #require(await database.recipe(id: id))
            #expect(abs(recipe.ingredients.reduce(0) { $0 + $1.ratio } - 1) < 0.001)
            #expect(recipe.ingredients.allSatisfy { nutrition.caloriesPer100g(for: $0.nutritionLookupName) != nil })
        }
    }

    @Test("Recipe tool exposes only validated local identity")
    func recipeTool() async throws {
        let tool = RecipeDatabaseTool(database: database)
        let output = try await tool.call(arguments: RecipeLookupArguments(
            name: "phở bò",
            languageCode: "vi",
            localeIdentifier: "vi-VN",
            cuisine: "Vietnamese"
        ))
        #expect(output.contains("vn.pho.beef"))
        let miss = try await tool.call(arguments: RecipeLookupArguments(
            name: "invented dish",
            languageCode: "en",
            localeIdentifier: "",
            cuisine: ""
        ))
        #expect(miss == "No confident local recipe match.")
    }
}
