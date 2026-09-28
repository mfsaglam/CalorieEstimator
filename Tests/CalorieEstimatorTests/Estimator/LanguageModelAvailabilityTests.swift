import Testing
@testable import CalorieEstimator

@Suite("Language Model Availability Boundaries")
struct LanguageModelAvailabilityTests {
    @Test("Phrase input fails before semantic parsing when the model is unavailable")
    func phraseFailsBeforeParsing() async {
        let energyEstimator = CountingModelEnergyEstimator()
        let estimator = CalorieEstimator(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: LocalRecipeDatabase(),
            mealParser: FailingMealRequestParser(),
            modelEnergyEstimator: energyEstimator,
            modelAvailability: StubLanguageModelAvailabilityProvider.unavailable(
                "Apple Intelligence is disabled"
            )
        )

        do {
            _ = try await estimator.estimate(phrase: "200g carbonara")
            Issue.record("Expected modelUnavailable")
        } catch CalorieEstimatorError.modelUnavailable(let reason) {
            #expect(reason == "Apple Intelligence is disabled")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await energyEstimator.callCount == 0)
    }

    @Test("Structured recipe lookup succeeds without the model")
    func structuredRecipeWorksOffline() async throws {
        let energyEstimator = CountingModelEnergyEstimator()
        let estimator = offlineEstimator(energyEstimator: energyEstimator)

        let result = try await estimator.estimate(meal: "spaghetti carbonara", grams: 200)

        #expect(result.provenance == .localRecipe)
        #expect(result.confidence == .high)
        #expect(result.recipeID == "it.spaghetti_carbonara.roman")
        #expect(result.grams == 200)
        #expect(result.ingredients?.reduce(0) { $0 + $1.grams } == 200)
        #expect(await energyEstimator.callCount == 0)
    }

    @Test("Structured localized alias resolves without the model")
    func structuredLocalizedAliasWorksOffline() async throws {
        let energyEstimator = CountingModelEnergyEstimator()
        let estimator = offlineEstimator(energyEstimator: energyEstimator)

        let result = try await estimator.estimate(meal: "Καρμπονάρα", grams: 200)

        #expect(result.provenance == .localRecipe)
        #expect(result.recipeID == "it.spaghetti_carbonara.roman")
        #expect(result.grams == 200)
        #expect(await energyEstimator.callCount == 0)
    }

    @Test("Structured simple-food nutrition lookup succeeds without the model")
    func structuredNutritionWorksOffline() async throws {
        let energyEstimator = CountingModelEnergyEstimator()
        let estimator = offlineEstimator(energyEstimator: energyEstimator)

        let result = try await estimator.estimate(meal: "banana", grams: 100)

        #expect(result.provenance == .localNutrition)
        #expect(result.confidence == .high)
        #expect(result.grams == 100)
        #expect(await energyEstimator.callCount == 0)
    }

    @Test("Structured local miss fails without invoking model fallback")
    func structuredMissFailsOffline() async {
        let energyEstimator = CountingModelEnergyEstimator()
        let estimator = offlineEstimator(energyEstimator: energyEstimator)

        do {
            _ = try await estimator.estimate(meal: "some unknown meal", grams: 200)
            Issue.record("Expected modelUnavailable")
        } catch CalorieEstimatorError.modelUnavailable(let reason) {
            #expect(!reason.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await energyEstimator.callCount == 0)
    }

    @Test("Structured local miss preserves model fallback when available")
    func structuredMissUsesModelWhenAvailable() async throws {
        let energyEstimator = CountingModelEnergyEstimator(
            value: ModelEnergyEstimate(
                caloriesPer100Grams: 175,
                confidence: .medium,
                validSamples: [170, 175, 180]
            )
        )
        let estimator = CalorieEstimator(
            nutritionTable: EmptyNutritionTable(),
            recipeDatabase: EmptyRecipeDatabase(),
            mealParser: FailingMealRequestParser(),
            modelEnergyEstimator: energyEstimator,
            modelAvailability: StubLanguageModelAvailabilityProvider.available
        )

        let result = try await estimator.estimate(meal: "some unknown meal", grams: 200)

        #expect(result.calories == 350)
        #expect(result.provenance == .modelNutrition)
        #expect(await energyEstimator.callCount == 1)
    }

    private func offlineEstimator(
        energyEstimator: CountingModelEnergyEstimator
    ) -> CalorieEstimator {
        CalorieEstimator(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: LocalRecipeDatabase(),
            mealParser: FailingMealRequestParser(),
            modelEnergyEstimator: energyEstimator,
            modelAvailability: StubLanguageModelAvailabilityProvider.unavailable()
        )
    }
}
