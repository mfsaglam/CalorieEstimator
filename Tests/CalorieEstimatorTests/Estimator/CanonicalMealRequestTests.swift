import Testing
@testable import CalorieEstimator

@Suite("Multilingual Canonical Meal Request")
struct CanonicalMealRequestTests {
    private let database = LocalRecipeDatabase()

    @Test("Canonical removals survive the complete deterministic recipe path")
    func canonicalRemovalsReachFinalIngredients() async throws {
        let cases: [(recipeID: RecipeID, phrase: String, evidence: String, ingredientID: IngredientID)] = [
            (
                "it.spaghetti_carbonara.roman",
                "200 grammi di spaghetti alla carbonara senza parmigiano",
                "senza parmigiano",
                "parmesan"
            ),
            (
                "kr.bibimbap.default",
                "비빔밥 200그램, 계란 빼고",
                "계란 빼고",
                "egg"
            )
        ]

        for testCase in cases {
            let recipe = try #require(await database.recipe(id: testCase.recipeID))
            let candidateIndex = try #require(
                recipe.ingredients.firstIndex { $0.id == testCase.ingredientID }
            )
            let generated = GeneratedKnownIngredientModificationsResponse(
                modifications: [
                    GeneratedKnownIngredientModification(
                        kind: .remove,
                        ingredientCandidateNumber: candidateIndex + 1,
                        evidenceText: testCase.evidence,
                        hasExplicitGrams: false,
                        explicitGrams: 0
                    )
                ]
            )
            let mapped = FoundationModelMealParser.canonicalModifications(
                from: generated,
                in: recipe,
                originalDescription: testCase.phrase,
                explicitModifierMasses: []
            )
            let request = FoundationModelMealParser.makeRequest(
                quantity: quantityResponse(for: recipe, grams: 200),
                existingModifications: mapped,
                modifications: noNewIngredients,
                trustedRecipe: recipe,
                explicitMassesGrams: [200]
            )
            let estimate = try await MealResolver(
                nutritionTable: LocalNutritionTable(),
                recipeDatabase: database
            ).resolve(request)

            #expect(mapped.first?.ingredientID == testCase.ingredientID)
            #expect(request.canonicalRequest?.modifications == [
                .remove(ingredientID: testCase.ingredientID)
            ])
            let ingredientIDs = Set(try #require(estimate.ingredients).compactMap(\.ingredientID))
            #expect(!ingredientIDs.contains(testCase.ingredientID))
            #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 200)
        }
    }

    @Test("Trusted Paella shrimp increase survives the deterministic recipe path")
    func paellaShrimpIncrease() async throws {
        let phrase = "200 gramos de paella con extra de gambas"
        let recipe = try #require(await database.recipe(id: "es.paella.seafood"))
        let shrimpIndex = try #require(recipe.ingredients.firstIndex { $0.id == "shrimp" })
        let generated = GeneratedKnownIngredientModificationsResponse(
            modifications: [
                GeneratedKnownIngredientModification(
                    kind: .increase,
                    ingredientCandidateNumber: shrimpIndex + 1,
                    evidenceText: "con extra de gambas",
                    hasExplicitGrams: false,
                    explicitGrams: 0
                )
            ]
        )
        let mapped = FoundationModelMealParser.canonicalModifications(
            from: generated,
            in: recipe,
            originalDescription: phrase,
            explicitModifierMasses: []
        )
        let request = FoundationModelMealParser.makeRequest(
            quantity: quantityResponse(for: recipe, grams: 200),
            existingModifications: mapped,
            modifications: noNewIngredients,
            trustedRecipe: recipe,
            explicitMassesGrams: [200]
        )
        let baseline = try #require(RecipeDecomposer.estimate(
            recipe: recipe,
            grams: 200,
            displayName: recipe.canonicalName,
            nutritionTable: LocalNutritionTable()
        ))
        let increased = try await MealResolver(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: database
        ).resolve(request)
        let baselineShrimp = try #require(
            baseline.ingredients?.first { $0.ingredientID == "shrimp" }
        )
        let increasedShrimp = try #require(
            increased.ingredients?.first { $0.ingredientID == "shrimp" }
        )

        #expect(mapped.first?.ingredientID == "shrimp")
        #expect(request.canonicalRequest?.modifications == [
            .increase(ingredientID: "shrimp", grams: nil)
        ])
        #expect(baselineShrimp.grams == 30)
        #expect(increasedShrimp.grams == 45)
        #expect(increasedShrimp.grams > baselineShrimp.grams)
        #expect(increased.ingredients?.reduce(0) { $0 + $1.grams } == 200)
    }

    @Test("Trusted ingredient selections become stable IngredientID operations")
    func trustedSelections() async throws {
        let cases: [(
            recipeID: RecipeID,
            ingredientID: IngredientID,
            kind: MealModificationKind,
            expected: CanonicalMealModification
        )] = [
            (
                "it.spaghetti_carbonara.roman",
                "parmesan",
                .remove,
                .remove(ingredientID: "parmesan")
            ),
            (
                "es.paella.seafood",
                "shrimp",
                .increase,
                .increase(ingredientID: "shrimp", grams: nil)
            ),
            (
                "ru.borscht.default",
                "sour_cream",
                .remove,
                .remove(ingredientID: "sour_cream")
            ),
            (
                "kr.bibimbap.default",
                "egg",
                .remove,
                .remove(ingredientID: "egg")
            )
        ]

        for testCase in cases {
            let recipe = try #require(await database.recipe(id: testCase.recipeID))
            let index = try #require(recipe.ingredients.firstIndex { $0.id == testCase.ingredientID })
            let selection = TrustedIngredientSelection(
                kind: testCase.kind,
                candidateNumber: index + 1,
                grams: nil
            )
            let modification = try #require(
                FoundationModelMealParser.canonicalModification(from: selection, in: recipe)
            )
            let request = CanonicalMealRequest(
                recipeID: recipe.id,
                quantity: .grams(200),
                modifications: [modification]
            )

            #expect(request.recipeID == testCase.recipeID)
            #expect(request.modifications == [testCase.expected])
            #expect(modification.ingredientID == testCase.ingredientID)
        }
    }

    @Test("A trusted localized new ingredient becomes a canonical add")
    func trustedAddition() async throws {
        let ramen = try #require(await database.recipe(id: "jp.ramen.shoyu"))
        let additions = try await FoundationModelMealParser.resolveNewIngredientAdditions(
            [
                GeneratedNewIngredientAddition(
                    evidenceText: "コーン入り",
                    ingredientName: "コーン",
                    ingredientNameEnglish: "corn",
                    hasExplicitGrams: false,
                    explicitGrams: 0
                )
            ],
            trustedRecipe: ramen,
            recipeDatabase: database,
            languageCode: "ja",
            localeIdentifier: "ja-JP",
            sourceDescriptions: ["ラーメン200グラム、コーン入り"]
        )
        let modification = try #require(additions.first)
        let request = CanonicalMealRequest(
            recipeID: ramen.id,
            quantity: .grams(200),
            modifications: [modification]
        )

        #expect(request.recipeID == "jp.ramen.shoyu")
        #expect(additions.count == 1)
        #expect(request.modifications == [.add(ingredientID: "corn", grams: nil)])
        #expect(modification.ingredientID == "corn")
    }

    @Test("Deterministic modification identity uses IngredientID instead of names")
    func decomposerUsesIngredientID() async throws {
        let bibimbap = try #require(await database.recipe(id: "kr.bibimbap.default"))
        let misleadingNames = MealModification(
            kind: .remove,
            ingredientID: "egg",
            ingredientName: "Rice",
            ingredientNameEnglish: "rice",
            estimatedGrams: nil
        )
        let estimate = try #require(RecipeDecomposer.estimate(
            recipe: bibimbap,
            grams: 200,
            displayName: "비빔밥",
            nutritionTable: LocalNutritionTable(),
            modifications: [misleadingNames]
        ))

        let ids = Set(try #require(estimate.ingredients).compactMap(\.ingredientID))
        #expect(!ids.contains("egg"))
        #expect(ids.contains("rice"))
    }

    @Test("Whole-meal mass cannot become an existing-ingredient modifier mass")
    func wholeMealMassDoesNotLeakIntoModifier() async throws {
        let borscht = try #require(await database.recipe(id: "ru.borscht.default"))
        let sourCreamIndex = try #require(
            borscht.ingredients.firstIndex { $0.id == "sour_cream" }
        )
        let quantity = quantityResponse(for: borscht, grams: 200)
        let allowedModifierMasses = FoundationModelMealParser.explicitModifierMasses(
            from: [200],
            quantity: quantity,
            hasExplicitWholeMealGrams: true
        )
        let generated = GeneratedKnownIngredientModificationsResponse(
            modifications: [
                GeneratedKnownIngredientModification(
                    kind: .decrease,
                    ingredientCandidateNumber: sourCreamIndex + 1,
                    evidenceText: "200 граммов борща без сметаны",
                    hasExplicitGrams: true,
                    explicitGrams: 200
                )
            ]
        )
        let modifications = FoundationModelMealParser.canonicalModifications(
            from: generated,
            in: borscht,
            originalDescription: "200 граммов борща без сметаны",
            explicitModifierMasses: allowedModifierMasses
        )

        #expect(allowedModifierMasses.isEmpty)
        #expect(modifications.first?.ingredientID == "sour_cream")
        #expect(modifications.first?.estimatedGrams == nil)
    }

    @Test("A separately grounded existing-ingredient mass is preserved")
    func groundedExistingIngredientMassIsPreserved() async throws {
        let recipe = try #require(await database.recipe(id: "global.chicken_rice.default"))
        let chickenIndex = try #require(recipe.ingredients.firstIndex { $0.id == "chicken" })
        let phrase = "200g chicken rice with 30g extra chicken"
        let quantity = quantityResponse(for: recipe, grams: 200)
        let allowedModifierMasses = FoundationModelMealParser.explicitModifierMasses(
            from: [200, 30],
            quantity: quantity,
            hasExplicitWholeMealGrams: true
        )
        let generated = GeneratedKnownIngredientModificationsResponse(
            modifications: [
                GeneratedKnownIngredientModification(
                    kind: .increase,
                    ingredientCandidateNumber: chickenIndex + 1,
                    evidenceText: "30g extra chicken",
                    hasExplicitGrams: true,
                    explicitGrams: 30
                )
            ]
        )
        let modifications = FoundationModelMealParser.canonicalModifications(
            from: generated,
            in: recipe,
            originalDescription: phrase,
            explicitModifierMasses: allowedModifierMasses
        )

        #expect(allowedModifierMasses == [30])
        #expect(modifications.first?.ingredientID == "chicken")
        #expect(modifications.first?.estimatedGrams == 30)
    }

    @Test("Canonical operations remain distinct")
    func canonicalOperationsRemainDistinct() {
        let request = CanonicalMealRequest(
            recipeID: "test.recipe",
            quantity: .grams(200),
            modifications: [
                modification(.remove, id: "remove"),
                modification(.decrease, id: "decrease", grams: 10),
                modification(.increase, id: "increase", grams: 20),
                modification(.add, id: "add", grams: 30)
            ]
        )

        #expect(request.modifications == [
            .remove(ingredientID: "remove"),
            .decrease(ingredientID: "decrease", grams: 10),
            .increase(ingredientID: "increase", grams: 20),
            .add(ingredientID: "add", grams: 30)
        ])
    }

    @Test("Explicit modifier mass remains separate from final meal mass")
    func explicitModifierMassIsPreserved() async throws {
        let recipe = try #require(await database.recipe(id: "global.chicken_rice.default"))
        let request = FoundationModelMealParser.makeRequest(
            quantity: quantityResponse(for: recipe, grams: 200),
            modifications: noNewIngredients,
            resolvedAdditions: [
                MealModification(
                    kind: .add,
                    ingredientID: "mushroom",
                    ingredientName: "Mushroom",
                    ingredientNameEnglish: "mushroom",
                    estimatedGrams: 30
                )
            ],
            trustedRecipe: recipe,
            explicitMassesGrams: [200, 30]
        )
        let estimate = try await MealResolver(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: database
        ).resolve(request)
        let mushroom = try #require(
            estimate.ingredients?.first { $0.ingredientID == "mushroom" }
        )

        #expect(request.quantity == .grams(200))
        #expect(request.quantityScope == .finalMeal)
        #expect(request.canonicalRequest?.modifications == [
            .add(ingredientID: "mushroom", grams: 30)
        ])
        #expect(mushroom.grams == 30)
        #expect(estimate.ingredients?.reduce(0) { $0 + $1.grams } == 200)
    }

    private var noNewIngredients: ParsedKnownRecipeModificationsResponse {
        ParsedKnownRecipeModificationsResponse(
            hasExplicitWholeMealGrams: true,
            quantityExcludesModifierMass: false,
            addedNewIngredients: []
        )
    }

    private func quantityResponse(for recipe: Recipe, grams: Int) -> ParsedMealResponse {
        ParsedMealResponse(
            foodName: recipe.canonicalName,
            foodNameEnglish: recipe.canonicalName,
            recipeID: recipe.id.rawValue,
            languageCode: "",
            localeIdentifier: "",
            cuisine: recipe.cuisine ?? "",
            amount: Double(grams),
            unit: .gram,
            estimatedGrams: 0,
            hasExplicitTotalMass: true,
            modifications: [],
            isCompositeDish: true,
            proposedIngredients: [],
            fallbackCaloriesPer100g: 1
        )
    }

    private func modification(
        _ kind: MealModificationKind,
        id: IngredientID,
        grams: Int? = nil
    ) -> MealModification {
        MealModification(
            kind: kind,
            ingredientID: id,
            ingredientName: id.rawValue,
            ingredientNameEnglish: id.rawValue,
            estimatedGrams: grams
        )
    }
}
