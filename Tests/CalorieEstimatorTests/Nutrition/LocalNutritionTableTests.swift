import Testing
@testable import CalorieEstimator

// MARK: - Local Nutrition Table

@Suite("Local Nutrition Table")
struct LocalNutritionTableTests {

    private let table = LocalNutritionTable()

    @Test("Exact match resolves")
    func exactMatch() {
        #expect(table.caloriesPer100g(for: "banana") == 89)
    }

    @Test("Plural resolves to the singular key")
    func pluralMatch() {
        #expect(table.caloriesPer100g(for: "eggs") == 155)
        #expect(table.caloriesPer100g(for: "almonds") == 579)
    }

    @Test("Case and punctuation are ignored")
    func normalisation() {
        #expect(table.caloriesPer100g(for: "  White Rice! ") == 130)
    }

    @Test("Modifier words resolve via the longest contained key")
    func substringMatch() {
        // "grilled chicken breast" → prefers "chicken breast" (165) over "chicken" (190).
        #expect(table.caloriesPer100g(for: "grilled chicken breast") == 165)
    }

    @Test("A whole-word match does not fire on a partial word")
    func noPartialWordMatch() {
        // "eggplant" must not match the "egg" key.
        #expect(table.caloriesPer100g(for: "eggplant") == 25)
    }

    @Test("Unknown foods miss")
    func unknownMisses() {
        #expect(table.caloriesPer100g(for: "grandma's mystery stew") == nil)
    }
}
