import Testing
@testable import CalorieEstimator

@Suite("Three-Sample Model Energy Fallback")
struct ModelEnergyFallbackTests {
    @Test("Three valid samples use their median")
    func median() throws {
        let result = try ModelEnergyEstimate.aggregate([215, 238, 410])
        #expect(result.caloriesPer100Grams == 238)
        #expect(result.validSamples == [215, 238, 410])
    }

    @Test("Close samples receive higher confidence than wide samples")
    func confidenceFromAgreement() throws {
        let close = try ModelEnergyEstimate.aggregate([220, 230, 240])
        let wide = try ModelEnergyEstimate.aggregate([100, 230, 500])
        #expect(close.confidence == .medium)
        #expect(wide.confidence == .low)
        #expect(close.confidence != .high)
        #expect(wide.confidence != .high)
    }

    @Test("Two valid samples use the conservative upper middle value")
    func twoSamplePolicy() throws {
        let result = try ModelEnergyEstimate.aggregate([210, nil, 240])
        #expect(result.caloriesPer100Grams == 240)
        #expect(result.confidence == .medium)
    }

    @Test("One failed sample is rejected without a retry")
    func invalidSampleRejection() async throws {
        let provider = StubEnergyDensitySampleProvider([230, nil, 240])
        let result = try await ThreeSampleModelEnergyEstimator(sampleProvider: provider)
            .estimate(foodDescription: "unknown dish")
        #expect(result.caloriesPer100Grams == 240)
        #expect(result.validSamples == [230, 240])
        #expect(await provider.attempts == [1, 2, 3])
    }

    @Test("Out-of-range values are rejected rather than clamped")
    func numericValidation() throws {
        let result = try ModelEnergyEstimate.aggregate([0, 230, 901])
        #expect(result.caloriesPer100Grams == 230)
        #expect(result.validSamples == [230])
        #expect(result.confidence == .low)
    }

    @Test("All invalid samples produce the controlled estimation error")
    func allInvalid() async {
        let provider = StubEnergyDensitySampleProvider([0, nil, 901])
        let estimator = ThreeSampleModelEnergyEstimator(sampleProvider: provider)
        await #expect(throws: CalorieEstimatorError.self) {
            _ = try await estimator.estimate(foodDescription: "unknown dish")
        }
        #expect(await provider.attempts == [1, 2, 3])
    }

    @Test("Swift scales density to quantity and hides ingredients")
    func quantityArithmeticAndResultBoundary() async throws {
        let request = MealRequest(
            displayName: "unknown casserole",
            lookupName: "unknown casserole",
            baseDisplayName: "unknown casserole",
            baseLookupName: "unknown casserole",
            recipeID: nil,
            languageCode: "en",
            localeIdentifier: nil,
            cuisine: nil,
            quantity: .grams(180),
            quantityScope: .finalMeal,
            modifications: [],
            isCompositeDish: true,
            proposedIngredients: [],
            modelCaloriesPer100g: nil
        )
        let estimator = CalorieEstimator(
            nutritionTable: EmptyNutritionTable(),
            recipeDatabase: EmptyRecipeDatabase(),
            mealParser: StubMealRequestParser(request: request),
            modelEnergyEstimator: CountingModelEnergyEstimator(
                value: ModelEnergyEstimate(
                    caloriesPer100Grams: 230,
                    confidence: .medium,
                    validSamples: [225, 230, 235]
                )
            )
        )

        let result = try await estimator.estimate(phrase: "180g unknown casserole")
        #expect(result.calories == 414)
        #expect(result.grams == 180)
        #expect(result.ingredients?.isEmpty == true)
        #expect(result.provenance == .modelNutrition)
        #expect(result.provenance != .localRecipe)
        #expect(result.recipeID == nil)
        #expect(result.confidence == .medium)
    }

    @Test("Trusted recipe and nutrition hits never invoke model energy fallback")
    func trustOrdering() async throws {
        let energyEstimator = CountingModelEnergyEstimator()
        let estimator = CalorieEstimator(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: LocalRecipeDatabase(),
            mealParser: FailingMealRequestParser(),
            modelEnergyEstimator: energyEstimator
        )

        let recipe = try await estimator.estimate(meal: "cheeseburger", grams: 200)
        let nutrition = try await estimator.estimate(meal: "banana", grams: 100)

        #expect(recipe.provenance == .localRecipe)
        #expect(nutrition.provenance == .localNutrition)
        #expect(await energyEstimator.callCount == 0)
    }
}
