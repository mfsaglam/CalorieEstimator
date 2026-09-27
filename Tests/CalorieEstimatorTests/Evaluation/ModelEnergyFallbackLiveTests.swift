import Foundation
import Testing
@testable import CalorieEstimator

@Suite(
    "Model Energy Fallback Live Verification",
    .enabled(if: ProcessInfo.processInfo.environment["CALORIE_ESTIMATOR_RUN_FALLBACK_LIVE_TESTS"] == "1"),
    .serialized
)
struct ModelEnergyFallbackLiveTests {
    @Test("Exactly three scenarios and nine maximum model requests")
    func threeBoundedScenarios() async {
        let foods = ["Türk kahvaltısı", "English breakfast", "shakshuka"]

        for food in foods {
            let clock = ContinuousClock()
            let started = clock.now
            do {
                let aggregate = try await AsyncTimeout.run(after: .seconds(60)) {
                    try await ThreeSampleModelEnergyEstimator().estimate(foodDescription: food)
                }
                let result = MealEstimate(
                    foodName: food,
                    grams: 100,
                    calories: RecipeDecomposer.calories(
                        density: aggregate.caloriesPer100Grams,
                        grams: 100
                    ),
                    source: .model,
                    confidence: aggregate.confidence,
                    ingredients: [],
                    provenance: .modelNutrition
                )
                let renderedSamples = aggregate.samples.map {
                    $0.map(String.init) ?? "invalid"
                }
                print("""
                LIVE FALLBACK | 100g \(food)
                sample 1: \(renderedSamples[0])
                sample 2: \(renderedSamples[1])
                sample 3: \(renderedSamples[2])
                median: \(aggregate.caloriesPer100Grams) kcal/100g
                final kcal: \(result.calories)
                confidence: \(String(describing: result.confidence))
                provenance: \(result.provenance)
                ingredients count: \(result.ingredients?.count ?? 0)
                elapsed: \(started.duration(to: clock.now))
                """)
            } catch {
                print("""
                LIVE FALLBACK | 100g \(food)
                samples/median/final: unavailable (controlled error)
                confidence/provenance/ingredients: unavailable (controlled error)
                error: \(error)
                elapsed: \(started.duration(to: clock.now))
                """)
            }
        }
    }
}
