import Foundation
import FoundationModels

/// Estimates calories for a meal using on-device Apple Intelligence.
///
/// Two entry points, matching how meals are logged:
/// - ``estimate(phrase:)`` — a natural-language phrase in a supported model language ("iki yumurta",
///   "200 g grilled chicken", "kremalı mantarlı makarna"). For the Siri-intent path.
/// - ``estimate(meal:weight:)`` — a food name plus an explicit weight. For the
///   text-field path; units (oz/lb/kg) are converted to grams in code, never by the model.
///
/// Both return a unified ``MealEstimate`` the app renders identically. Calorie figures
/// are resolved through a ``NutritionTable`` (the bundled ``LocalNutritionTable`` by
/// default) and computed in code; the model is only consulted when the food isn't in the
/// table. Known dishes are resolved through a trusted local recipe database. Unknown
/// dishes may use a model-proposed composition only when every ingredient resolves through
/// local nutrition. The caller never needs to select a path.
public struct CalorieEstimator: Sendable {

    /// The nutrition source consulted before (and instead of) model nutrition.
    let nutritionTable: any NutritionTable
    let recipeDatabase: any RecipeDatabase
    private let mealParser: any MealRequestParsing
    private let modelTimeout: Duration

    /// Create an estimator.
    /// - Parameters:
    ///   - nutritionTable: The source used to resolve calories-per-100g.
    ///   - recipeDatabase: Trusted recipe identities, aliases, and composition.
    public init(
        nutritionTable: any NutritionTable = LocalNutritionTable(),
        recipeDatabase: any RecipeDatabase = LocalRecipeDatabase()
    ) {
        self.nutritionTable = nutritionTable
        self.recipeDatabase = recipeDatabase
        self.mealParser = FoundationModelMealParser()
        self.modelTimeout = .seconds(60)
    }

    init(
        nutritionTable: any NutritionTable,
        recipeDatabase: any RecipeDatabase,
        mealParser: any MealRequestParsing,
        modelTimeout: Duration = .seconds(60)
    ) {
        self.nutritionTable = nutritionTable
        self.recipeDatabase = recipeDatabase
        self.mealParser = mealParser
        self.modelTimeout = modelTimeout
    }

    // MARK: - Public API

    /// Estimate a meal from a single natural-language phrase (the Siri-intent path).
    ///
    /// The phrase may describe the amount as a weight ("200 grams of grilled chicken"),
    /// a volume ("250 ml orange juice"), or a count ("two eggs", "a handful of almonds"),
    /// in a supported language. The model parses the food and amount; nutrition is
    /// then resolved using trusted recipe and nutrition data. Model-assisted decomposition
    /// and model nutrition are progressively lower-trust fallbacks. If no amount is stated,
    /// a single typical serving is assumed.
    ///
    /// - Parameter phrase: A spoken/typed description of a food and its amount.
    /// - Returns: A ``MealEstimate``; ``MealEstimate/ingredients`` is populated only for
    ///   composite dishes.
    /// - Throws: ``CalorieEstimatorError/modelUnavailable(reason:)`` when the on-device
    ///   model can't be used, or ``CalorieEstimatorError/parsingFailed(response:)`` when
    ///   the model returns unusable output.
    public func estimate(phrase: String) async throws -> MealEstimate {
        let request = try await parse(phrase)
        return try await MealResolver(
            nutritionTable: nutritionTable,
            recipeDatabase: recipeDatabase
        ).resolve(request)
    }

    /// Estimate a meal from a food name plus an explicit weight (the text-field path).
    ///
    /// The weight — grams, ounces, pounds, kilograms, anything — is converted to grams
    /// **in code** via `Measurement`; the model never parses units on this path.
    ///
    /// The food is looked up in the recipe database and then the nutrition table **before
    /// any model session is created**. On a hit, calories are computed in code. Only a
    /// complete local miss invokes semantic parsing and lower-trust fallbacks.
    ///
    /// - Parameters:
    ///   - meal: The food or dish name in a supported language or local alias.
    ///   - weight: The amount, in any mass unit; converted to grams internally.
    /// - Returns: A ``MealEstimate``; ``MealEstimate/ingredients`` is populated only for
    ///   composite dishes.
    /// - Throws: ``CalorieEstimatorError/parsingFailed(response:)`` for a non-positive
    ///   weight or unusable model output, or
    ///   ``CalorieEstimatorError/modelUnavailable(reason:)`` when a model call is needed
    ///   but the model can't be used. A table hit never touches the model and never throws
    ///   ``CalorieEstimatorError/modelUnavailable(reason:)``.
    public func estimate(meal: String, weight: Measurement<UnitMass>) async throws -> MealEstimate {
        let grams = Int(weight.converted(to: .grams).value.rounded())
        guard grams > 0 else {
            throw CalorieEstimatorError.parsingFailed(response: "weight must be positive, got \(weight)")
        }

        let resolver = MealResolver(nutritionTable: nutritionTable, recipeDatabase: recipeDatabase)

        // Trusted recipes precede broad nutrition matching so a prepared dish can never
        // be mistaken for one ingredient or bypass deterministic decomposition.
        if let known = try await resolver.knownEstimate(name: meal, grams: grams) {
            return known
        }

        let request = try await parse(meal)
        return try await resolver.resolve(request, overridingGrams: grams)
    }

    /// Convenience overload of ``estimate(meal:weight:)`` taking a gram weight directly.
    ///
    /// - Parameters:
    ///   - meal: The food or dish name in a supported language or local alias.
    ///   - grams: The weight in grams.
    public func estimate(meal: String, grams: Int) async throws -> MealEstimate {
        try await estimate(meal: meal, weight: Measurement(value: Double(grams), unit: .grams))
    }

    private func parse(_ input: String) async throws -> MealRequest {
        let parser = mealParser
        let database = recipeDatabase
        return try await AsyncTimeout.run(after: modelTimeout) {
            try await parser.parse(input, recipeDatabase: database)
        }
    }

    /// The on-device model, or a throw describing why it's unavailable.
    static func availableModel() throws -> SystemLanguageModel {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else {
            throw CalorieEstimatorError.modelUnavailable(
                reason: FoundationModelMealParser.description(for: model.availability)
            )
        }
        return model
    }

}
