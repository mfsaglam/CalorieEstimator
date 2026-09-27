@testable import CalorieEstimator

struct StubMealRequestParser: MealRequestParsing {
    let request: MealRequest

    func parse(_ input: String, recipeDatabase: any RecipeDatabase) async throws -> MealRequest {
        request
    }
}

struct FailingMealRequestParser: MealRequestParsing {
    struct UnexpectedCall: Error {}

    func parse(_ input: String, recipeDatabase: any RecipeDatabase) async throws -> MealRequest {
        throw UnexpectedCall()
    }
}

actor CountingModelEnergyEstimator: ModelEnergyEstimating {
    private(set) var callCount = 0
    let value: ModelEnergyEstimate?

    init(value: ModelEnergyEstimate? = nil) {
        self.value = value
    }

    func estimate(foodDescription: String) async throws -> ModelEnergyEstimate {
        callCount += 1
        guard let value else {
            throw CalorieEstimatorError.parsingFailed(response: "stub energy estimator failure")
        }
        return value
    }
}

actor StubEnergyDensitySampleProvider: EnergyDensitySampleProviding {
    struct SampleFailure: Error {}

    private var samples: [Int?]
    private(set) var attempts: [Int] = []

    init(_ samples: [Int?]) {
        self.samples = samples
    }

    func sample(foodDescription: String, attempt: Int) async throws -> Int {
        attempts.append(attempt)
        let index = attempt - 1
        guard samples.indices.contains(index), let value = samples[index] else {
            throw SampleFailure()
        }
        return value
    }
}
