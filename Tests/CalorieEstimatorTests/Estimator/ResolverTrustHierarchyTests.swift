import Testing
@testable import CalorieEstimator

@Suite("Resolver Trust Hierarchy")
struct ResolverTrustHierarchyTests {
    @Test("A trusted recipe precedes a prepared-dish nutrition-table entry")
    func recipePrecedesNutrition() async throws {
        let estimator = CalorieEstimator(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: LocalRecipeDatabase(),
            mealParser: FailingMealRequestParser()
        )
        let result = try await estimator.estimate(meal: "cheeseburger", grams: 200)
        #expect(result.provenance == .localRecipe)
        #expect(result.source == .decomposed)
        #expect(result.ingredients?.reduce(0) { $0 + $1.grams } == 200)
    }

    @Test("Known recipe serving weight overrides a model portion estimate")
    func trustedServingWeightWins() async throws {
        let resolver = MealResolver(nutritionTable: LocalNutritionTable(), recipeDatabase: LocalRecipeDatabase())
        let result = try await resolver.resolve(request(
            name: "shoyu ramen",
            recipeID: "jp.ramen.shoyu",
            quantity: MealQuantity(amount: 1, unit: .serving, estimatedGrams: 999),
            composite: true,
            proposals: [ModelIngredientProposal(name: "cheese", nameEnglish: "cheese", ratio: 1)],
            modelCalories: 899
        ))
        #expect(result.grams == 550)
        #expect(result.provenance == .localRecipe)
        #expect(result.ingredients?.contains { $0.name == "cheese" } == false)
    }

    @Test("Phrase-provided composite weight is retained")
    func phraseWeightRetained() async throws {
        let request = request(
            name: "tavuklu pilav",
            recipeID: "tr.tavuklu_pilav.default",
            quantity: .grams(200),
            composite: true
        )
        let estimator = CalorieEstimator(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: LocalRecipeDatabase(),
            mealParser: StubMealRequestParser(request: request)
        )
        let result = try await estimator.estimate(phrase: "200 gram tavuklu pilav")
        #expect(result.grams == 200)
        #expect(result.ingredients?.reduce(0) { $0 + $1.grams } == 200)
        #expect(result.recipeID == "tr.tavuklu_pilav.default")
        #expect(result.ingredients?.contains { FoodNameNormalizer.normalize($0.name) == "mushroom" } == false)
    }

    @Test("Local food nutrition overrides the model fallback")
    func localFoodPrecedence() async throws {
        let resolver = MealResolver(nutritionTable: LocalNutritionTable(), recipeDatabase: EmptyRecipeDatabase())
        let result = try await resolver.resolve(request(name: "banana", quantity: .grams(100), modelCalories: 899))
        #expect(result.calories == 89)
        #expect(result.provenance == .localNutrition)
        #expect(result.confidence == .high)
    }

    @Test("A hallucinated existing recipe ID cannot override a trusted local food")
    func hallucinatedRecipeIDCannotOverride() async throws {
        let resolver = MealResolver(nutritionTable: LocalNutritionTable(), recipeDatabase: LocalRecipeDatabase())
        let result = try await resolver.resolve(request(
            name: "banana",
            recipeID: "it.spaghetti_carbonara.roman",
            quantity: .grams(100),
            modelCalories: 899
        ))
        #expect(result.foodName == "banana")
        #expect(result.calories == 89)
        #expect(result.provenance == .localNutrition)
    }

    @Test("Unknown composition made entirely of local ingredients is medium trust")
    func modelAssistedComposition() async throws {
        let resolver = MealResolver(nutritionTable: LocalNutritionTable(), recipeDatabase: EmptyRecipeDatabase())
        let proposals = [
            ModelIngredientProposal(name: "rice", nameEnglish: "rice", ratio: 0.6),
            ModelIngredientProposal(name: "chicken", nameEnglish: "chicken", ratio: 0.4)
        ]
        let result = try await resolver.resolve(request(
            name: "unknown family dish",
            quantity: .grams(250),
            composite: true,
            proposals: proposals,
            modelCalories: 800
        ))
        #expect(result.provenance == .modelAssistedRecipe)
        #expect(result.confidence == .medium)
        #expect(result.ingredients?.reduce(0) { $0 + $1.grams } == 250)
    }

    @Test("Unresolved food uses clearly marked lowest-trust model nutrition")
    func finalModelFallback() async throws {
        let resolver = MealResolver(nutritionTable: EmptyNutritionTable(), recipeDatabase: EmptyRecipeDatabase())
        let result = try await resolver.resolve(request(
            name: "long-tail food",
            quantity: .grams(200),
            modelCalories: 175
        ))
        #expect(result.calories == 350)
        #expect(result.source == .model)
        #expect(result.provenance == .modelNutrition)
        #expect(result.confidence == .low)
    }

    private func request(
        name: String,
        baseName: String? = nil,
        lookupName: String? = nil,
        baseLookupName: String? = nil,
        recipeID: RecipeID? = nil,
        quantity: MealQuantity,
        modifications: [MealModification] = [],
        composite: Bool = false,
        proposals: [ModelIngredientProposal] = [],
        modelCalories: Int? = nil
    ) -> MealRequest {
        MealRequest(
            displayName: name,
            lookupName: lookupName ?? name,
            baseDisplayName: baseName ?? name,
            baseLookupName: baseLookupName ?? lookupName ?? baseName ?? name,
            recipeID: recipeID,
            languageCode: nil,
            localeIdentifier: nil,
            cuisine: nil,
            quantity: quantity,
            modifications: modifications,
            isCompositeDish: composite,
            proposedIngredients: proposals,
            modelCaloriesPer100g: modelCalories
        )
    }
}
