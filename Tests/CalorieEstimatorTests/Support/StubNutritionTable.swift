@testable import CalorieEstimator

/// A stub table that always resolves to a fixed value, for testing the override path
/// independently of the bundled data.
struct StubNutritionTable: NutritionTable {
    let value: Int?
    func caloriesPer100g(for foodName: String) -> Int? { value }
}
