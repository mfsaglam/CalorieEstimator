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
