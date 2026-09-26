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
            "es.paella.seafood", "ru.borscht.default", "fr.ratatouille.default",
            "de.schnitzel.pork"
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

    @Test("Modified phrases find only bounded complete recipe aliases")
    func boundedRecipeCandidates() async throws {
        let prefix = try await database.recipeCandidate(
            containedIn: RecipeQuery(name: "200 gram mantarlı tavuklu pilav")
        )
        let suffix = try await database.recipeCandidate(
            containedIn: RecipeQuery(name: "200 gram tavuklu pilav mantarlı")
        )
        let carbonara = try await database.recipeCandidate(
            containedIn: RecipeQuery(name: "200g mushroom carbonara")
        )
        let partialWord = try await database.recipeCandidate(
            containedIn: RecipeQuery(name: "200g scarbonara sauce")
        )
        let ingredientOnly = try await database.recipeCandidate(
            containedIn: RecipeQuery(name: "200g mushroom rice")
        )

        #expect(prefix?.id == "tr.tavuklu_pilav.default")
        #expect(suffix?.id == prefix?.id)
        #expect(carbonara?.id == "it.spaghetti_carbonara.roman")
        #expect(partialWord == nil)
        #expect(ingredientOnly == nil)
    }

    @Test("Five-recipe localized aliases resolve to stable recipe identities")
    func proofOfConceptRecipeAliases() async throws {
        let cases: [(String, RecipeID)] = [
            ("200 grammi di spaghetti alla carbonara senza parmigiano", "it.spaghetti_carbonara.roman"),
            ("200 gramos de paella con extra de gambas", "es.paella.seafood"),
            ("200 граммов борща без сметаны", "ru.borscht.default"),
            ("비빔밥 200그램, 계란 빼고", "kr.bibimbap.default"),
            ("ラーメン200グラム、コーン入り", "jp.ramen.shoyu")
        ]

        for (phrase, expectedID) in cases {
            let recipe = try await database.recipeCandidate(containedIn: RecipeQuery(name: phrase))
            #expect(recipe?.id == expectedID, Comment(rawValue: phrase))
        }
    }

    @Test("Localized ingredient aliases resolve exactly to stable identities")
    func proofOfConceptIngredientAliases() async throws {
        let cases: [(name: String, language: String, expectedID: IngredientID)] = [
            ("parmigiano", "it", "parmesan"),
            ("gambas", "es", "shrimp"),
            ("сметана", "ru", "sour_cream"),
            ("сметаны", "ru", "sour_cream"),
            ("계란", "ko", "egg"),
            ("コーン", "ja", "corn")
        ]

        for testCase in cases {
            let ingredient = try await database.ingredient(
                matching: IngredientQuery(name: testCase.name, languageCode: testCase.language)
            )
            #expect(ingredient?.id == testCase.expectedID, Comment(rawValue: testCase.name))
        }
        let partial = try await database.ingredient(
            matching: IngredientQuery(name: "コーン入り", languageCode: "ja")
        )
        #expect(partial == nil)
    }

    @Test("Compact aliases require non-letter boundaries")
    func compactAliasBoundaries() async throws {
        let quantityAdjacent = try await database.recipeCandidate(
            containedIn: RecipeQuery(name: "ラーメン200グラム")
        )
        let embeddedInLongerWord = try await database.recipeCandidate(
            containedIn: RecipeQuery(name: "スーパーラーメン屋")
        )
        let latinPartial = try await database.recipeCandidate(
            containedIn: RecipeQuery(name: "scarbonara")
        )

        #expect(quantityAdjacent?.id == "jp.ramen.shoyu")
        #expect(embeddedInLongerWord == nil)
        #expect(latinPartial == nil)
    }
}
