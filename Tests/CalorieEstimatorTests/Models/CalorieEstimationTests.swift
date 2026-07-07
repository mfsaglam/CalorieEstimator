import Testing
@testable import CalorieEstimator

// MARK: - CalorieEstimation

@Suite("CalorieEstimation")
struct CalorieEstimationTests {

    @Test("Stores calories and explanation")
    func initWithValues() {
        let estimation = CalorieEstimation(calories: 300, explanation: "Some explanation")
        #expect(estimation.calories == 300)
        #expect(estimation.explanation == "Some explanation")
        #expect(estimation.estimatedGrams == nil)
    }

    @Test("Stores estimatedGrams when provided")
    func initWithEstimatedGrams() {
        let estimation = CalorieEstimation(calories: 300, explanation: "test", estimatedGrams: 150)
        #expect(estimation.estimatedGrams == 150)
    }

    @Test("Explanation can be nil")
    func nilExplanation() {
        let estimation = CalorieEstimation(calories: 0, explanation: nil)
        #expect(estimation.calories == 0)
        #expect(estimation.explanation == nil)
    }
}
