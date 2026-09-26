import Foundation
import FoundationModels

protocol MealRequestParsing: Sendable {
    func parse(_ input: String, recipeDatabase: any RecipeDatabase) async throws -> MealRequest
}

struct FoundationModelMealParser: MealRequestParsing {
    func parse(_ input: String, recipeDatabase: any RecipeDatabase) async throws -> MealRequest {
        let model = try CalorieEstimator.availableModel()
        let trustedCandidate = try await recipeDatabase.recipeCandidate(
            containedIn: RecipeQuery(name: input)
        )
        if let trustedCandidate {
            let quantity = try await Self.respond(input: input, model: model, tools: [])
            let translation = try await Self.translatePreservingModifiers(input: input, model: model)
            let existingModifications = try await Self.respondForKnownExistingIngredientChanges(
                input: input,
                englishDescription: translation.englishDescription,
                recipe: trustedCandidate,
                model: model
            )
            let modifications = try await Self.respondForKnownRecipeModifications(
                input: input,
                englishDescription: translation.englishDescription,
                recipe: trustedCandidate,
                quantity: quantity,
                model: model
            )
            let resolvedAdditions = try await Self.resolveNewIngredientAdditions(
                modifications.addedNewIngredients,
                trustedRecipe: trustedCandidate,
                recipeDatabase: recipeDatabase,
                languageCode: Self.nonempty(quantity.languageCode),
                localeIdentifier: Self.nonempty(quantity.localeIdentifier),
                sourceDescriptions: [input, translation.englishDescription]
            )
            return Self.makeRequest(
                quantity: quantity,
                existingModifications: existingModifications,
                modifications: modifications,
                resolvedAdditions: resolvedAdditions,
                trustedRecipe: trustedCandidate,
                sourceDescriptions: [input, translation.englishDescription],
                explicitMassesGrams: translation.explicitMassesGrams
            )
        }

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
            generated = try await Self.respond(
                input: input,
                model: model,
                tools: []
            )
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

    private static func translatePreservingModifiers(
        input: String,
        model: SystemLanguageModel
    ) async throws -> GeneratedModifierPreservingTranslation {
        let session = LanguageModelSession(model: model, instructions: modifierTranslationInstructions)
        return try await session.respond(
            to: "Food description: \(input)",
            generating: GeneratedModifierPreservingTranslation.self,
            options: GenerationOptions(samplingMode: .greedy)
        ).content
    }

    private static func respondForKnownRecipeModifications(
        input: String,
        englishDescription: String,
        recipe: Recipe,
        quantity: ParsedMealResponse,
        model: SystemLanguageModel
    ) async throws -> ParsedKnownRecipeModificationsResponse {
        let baseIngredients = recipe.ingredients.enumerated().map { index, ingredient in
            "\(index + 1). \(ingredient.canonicalName) [nutrition name: \(ingredient.nutritionLookupName)]"
        }.joined(separator: ", ")
        let mealUnit = unit(from: quantity.unit).rawValue
        let session = LanguageModelSession(model: model, instructions: knownRecipeModificationInstructions)
        return try await session.respond(
            to: """
            Original food description: \(input)
            Faithful English description: \(englishDescription)
            Trusted base recipe: \(recipe.canonicalName)
            Existing base ingredients: \(baseIngredients)
            Protected whole-meal quantity: \(quantity.amount) \(mealUnit)
            """,
            generating: ParsedKnownRecipeModificationsResponse.self,
            options: GenerationOptions(samplingMode: .greedy)
        ).content
    }

    private static func respondForKnownExistingIngredientChanges(
        input: String,
        englishDescription: String,
        recipe: Recipe,
        model: SystemLanguageModel
    ) async throws -> [MealModification] {
        let numberedIngredients = recipe.ingredients.enumerated().map { index, ingredient in
            "\(index + 1). \(ingredient.canonicalName) [nutrition name: \(ingredient.nutritionLookupName)]"
        }.joined(separator: ", ")
        var modifications: [MealModification] = []
        for (index, ingredient) in recipe.ingredients.enumerated() {
            let session = LanguageModelSession(model: model, instructions: existingIngredientChangeInstructions)
            let decision = try await session.respond(
                to: """
                Original food description: \(input)
                English rendering (which may be imperfect): \(englishDescription)
                Trusted base recipe: \(recipe.canonicalName)
                All existing base ingredients: \(numberedIngredients)
                Target ingredient to decide: \(ingredient.canonicalName) [nutrition name: \(ingredient.nutritionLookupName)]
                """,
                generating: GeneratedExistingIngredientChangeDecision.self,
                options: GenerationOptions(samplingMode: .greedy)
            ).content
            let normalizedEvidence = FoodNameNormalizer.normalize(decision.evidenceText)
            let protectedTokens = Set(
                ([recipe.canonicalName] + recipe.ingredients.flatMap {
                    [$0.canonicalName, $0.nutritionLookupName]
                })
                .flatMap { FoodNameNormalizer.normalize($0).split(separator: " ") }
                .map(String.init)
            )
            let evidenceLetterTokens = normalizedEvidence
                .split(separator: " ")
                .map(String.init)
                .filter { token in
                    token.unicodeScalars.contains { CharacterSet.letters.contains($0) }
                }
            guard decision.hasExplicitChange,
                  normalizedEvidence.split(separator: " ").count >= 2,
                  exactEvidenceIsGrounded(decision.evidenceText, in: [input]),
                  evidenceLetterTokens.contains(where: { !protectedTokens.contains($0) }) else {
                continue
            }
            let interpretation = try await interpretChangeEvidence(
                decision.evidenceText,
                model: model
            )
            guard translatedEvidence(
                interpretation.englishTranslation,
                names: ingredient
            ) else { continue }
            let kind: MealModificationKind = switch interpretation.direction {
            case .useMore: .increase
            case .useLess: .decrease
            case .removeEntirely: .remove
            }
            let selection = TrustedIngredientSelection(
                kind: kind,
                candidateNumber: index + 1,
                grams: interpretation.hasExplicitGrams && interpretation.explicitGrams > 0
                    ? interpretation.explicitGrams
                    : nil
            )
            if let modification = canonicalModification(from: selection, in: recipe) {
                modifications.append(modification)
            }
        }
        return modifications
    }

    static func canonicalModification(
        from selection: TrustedIngredientSelection,
        in recipe: Recipe
    ) -> MealModification? {
        let index = selection.candidateNumber - 1
        guard recipe.ingredients.indices.contains(index) else { return nil }
        let ingredient = recipe.ingredients[index]
        return MealModification(
            kind: selection.kind,
            ingredientID: ingredient.id,
            ingredientName: ingredient.canonicalName,
            ingredientNameEnglish: ingredient.nutritionLookupName,
            estimatedGrams: selection.kind == .remove ? nil : selection.grams
        )
    }

    private static func interpretChangeEvidence(
        _ evidence: String,
        model: SystemLanguageModel
    ) async throws -> GeneratedChangeEvidenceInterpretation {
        let session = LanguageModelSession(model: model, instructions: changeEvidenceInterpretationInstructions)
        return try await session.respond(
            to: "Evidence phrase: \(evidence)",
            generating: GeneratedChangeEvidenceInterpretation.self,
            options: GenerationOptions(samplingMode: .greedy)
        ).content
    }

    private static func translatedEvidence(
        _ englishEvidence: String,
        names ingredient: RecipeIngredient
    ) -> Bool {
        let evidenceTokens = Set(
            FoodNameNormalizer.normalize(englishEvidence)
                .split(separator: " ")
                .map(String.init)
        )
        guard !evidenceTokens.isEmpty else { return false }
        return [ingredient.canonicalName, ingredient.nutritionLookupName].contains { name in
            FoodNameNormalizer.normalize(name)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 3 }
                .contains(where: evidenceTokens.contains)
        }
    }

    static func makeRequest(from generated: ParsedMealResponse) -> MealRequest {
        let displayName = generated.foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookupName = generated.foodNameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        return MealRequest(
            displayName: displayName,
            lookupName: lookupName,
            baseDisplayName: displayName,
            baseLookupName: lookupName,
            recipeID: nonempty(generated.recipeID).map(RecipeID.init(rawValue:)),
            languageCode: nonempty(generated.languageCode),
            localeIdentifier: nonempty(generated.localeIdentifier),
            cuisine: nonempty(generated.cuisine),
            quantity: MealQuantity(
                amount: generated.amount,
                unit: unit(from: generated.unit),
                estimatedGrams: generated.estimatedGrams > 0 ? generated.estimatedGrams : nil
            ),
            quantityScope: .finalMeal,
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

    static func makeRequest(
        quantity: ParsedMealResponse,
        existingModifications: [MealModification] = [],
        modifications generatedModifications: ParsedKnownRecipeModificationsResponse,
        resolvedAdditions: [MealModification]? = nil,
        trustedRecipe: Recipe,
        sourceDescriptions: [String] = [],
        explicitMassesGrams: [Int] = []
    ) -> MealRequest {
        let parsedQuantity = MealQuantity(
            amount: quantity.amount,
            unit: unit(from: quantity.unit),
            estimatedGrams: quantity.estimatedGrams > 0 ? quantity.estimatedGrams : nil
        )
        let parsedGrams = grams(from: parsedQuantity)
        var resolvedQuantity: MealQuantity
        if (quantity.hasExplicitTotalMass || generatedModifications.hasExplicitWholeMealGrams),
           let parsedGrams {
            resolvedQuantity = .grams(parsedGrams)
        } else {
            resolvedQuantity = parsedQuantity
        }

        var modifications = existingModifications
        let additions = resolvedAdditions ?? generatedModifications.addedNewIngredients.compactMap {
            validatedAddedIngredient(
                from: $0,
                trustedRecipe: trustedRecipe,
                sourceDescriptions: sourceDescriptions
            )
        }
        for addition in additions {
            let normalized = FoodNameNormalizer.normalize(addition.ingredientNameEnglish)
            if let index = modifications.firstIndex(where: {
                if let additionID = addition.ingredientID,
                   let existingID = $0.ingredientID {
                    return additionID == existingID
                }
                return FoodNameNormalizer.normalize($0.ingredientNameEnglish) == normalized
            }) {
                if modifications[index].estimatedGrams == nil, addition.estimatedGrams != nil {
                    modifications[index] = addition
                }
            } else {
                modifications.append(addition)
            }
        }
        let statedMasses = explicitMassesGrams.filter { $0 > 0 }
        if statedMasses.count == 1, let mass = statedMasses.first {
            resolvedQuantity = .grams(mass)
        } else if statedMasses.count > 1 {
            var remainingMasses = statedMasses
            for explicit in modifications.compactMap(\.estimatedGrams) {
                if let index = remainingMasses.firstIndex(of: explicit) {
                    remainingMasses.remove(at: index)
                }
            }
            if remainingMasses.count == 1, let mealMass = remainingMasses.first {
                resolvedQuantity = .grams(mealMass)
            }
        }
        let statedGrams = grams(from: resolvedQuantity)
        let hasDistinctExplicitAddition = modifications.contains { modification in
            guard modification.kind == .add || modification.kind == .increase,
                  let explicit = modification.estimatedGrams,
                  explicit > 0 else { return false }
            return explicit != statedGrams
        }
        let quantityScope: MealQuantityScope = generatedModifications.quantityExcludesModifierMass
            && hasDistinctExplicitAddition ? .baseRecipe : .finalMeal
        if quantityScope == .finalMeal, let statedGrams {
            modifications = modifications.map { modification in
                guard let explicit = modification.estimatedGrams, explicit >= statedGrams else {
                    return modification
                }
                return MealModification(
                    kind: modification.kind,
                    ingredientID: modification.ingredientID,
                    ingredientName: modification.ingredientName,
                    ingredientNameEnglish: modification.ingredientNameEnglish,
                    estimatedGrams: nil
                )
            }
        }
        var request = MealRequest(
            displayName: quantity.foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            lookupName: quantity.foodNameEnglish.trimmingCharacters(in: .whitespacesAndNewlines),
            baseDisplayName: trustedRecipe.canonicalName,
            baseLookupName: trustedRecipe.canonicalName,
            recipeID: trustedRecipe.id,
            languageCode: nil,
            localeIdentifier: nil,
            cuisine: trustedRecipe.cuisine,
            quantity: resolvedQuantity,
            quantityScope: quantityScope,
            modifications: modifications,
            isCompositeDish: true,
            proposedIngredients: [],
            modelCaloriesPer100g: nil
        )
        request.canonicalRequest = CanonicalMealRequest(
            recipeID: trustedRecipe.id,
            quantity: resolvedQuantity,
            modifications: modifications
        )
        return request
    }

    static func resolveNewIngredientAdditions(
        _ generatedAdditions: [GeneratedNewIngredientAddition],
        trustedRecipe: Recipe,
        recipeDatabase: any RecipeDatabase,
        languageCode: String?,
        localeIdentifier: String?,
        sourceDescriptions: [String]
    ) async throws -> [MealModification] {
        guard let ingredientDatabase = recipeDatabase as? any IngredientDatabase else {
            return generatedAdditions.compactMap {
                validatedAddedIngredient(
                    from: $0,
                    trustedRecipe: trustedRecipe,
                    sourceDescriptions: sourceDescriptions
                )
            }
        }

        var resolved: [MealModification] = []
        for generated in generatedAdditions {
            guard evidenceIsGrounded(generated.evidenceText, in: sourceDescriptions) else { continue }
            let names = [generated.ingredientName, generated.ingredientNameEnglish]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var identity: IngredientIdentity?
            for name in names where identity == nil {
                identity = try await ingredientDatabase.ingredient(
                    matching: IngredientQuery(
                        name: name,
                        languageCode: languageCode,
                        localeIdentifier: localeIdentifier
                    )
                )
            }
            let explicitGrams = generated.hasExplicitGrams && generated.explicitGrams > 0
                ? generated.explicitGrams
                : nil
            if let identity {
                resolved.append(
                    canonicalAddition(
                        identity: identity,
                        explicitGrams: explicitGrams,
                        trustedRecipe: trustedRecipe
                    )
                )
            } else if let legacy = validatedAddedIngredient(
                from: generated,
                trustedRecipe: trustedRecipe,
                sourceDescriptions: sourceDescriptions
            ) {
                resolved.append(legacy)
            }
        }
        return resolved
    }

    static func canonicalAddition(
        identity: IngredientIdentity,
        explicitGrams: Int?,
        trustedRecipe: Recipe
    ) -> MealModification {
        MealModification(
            kind: trustedRecipe.ingredients.contains { $0.id == identity.id } ? .increase : .add,
            ingredientID: identity.id,
            ingredientName: identity.canonicalName,
            ingredientNameEnglish: identity.nutritionLookupName,
            estimatedGrams: explicitGrams
        )
    }

    private static func validatedAddedIngredient(
        from generated: GeneratedNewIngredientAddition,
        trustedRecipe: Recipe,
        sourceDescriptions: [String]
    ) -> MealModification? {
        guard sourceDescriptions.isEmpty || evidenceIsGrounded(
            generated.evidenceText,
            in: sourceDescriptions
        ) else { return nil }

        let explicitGrams = generated.hasExplicitGrams && generated.explicitGrams > 0
            ? generated.explicitGrams
            : nil
        return canonicalizedAddition(
            ingredientName: generated.ingredientName,
            ingredientNameEnglish: generated.ingredientNameEnglish,
            explicitGrams: explicitGrams,
            trustedRecipe: trustedRecipe
        )
    }

    private static func canonicalizedAddition(
        ingredientName: String,
        ingredientNameEnglish: String,
        explicitGrams: Int?,
        trustedRecipe: Recipe
    ) -> MealModification {
        let modification = MealModification(
            kind: .add,
            ingredientName: ingredientName,
            ingredientNameEnglish: ingredientNameEnglish,
            estimatedGrams: explicitGrams
        )
        let names = [modification.ingredientName, modification.ingredientNameEnglish]
            .map(FoodNameNormalizer.normalize)
            .filter { !$0.isEmpty }
        guard let existingIndex = matchingBaseIngredientIndex(for: names, in: trustedRecipe) else {
            return modification
        }
        let existingIngredient = trustedRecipe.ingredients[existingIndex]
        return MealModification(
            kind: .increase,
            ingredientName: existingIngredient.canonicalName,
            ingredientNameEnglish: existingIngredient.nutritionLookupName,
            estimatedGrams: explicitGrams
        )
    }

    private static func matchingBaseIngredientIndex(
        for names: [String],
        in recipe: Recipe
    ) -> Int? {
        let candidates = names.map(FoodNameNormalizer.normalize).filter { !$0.isEmpty }
        let matches = recipe.ingredients.indices.filter { index in
            let ingredient = recipe.ingredients[index]
            let baseNames = [ingredient.canonicalName, ingredient.nutritionLookupName]
                .map(FoodNameNormalizer.normalize)
            return candidates.contains { candidate in
                let candidateTokens = Set(candidate.split(separator: " ").map(String.init))
                return baseNames.contains { baseName in
                    let baseTokens = Set(baseName.split(separator: " ").map(String.init))
                    return candidateTokens.isSubset(of: baseTokens)
                        || baseTokens.isSubset(of: candidateTokens)
                }
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func evidenceIsGrounded(_ evidence: String, in sources: [String]) -> Bool {
        let evidenceTokens = FoodNameNormalizer.normalize(evidence).split(separator: " ")
        guard evidenceTokens.contains(where: { token in
            token.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
        }) else { return false }

        let sourceTokens = Set(
            sources
                .flatMap { FoodNameNormalizer.normalize($0).split(separator: " ") }
                .map(String.init)
        )
        return evidenceTokens.allSatisfy { sourceTokens.contains(String($0)) }
    }

    private static func exactEvidenceIsGrounded(_ evidence: String, in sources: [String]) -> Bool {
        let normalizedEvidence = FoodNameNormalizer.normalize(evidence)
        guard !normalizedEvidence.isEmpty else { return false }
        let paddedEvidence = " \(normalizedEvidence) "
        return sources.contains { source in
            let paddedSource = " \(FoodNameNormalizer.normalize(source)) "
            return paddedSource.contains(paddedEvidence)
        }
    }

    private static func grams(from quantity: MealQuantity) -> Int? {
        let value: Double
        switch quantity.unit {
        case .gram: value = quantity.amount
        case .kilogram: value = quantity.amount * 1_000
        case .ounce: value = quantity.amount * 28.349_523_125
        case .pound: value = quantity.amount * 453.592_37
        case .milliliter, .liter, .serving, .bowl, .cup, .slice, .piece, .item:
            guard let estimatedGrams = quantity.estimatedGrams, estimatedGrams > 0 else { return nil }
            value = Double(estimatedGrams)
        }
        let grams = Int(value.rounded())
        return grams > 0 ? grams : nil
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
    Set hasExplicitTotalMass only when a stated mass describes the whole requested food or meal,
    not when it describes a single ingredient modifier.
    """

    private static let knownRecipeModificationInstructions = """
    A trusted local base recipe and its whole-meal quantity have already been identified. They are
    authoritative and cannot be replaced. Existing-ingredient directions are handled separately.
    Put only genuinely new ingredients in addedNewIngredients. For each new ingredient, copy into
    evidenceText the exact words from the original or faithful English description that request the
    addition. Normal base ingredients are not additions. Every change identifies one ingredient,
    never the base dish.

    Words can express a modifier before or after the base name, with a preposition, or through
    an adjectival or inflected form in any language; word order does not change the meaning.
    For a new ingredient, hasExplicitGrams is true only when a separate number directly quantifies
    that ingredient change. The protected whole-meal quantity is not an ingredient quantity. Treat
    the stated meal mass as final unless the user clearly says the modifier is additional outside
    the base quantity.
    Set hasExplicitWholeMealGrams only when a gram mass quantifies the whole base dish or final meal.
    Do not treat an ingredient-only quantity as the whole-meal mass. When multiple masses exist,
    keep their semantic roles distinct.
    Never perform calorie arithmetic.
    """

    private static let existingIngredientChangeInstructions = """
    A trusted recipe, all of its existing ingredients, and one target ingredient are supplied.
    Understand the original description in its own language; use the English rendering only as a
    secondary aid because it can omit a modifier. Decide only whether the user explicitly asks to
    increase, decrease, or completely remove the target. Merely naming the target as part of the
    dish is unchanged. In a dish whose name contains ingredients A and B, "A B with extra B" changes
    only B, not A; "A B with less B" changes only B; and "A B" changes neither. Never mark another
    ingredient as a compensating change. Requests for extra, more, plenty, less, or none can be
    expressed through adjectival or inflected forms in any language. When changed, copy the shortest
    exact contiguous phrase from the original description that expresses both the change and its
    target into evidenceText. Do not translate, invent, reorder, or copy the whole-meal weight into
    that phrase. Otherwise set hasExplicitChange false and evidenceText empty. Do not determine
    quantities or perform calorie arithmetic.
    """

    private static let changeEvidenceInterpretationInstructions = """
    Interpret only the supplied evidence phrase, without information about a recipe or expected
    target. Translate the complete phrase faithfully into English, preserving the ingredient and
    whether it requests more, less, or complete removal. Choose the matching direction. A separate
    gram amount belongs to the ingredient only when it occurs in this evidence phrase. Never infer
    other ingredients, compensating changes, or a whole-meal quantity.
    """

    private static let modifierTranslationInstructions = """
    Translate the food description faithfully into English without interpreting its recipe or
    calculating nutrition. Preserve every explicit ingredient modifier and its direction or
    intensity: additions, removals, requests for more, requests for less, and exact quantities.
    Preserve all numbers and units. Do not omit repeated ingredient wording, because it may carry
    the modifier meaning. Include every explicitly stated mass in explicitMassesGrams after
    converting it to grams; do not add estimated or inferred masses.
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
