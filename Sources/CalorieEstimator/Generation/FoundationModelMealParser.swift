import Foundation
import FoundationModels

protocol MealRequestParsing: Sendable {
    func parse(_ input: String, recipeDatabase: any RecipeDatabase) async throws -> MealRequest
}

struct FoundationModelMealParser: MealRequestParsing {
    func parse(_ input: String, recipeDatabase: any RecipeDatabase) async throws -> MealRequest {
        let model = try CalorieEstimator.availableModel()
        let generated: ParsedMealResponse
        do {
            generated = try await Self.respond(
                input: input,
                model: model,
                tools: [RecipeDatabaseTool(database: recipeDatabase)]
            )
        } catch {
            // Some early OS builds expose the Tool API in the SDK but reject its internal
            // instruction prefix at runtime. Alias validation still happens in Swift, so
            // retry semantic parsing without tools instead of losing long-tail coverage.
            let description = String(reflecting: error)
            guard description.contains("tool_calls_override") else { throw error }
            generated = try await Self.respond(input: input, model: model, tools: [])
        }
        return Self.makeRequest(from: generated)
    }

    private static func respond(
        input: String,
        model: SystemLanguageModel,
        tools: [any Tool]
    ) async throws -> ParsedMealResponse {
        let session = LanguageModelSession(model: model, tools: tools, instructions: instructions)
        return try await session.respond(
            to: "Food description: \(input)",
            generating: ParsedMealResponse.self,
            options: GenerationOptions(samplingMode: .greedy)
        ).content
    }

    static func makeRequest(from generated: ParsedMealResponse) -> MealRequest {
        MealRequest(
            displayName: generated.foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            lookupName: generated.foodNameEnglish.trimmingCharacters(in: .whitespacesAndNewlines),
            recipeID: nonempty(generated.recipeID).map(RecipeID.init(rawValue:)),
            languageCode: nonempty(generated.languageCode),
            localeIdentifier: nonempty(generated.localeIdentifier),
            cuisine: nonempty(generated.cuisine),
            quantity: MealQuantity(
                amount: generated.amount,
                unit: unit(from: generated.unit),
                estimatedGrams: generated.estimatedGrams > 0 ? generated.estimatedGrams : nil
            ),
            modifications: generated.modifications.map {
                MealModification(
                    kind: modificationKind(from: $0.kind),
                    ingredientName: $0.ingredientName,
                    ingredientNameEnglish: $0.ingredientNameEnglish,
                    estimatedGrams: $0.estimatedGrams > 0 ? $0.estimatedGrams : nil
                )
            },
            isCompositeDish: generated.isCompositeDish,
            proposedIngredients: generated.proposedIngredients.map {
                ModelIngredientProposal(name: $0.name, nameEnglish: $0.nameEnglish, ratio: $0.ratio)
            },
            modelCaloriesPer100g: generated.fallbackCaloriesPer100g
        )
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unit(from unit: GeneratedQuantityUnit) -> MealQuantityUnit {
        switch unit {
        case .gram: .gram
        case .kilogram: .kilogram
        case .ounce: .ounce
        case .pound: .pound
        case .milliliter: .milliliter
        case .liter: .liter
        case .serving: .serving
        case .bowl: .bowl
        case .cup: .cup
        case .slice: .slice
        case .piece: .piece
        case .item: .item
        }
    }

    private static func modificationKind(from kind: GeneratedModificationKind) -> MealModificationKind {
        switch kind {
        case .add: .add
        case .remove: .remove
        case .increase: .increase
        case .decrease: .decrease
        }
    }

    private static let instructions = """
    Parse food descriptions in the user's language into typed semantic data. Never perform
    calorie arithmetic. Use lookupLocalRecipe to search trusted local recipes. If it returns
    a recipe ID, copy that ID exactly and leave proposedIngredients empty. Never add, remove,
    or change ingredients of a known recipe unless the user explicitly requested a modifier.
    Preserve meaningful cuisine and regional distinctions instead of translating distinct
    dishes into a generic dish. Return the stated unit rather than converting mass units.
    For ambiguous portions, provide a reasonable estimated total gram weight. For an unknown
    composite dish only, propose a compact ingredient-ratio breakdown. The whole-food calorie
    density is a last-resort estimate and will be ignored whenever local knowledge resolves.
    """

    static func description(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            "available"
        case .unavailable(.deviceNotEligible):
            "this device does not support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence is not enabled in Settings"
        case .unavailable(.modelNotReady):
            "the on-device model is not ready yet (it may still be downloading)"
        case .unavailable(let other):
            "unavailable for an unknown reason (\(other))"
        }
    }
}
