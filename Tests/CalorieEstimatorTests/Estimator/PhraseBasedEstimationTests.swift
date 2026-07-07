import Testing
import Foundation
@testable import CalorieEstimator

// MARK: - Phrase-Based Estimation (on-device model)
//
// These tests exercise the real on-device model, so their exact numbers are
// non-deterministic. They assert on invariants (non-empty food name, no digits
// in the name, sane gram range, positive calories) rather than exact values.
// They require a device with Apple Intelligence available.

@Suite("Phrase-Based Estimation")
struct PhraseBasedEstimationTests {

    private let estimator = CalorieEstimator()

    /// Shared invariants every phrase estimate must satisfy.
    private func assertInvariants(_ estimate: MealEstimate, gramRange: ClosedRange<Int>) {
        let trimmedName = estimate.foodName.trimmingCharacters(in: .whitespaces)
        let hasDigits = estimate.foodName.contains(where: \.isNumber)
        #expect(!trimmedName.isEmpty)
        #expect(!hasDigits, "Food name should not contain digits: \(estimate.foodName)")
        #expect(gramRange.contains(estimate.grams), "grams \(estimate.grams) outside expected range \(gramRange)")
        #expect(estimate.calories > 0)
    }

    @Test("Weight phrase: 200 grams of chicken")
    func weightPhrase() async throws {
        let estimate = try await estimator.estimate(phrase: "200 grams of grilled chicken")
        assertInvariants(estimate, gramRange: 150...260)
        #expect(estimate.foodName.localizedCaseInsensitiveContains("chicken"))
    }

    @Test("Word-number weight phrase: eight ounces of salmon")
    func wordNumberWeightPhrase() async throws {
        // Eight ounces ≈ 227 g.
        let estimate = try await estimator.estimate(phrase: "eight ounces of salmon")
        assertInvariants(estimate, gramRange: 150...320)
        #expect(estimate.foodName.localizedCaseInsensitiveContains("salmon"))
    }

    @Test("Volume phrase: 250 ml orange juice")
    func volumePhrase() async throws {
        // 250 ml of juice ≈ 250 g.
        let estimate = try await estimator.estimate(phrase: "250 ml orange juice")
        assertInvariants(estimate, gramRange: 150...400)
    }

    @Test("Count phrase: two eggs")
    func countPhrase() async throws {
        let estimate = try await estimator.estimate(phrase: "two eggs")
        assertInvariants(estimate, gramRange: 60...200)
        #expect(estimate.foodName.localizedCaseInsensitiveContains("egg"))
    }

    @Test("Bare food with no amount: banana")
    func bareFood() async throws {
        // No amount stated → a single typical serving.
        let estimate = try await estimator.estimate(phrase: "banana")
        assertInvariants(estimate, gramRange: 50...400)
        #expect(estimate.foodName.localizedCaseInsensitiveContains("banana"))
    }
}
