import Foundation
import FoundationModels

/// A validated, aggregated result from the three bounded model samples.
struct ModelEnergyEstimate: Sendable, Equatable {
    /// Ordinary edible foods, including nearly pure cooking fats, should not exceed
    /// 900 kcal/100g. Values outside this range are rejected rather than clamped.
    static let validCaloriesPer100Grams = 1...900

    let caloriesPer100Grams: Int
    let confidence: Confidence
    let validSamples: [Int]
    /// Original attempt order; nil marks a failed or deterministically rejected sample.
    let samples: [Int?]

    init(
        caloriesPer100Grams: Int,
        confidence: Confidence,
        validSamples: [Int],
        samples: [Int?]? = nil
    ) {
        self.caloriesPer100Grams = caloriesPer100Grams
        self.confidence = confidence
        self.validSamples = validSamples
        self.samples = samples ?? validSamples.map(Optional.some)
    }

    static func aggregate(_ samples: [Int?]) throws -> Self {
        let valid = samples.compactMap { sample -> Int? in
            guard let sample, validCaloriesPer100Grams.contains(sample) else { return nil }
            return sample
        }.sorted()

        guard !valid.isEmpty else {
            throw CalorieEstimatorError.parsingFailed(
                response: "all three model energy-density samples were invalid"
            )
        }

        let selected: Int
        switch valid.count {
        case 1:
            selected = valid[0]
        case 2:
            // With no unique mathematical median, prefer the upper middle value. This
            // deterministic conservative policy avoids understating energy intake.
            selected = valid[1]
        default:
            selected = valid[valid.count / 2]
        }

        let confidence: Confidence
        if valid.count == 1 {
            confidence = .low
        } else {
            let relativeSpread = Double(valid.last! - valid.first!) / Double(selected)
            // The public confidence model has no "unreliable" case. Agreement within
            // 20% earns medium; every wider spread remains at the lowest available level.
            confidence = relativeSpread <= 0.20 ? .medium : .low
        }

        return Self(
            caloriesPer100Grams: selected,
            confidence: confidence,
            validSamples: valid,
            samples: samples.map { sample in
                guard let sample, validCaloriesPer100Grams.contains(sample) else { return nil }
                return sample
            }
        )
    }
}

protocol ModelEnergyEstimating: Sendable {
    func estimate(foodDescription: String) async throws -> ModelEnergyEstimate
}

protocol EnergyDensitySampleProviding: Sendable {
    func sample(foodDescription: String, attempt: Int) async throws -> Int
}

/// Runs exactly three predefined samples. A failed or invalid sample is discarded;
/// there is deliberately no retry loop.
struct ThreeSampleModelEnergyEstimator: ModelEnergyEstimating {
    private let sampleProvider: any EnergyDensitySampleProviding

    init(sampleProvider: any EnergyDensitySampleProviding = FoundationModelEnergySampleProvider()) {
        self.sampleProvider = sampleProvider
    }

    func estimate(foodDescription: String) async throws -> ModelEnergyEstimate {
        var samples: [Int?] = []
        samples.reserveCapacity(3)

        for attempt in 1...3 {
            do {
                samples.append(try await sampleProvider.sample(
                    foodDescription: foodDescription,
                    attempt: attempt
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                samples.append(nil)
            }
        }

        return try ModelEnergyEstimate.aggregate(samples)
    }
}

private struct FoundationModelEnergySampleProvider: EnergyDensitySampleProviding {
    func sample(foodDescription: String, attempt: Int) async throws -> Int {
        let model = try CalorieEstimator.availableModel()
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: "Food or meal description: \(foodDescription)",
            generating: GeneratedEnergyEstimate.self,
            options: GenerationOptions(
                samplingMode: .random(top: 20, seed: Self.seeds[attempt - 1]),
                temperature: 0.7
            )
        ).content
        return response.caloriesPer100Grams
    }

    private static let seeds: [UInt64] = [0xC0A1, 0xC0A2, 0xC0A3]

    private static let instructions = """
    Estimate only the calories per 100 grams of a typical representative version of the
    described edible food or meal. General meal names such as a regional breakfast, hotel
    breakfast, mixed plate, or homemade casserole are legitimate. Do not list or generate
    ingredients, do not calculate a requested portion's total calories, and do not explain.
    Return only the requested typed energy-density value.
    """
}
