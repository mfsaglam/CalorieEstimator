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

    @Test("Unresolved food uses clearly marked lowest-trust model nutrition")
    func finalModelFallback() async throws {
        let result = try await CalorieEstimator(
            nutritionTable: EmptyNutritionTable(),
            recipeDatabase: EmptyRecipeDatabase(),
            mealParser: FailingMealRequestParser(),
            modelEnergyEstimator: CountingModelEnergyEstimator(
                value: ModelEnergyEstimate(
                    caloriesPer100Grams: 175,
                    confidence: .low,
                    validSamples: [175]
                )
            )
        ).estimate(meal: "long-tail food", grams: 200)
        #expect(result.calories == 350)
        #expect(result.source == .model)
        #expect(result.provenance == .modelNutrition)
        #expect(result.confidence == .low)
        #expect(result.ingredients?.isEmpty == true)
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
            quantityScope: .finalMeal,
            modifications: modifications,
            isCompositeDish: composite,
            proposedIngredients: proposals,
            modelCaloriesPer100g: modelCalories
        )
    }
}
