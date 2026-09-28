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
/// foods use a bounded three-sample model energy-density estimate without a generated
/// ingredient decomposition. The caller never needs to select a path.
public struct CalorieEstimator: Sendable {

    /// The nutrition source consulted before (and instead of) model nutrition.
    let nutritionTable: any NutritionTable
    let recipeDatabase: any RecipeDatabase
    private let mealParser: any MealRequestParsing
    private let modelEnergyEstimator: any ModelEnergyEstimating
    private let modelAvailability: any LanguageModelAvailabilityProviding
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
        self.modelEnergyEstimator = ThreeSampleModelEnergyEstimator()
        self.modelAvailability = SystemLanguageModelAvailabilityProvider()
        self.modelTimeout = .seconds(60)
    }

    init(
        nutritionTable: any NutritionTable,
        recipeDatabase: any RecipeDatabase,
        mealParser: any MealRequestParsing,
        modelEnergyEstimator: any ModelEnergyEstimating = ThreeSampleModelEnergyEstimator(),
        modelAvailability: any LanguageModelAvailabilityProviding = SystemLanguageModelAvailabilityProvider(),
        modelTimeout: Duration = .seconds(60)
    ) {
        self.nutritionTable = nutritionTable
        self.recipeDatabase = recipeDatabase
        self.mealParser = mealParser
        self.modelEnergyEstimator = modelEnergyEstimator
        self.modelAvailability = modelAvailability
        self.modelTimeout = modelTimeout
    }

    // MARK: - Public API

    /// Estimate a meal from a single natural-language phrase (the Siri-intent path).
    ///
    /// The phrase may describe the amount as a weight ("200 grams of grilled chicken"),
    /// a volume ("250 ml orange juice"), or a count ("two eggs", "a handful of almonds"),
    /// in a supported language. The model parses the food and amount; nutrition is
    /// then resolved using trusted recipe and nutrition data. On a complete local miss,
    /// three bounded model energy-density samples provide the final fallback. If no amount
    /// is stated, a single typical serving is assumed.
    ///
    /// - Parameter phrase: A spoken/typed description of a food and its amount.
    /// - Returns: A ``MealEstimate``; ``MealEstimate/ingredients`` is populated only for
    ///   composite dishes.
    /// - Throws: ``CalorieEstimatorError/modelUnavailable(reason:)`` when the on-device
    ///   model can't be used, or ``CalorieEstimatorError/parsingFailed(response:)`` when
    ///   the model returns unusable output.
    public func estimate(phrase: String) async throws -> MealEstimate {
        try requireAvailableModel()
        let request = try await parse(phrase)
        let resolver = MealResolver(
            nutritionTable: nutritionTable,
            recipeDatabase: recipeDatabase
        )
        if let known = try await resolver.resolveKnown(request) {
            return known
        }
        let grams = try resolver.resolveGrams(
            request.quantity,
            defaultServingGrams: nil,
            override: nil
        )
        let name = request.displayName.isEmpty ? request.lookupName : request.displayName
        return try await makeModelFallback(foodDescription: name, displayName: name, grams: grams)
    }

    /// Estimate a meal from a food name plus an explicit weight (the text-field path).
    ///
    /// The weight — grams, ounces, pounds, kilograms, anything — is converted to grams
    /// **in code** via `Measurement`; the model never parses units on this path.
    ///
    /// The food is looked up in the recipe database and then the nutrition table **before
    /// any model session is created**. On a hit, calories are computed in code. Only a
    /// complete local miss invokes the bounded model nutrition fallback.
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

        // With an explicit weight there is no semantic parsing work left. A complete
        // trusted miss uses the three-sample density fallback only when the model is
        // available. The local lookup above remains usable without Apple Intelligence.
        try requireAvailableModel()
        return try await makeModelFallback(foodDescription: meal, displayName: meal, grams: grams)
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

    private func makeModelFallback(
        foodDescription: String,
        displayName: String,
        grams: Int
    ) async throws -> MealEstimate {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, grams > 0 else {
            throw CalorieEstimatorError.parsingFailed(
                response: "foodName=\"\(displayName)\", grams=\(grams)"
            )
        }

        let estimator = modelEnergyEstimator
        let aggregate = try await AsyncTimeout.run(after: modelTimeout) {
            try await estimator.estimate(foodDescription: foodDescription)
        }
        return MealEstimate(
            foodName: name,
            grams: grams,
            calories: RecipeDecomposer.calories(
                density: aggregate.caloriesPer100Grams,
                grams: grams
            ),
            source: .model,
            confidence: aggregate.confidence,
            ingredients: [],
            provenance: .modelNutrition
        )
    }

    private func requireAvailableModel() throws {
        if let reason = modelAvailability.unavailableReason {
            throw CalorieEstimatorError.modelUnavailable(reason: reason)
        }
    }

    /// The on-device model, or a throw describing why it's unavailable.
    static func availableModel() throws -> SystemLanguageModel {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        if let reason = SystemLanguageModelAvailabilityProvider.unavailableReason(
            for: model.availability
        ) {
            throw CalorieEstimatorError.modelUnavailable(reason: reason)
        }
        return model
    }

}
