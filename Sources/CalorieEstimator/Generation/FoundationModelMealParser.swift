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
            let modifications = try await Self.respondForKnownRecipeModifications(
                input: input,
                englishDescription: translation.englishDescription,
                recipe: trustedCandidate,
                quantity: quantity,
                model: model
            )
            let existingModifications = try await Self.respondForKnownExistingIngredientChanges(
                input: input,
                englishDescription: translation.englishDescription,
                recipe: trustedCandidate,
                explicitModifierMasses: Self.explicitModifierMasses(
                    from: translation.explicitMassesGrams,
                    quantity: quantity,
                    hasExplicitWholeMealGrams: modifications.hasExplicitWholeMealGrams
                ),
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

        // The trusted database has already missed. This call parses only identity and
        // quantity; approximate nutrition is handled by the separate bounded sampler.
        // Avoiding a tool call also removes the old tool-runtime retry from this path.
        let generated = try await Self.respond(input: input, model: model, tools: [])
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
        explicitModifierMasses: [Int],
        model: SystemLanguageModel
    ) async throws -> [MealModification] {
        let generated = try await generateKnownIngredientModifications(
            input: input,
            englishDescription: englishDescription,
            recipe: recipe,
            model: model
        )
        return canonicalModifications(
            from: generated,
            in: recipe,
            originalDescription: input,
            explicitModifierMasses: explicitModifierMasses
        )
    }

    static func generateKnownIngredientModifications(
        input: String,
        englishDescription: String,
        recipe: Recipe,
        model: SystemLanguageModel
    ) async throws -> GeneratedKnownIngredientModificationsResponse {
        let numberedIngredients = recipe.ingredients.enumerated().map { index, ingredient in
            "\(index + 1). \(ingredient.canonicalName) [nutrition name: \(ingredient.nutritionLookupName)]"
        }.joined(separator: ", ")
        let session = LanguageModelSession(model: model, instructions: existingIngredientChangeInstructions)
        return try await session.respond(
            to: """
            Original food description: \(input)
            English rendering (which may be imperfect): \(englishDescription)
            Trusted base recipe: \(recipe.canonicalName)
            Numbered existing ingredient candidates: \(numberedIngredients)
            """,
            generating: GeneratedKnownIngredientModificationsResponse.self,
            options: GenerationOptions(samplingMode: .greedy)
        ).content
    }

    static func canonicalModifications(
        from generated: GeneratedKnownIngredientModificationsResponse,
        in recipe: Recipe,
        originalDescription: String,
        explicitModifierMasses: [Int]
    ) -> [MealModification] {
        var remainingMasses = explicitModifierMasses.filter { $0 > 0 }
        var selectedCandidates: Set<Int> = []
        var modifications: [MealModification] = []

        for generatedModification in generated.modifications {
            let candidateNumber = generatedModification.ingredientCandidateNumber
            guard recipe.ingredients.indices.contains(candidateNumber - 1),
                  selectedCandidates.insert(candidateNumber).inserted,
                  exactEvidenceIsGrounded(
                      generatedModification.evidenceText,
                      in: [originalDescription]
                  ) else {
                continue
            }

            let kind: MealModificationKind = switch generatedModification.kind {
            case .remove: .remove
            case .decrease: .decrease
            case .increase: .increase
            }
            var explicitGrams: Int?
            if kind != .remove,
               generatedModification.hasExplicitGrams,
               generatedModification.explicitGrams > 0,
               explicitIntegerValues(in: generatedModification.evidenceText)
                    .contains(generatedModification.explicitGrams),
               let massIndex = remainingMasses.firstIndex(of: generatedModification.explicitGrams) {
                explicitGrams = remainingMasses.remove(at: massIndex)
            }
            let selection = TrustedIngredientSelection(
                kind: kind,
                candidateNumber: candidateNumber,
                grams: explicitGrams
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
            isCompositeDish: false,
            proposedIngredients: [],
            modelCaloriesPer100g: nil
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

    static func explicitModifierMasses(
        from explicitMassesGrams: [Int],
        quantity: ParsedMealResponse,
        hasExplicitWholeMealGrams: Bool
    ) -> [Int] {
        var masses = explicitMassesGrams.filter { $0 > 0 }
        guard quantity.hasExplicitTotalMass || hasExplicitWholeMealGrams else { return masses }
        let parsedQuantity = MealQuantity(
            amount: quantity.amount,
            unit: unit(from: quantity.unit),
            estimatedGrams: quantity.estimatedGrams > 0 ? quantity.estimatedGrams : nil
        )
        guard let mealGrams = grams(from: parsedQuantity),
              let mealMassIndex = masses.firstIndex(of: mealGrams) else {
            return masses
        }
        masses.remove(at: mealMassIndex)
        return masses
    }

    private static func explicitIntegerValues(in text: String) -> [Int] {
        var values: [Int] = []
        var current: Int?
        for character in text {
            if let digit = character.wholeNumberValue {
                current = (current ?? 0) * 10 + digit
            } else if let value = current {
                values.append(value)
                current = nil
            }
        }
        if let current { values.append(current) }
        return values
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
    Parse food descriptions in the user's language into typed semantic data. Never estimate
    nutrition, generate an ingredient list, or perform calorie arithmetic. Never add, remove,
    or change ingredients of a known recipe unless the user explicitly requested a modifier.
    Preserve meaningful cuisine and regional distinctions instead of translating distinct
    dishes into a generic dish. Return the stated unit rather than converting mass units.
    For ambiguous portions, provide a reasonable estimated total gram weight.
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
    A trusted recipe and a numbered bounded list of its existing ingredients are supplied.
    Understand the original description in its own language; use the English rendering only as a
    secondary aid because it can omit a modifier. Return only changes explicitly requested by the
    user, selecting each target by its one-based candidate number. Merely naming an ingredient as
    part of the dish is unchanged. Never mark another ingredient as a compensating change.

    Classify each operation from the selected ingredient's requested final state:
    INCREASE means it remains present with an additional or larger amount.
    DECREASE means it remains present with a smaller amount.
    REMOVE means it must be completely absent from the final dish. Use REMOVE only for requested
    absence, never when the user requests an additional amount of an existing ingredient.

    Copy the shortest exact contiguous phrase from the original description that expresses both
    the change and its target into evidenceText. Do not translate, invent, or reorder that evidence.
    The whole-meal quantity is protected and is never an ingredient quantity. Set hasExplicitGrams
    only when a separate gram amount occurs inside evidenceText and directly quantifies that selected
    ingredient change. Otherwise use false and zero. Do not perform calorie arithmetic.
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
