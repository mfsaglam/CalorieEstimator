import Testing
@testable import CalorieEstimator

@Suite("Modified Known Recipe Resolution")
struct ModifiedRecipeResolutionTests {
    private struct Case {
        let input: String
        let displayName: String
        let lookupName: String
        let baseDisplayName: String
        let baseLookupName: String
        let recipeID: RecipeID
        let modification: MealModification
    }

    @Test("Known base recipes remain authoritative across languages and modifier word order")
    func knownBaseRecipeWithModifiers() async throws {
        let cases = [
            Case(
                input: "200 gram mantarlı tavuklu pilav",
                displayName: "mantarlı tavuklu pilav",
                lookupName: "chicken rice with mushrooms",
                baseDisplayName: "tavuklu pilav",
                baseLookupName: "Turkish chicken rice",
                recipeID: "tr.tavuklu_pilav.default",
                modification: Self.addition("mantar", english: "mushroom")
            ),
            Case(
                input: "200 gram tavuklu pilav mantarlı",
                displayName: "tavuklu pilav mantarlı",
                lookupName: "chicken rice with mushrooms",
                baseDisplayName: "tavuklu pilav",
                baseLookupName: "Turkish chicken rice",
                recipeID: "tr.tavuklu_pilav.default",
                modification: Self.addition("mantar", english: "mushroom")
            ),
            Case(
                input: "200g mushroom chicken rice",
                displayName: "mushroom chicken rice",
                lookupName: "mushroom chicken rice",
                baseDisplayName: "chicken rice",
                baseLookupName: "chicken rice",
                recipeID: "global.chicken_rice.default",
                modification: Self.addition("mushroom", english: "mushroom")
            ),
            Case(
                input: "200g chicken rice with mushrooms",
                displayName: "chicken rice with mushrooms",
                lookupName: "chicken rice with mushrooms",
                baseDisplayName: "chicken rice",
                baseLookupName: "chicken rice",
                recipeID: "global.chicken_rice.default",
                modification: Self.addition("mushroom", english: "mushroom")
            ),
            Case(
                input: "200g carbonara with mushrooms",
                displayName: "carbonara with mushrooms",
                lookupName: "carbonara with mushrooms",
                baseDisplayName: "carbonara",
                baseLookupName: "carbonara",
                recipeID: "it.spaghetti_carbonara.roman",
                modification: Self.addition("mushroom", english: "mushroom")
            ),
            Case(
                input: "200g mushroom carbonara",
                displayName: "mushroom carbonara",
                lookupName: "mushroom carbonara",
                baseDisplayName: "carbonara",
                baseLookupName: "carbonara",
                recipeID: "it.spaghetti_carbonara.roman",
                modification: Self.addition("mushroom", english: "mushroom")
            ),
            Case(
                input: "200g ramen with extra egg",
                displayName: "ramen with extra egg",
                lookupName: "ramen with extra egg",
                baseDisplayName: "shoyu ramen",
                baseLookupName: "shoyu ramen",
                recipeID: "jp.ramen.shoyu",
                modification: Self.increase("egg")
            ),
            Case(
                input: "200g cheeseburger without cheese",
                displayName: "cheeseburger without cheese",
                lookupName: "cheeseburger without cheese",
                baseDisplayName: "cheeseburger",
                baseLookupName: "cheeseburger",
                recipeID: "us.cheeseburger.default",
                modification: Self.removal("cheese")
            )
        ]

        let database = LocalRecipeDatabase()
        for testCase in cases {
            let request = MealRequest(
                displayName: testCase.displayName,
                lookupName: testCase.lookupName,
                baseDisplayName: testCase.baseDisplayName,
                baseLookupName: testCase.baseLookupName,
                recipeID: testCase.recipeID,
                languageCode: nil,
                localeIdentifier: nil,
                cuisine: nil,
                quantity: .grams(200),
                quantityScope: .finalMeal,
                modifications: [testCase.modification],
                isCompositeDish: true,
                proposedIngredients: [
                    ModelIngredientProposal(name: "unrelated", nameEnglish: "banana", ratio: 1)
                ],
                modelCaloriesPer100g: 899
            )
            let estimator = CalorieEstimator(
                nutritionTable: LocalNutritionTable(),
                recipeDatabase: database,
                mealParser: StubMealRequestParser(request: request)
            )

            let estimate = try await estimator.estimate(phrase: testCase.input)
            let ingredients = try #require(estimate.ingredients)
            let names: Set<String> = Set(ingredients.map { FoodNameNormalizer.normalize($0.name) })
            let baseRecipe = try #require(await database.recipe(id: testCase.recipeID))
            var allowedNames: Set<String> = Set(baseRecipe.ingredients.map { FoodNameNormalizer.normalize($0.canonicalName) })

            if testCase.modification.kind == MealModificationKind.add {
                allowedNames.insert(FoodNameNormalizer.normalize(testCase.modification.ingredientName))
                #expect(names.contains(FoodNameNormalizer.normalize(testCase.modification.ingredientName)), Comment(rawValue: testCase.input))
            }
            if testCase.modification.kind == MealModificationKind.remove {
                #expect(!names.contains(FoodNameNormalizer.normalize(testCase.modification.ingredientName)), Comment(rawValue: testCase.input))
            }
            if testCase.modification.kind == MealModificationKind.increase {
                let modified = try #require(ingredients.first {
                    FoodNameNormalizer.normalize($0.name) == FoodNameNormalizer.normalize(testCase.modification.ingredientName)
                })
                let unmodified = try #require(RecipeDecomposer.estimate(
                    recipe: baseRecipe,
                    grams: 200,
                    displayName: testCase.baseDisplayName,
                    nutritionTable: LocalNutritionTable()
                )?.ingredients?.first {
                    FoodNameNormalizer.normalize($0.name) == FoodNameNormalizer.normalize(testCase.modification.ingredientName)
                })
                #expect(modified.grams > unmodified.grams, Comment(rawValue: testCase.input))
            }

            #expect(estimate.recipeID == testCase.recipeID, Comment(rawValue: testCase.input))
            #expect(estimate.provenance == EstimateProvenance.localRecipe, Comment(rawValue: testCase.input))
            #expect(estimate.grams == 200, Comment(rawValue: testCase.input))
            #expect(ingredients.reduce(0) { $0 + $1.grams } == 200, Comment(rawValue: testCase.input))
            let unexpected = names.subtracting(allowedNames).sorted().joined(separator: ", ")
            #expect(names.isSubset(of: allowedNames), "Unexpected ingredient for \(testCase.input): \(unexpected)")
        }
    }

    @Test("General generated response preserves full meal and modifier semantics")
    func generatedResponseMapping() {
        let generated = ParsedMealResponse(
            foodName: "mantarlı tavuklu pilav",
            foodNameEnglish: "Turkish chicken rice with mushrooms",
            recipeID: "tr.tavuklu_pilav.default",
            languageCode: "tr",
            localeIdentifier: "tr-TR",
            cuisine: "Turkish",
            amount: 200,
            unit: .gram,
            estimatedGrams: 0,
            hasExplicitTotalMass: true,
            modifications: [
                GeneratedMealModification(
                    kind: .add,
                    ingredientName: "mantar",
                    ingredientNameEnglish: "mushroom",
                    estimatedGrams: 0
                )
            ],
            isCompositeDish: true,
            proposedIngredients: [],
            fallbackCaloriesPer100g: 200
        )

        let request = FoundationModelMealParser.makeRequest(from: generated)

        #expect(request.displayName == "mantarlı tavuklu pilav")
        #expect(request.baseDisplayName == request.displayName)
        #expect(request.baseLookupName == request.lookupName)
        #expect(request.recipeID == "tr.tavuklu_pilav.default")
        #expect(request.quantity.amount == 200)
        #expect(request.quantity.unit == .gram)
        #expect(request.quantity.estimatedGrams == nil)
        #expect(request.modifications == [Self.addition("mantar", english: "mushroom")])
    }

    @Test("Known-recipe parser boundary canonicalizes restated base ingredients")
    func knownRecipeModificationValidation() async throws {
        let recipe = try #require(await LocalRecipeDatabase().recipe(id: "tr.tavuklu_pilav.default"))
        let quantity = ParsedMealResponse(
            foodName: "mantarlı tavuklu pilav",
            foodNameEnglish: "Turkish chicken rice with mushroom",
            recipeID: "",
            languageCode: "tr",
            localeIdentifier: "tr-TR",
            cuisine: "Turkish",
            amount: 200,
            unit: .gram,
            estimatedGrams: 0,
            hasExplicitTotalMass: true,
            modifications: [],
            isCompositeDish: true,
            proposedIngredients: [],
            fallbackCaloriesPer100g: 200
        )
        let generatedModifications = ParsedKnownRecipeModificationsResponse(
            hasExplicitWholeMealGrams: true,
            quantityExcludesModifierMass: false,
            addedNewIngredients: [
                GeneratedNewIngredientAddition(
                    evidenceText: "mantarlı",
                    ingredientName: "mantar",
                    ingredientNameEnglish: "mushroom",
                    hasExplicitGrams: false,
                    explicitGrams: 0
                ),
                GeneratedNewIngredientAddition(
                    evidenceText: "extra chicken",
                    ingredientName: "chicken",
                    ingredientNameEnglish: "chicken",
                    hasExplicitGrams: false,
                    explicitGrams: 0
                )
            ]
        )
        let request = FoundationModelMealParser.makeRequest(
            quantity: quantity,
            existingModifications: [Self.increase("Chicken", english: "chicken")],
            modifications: generatedModifications,
            trustedRecipe: recipe,
            sourceDescriptions: ["mantarlı tavuklu pilav extra chicken 200g"]
        )

        #expect(request.modifications == [
            Self.increase("Chicken", english: "chicken"),
            Self.addition("mantar", english: "mushroom")
        ])
    }

    @Test("Explicit whole-meal mass cannot be duplicated as additive modifier mass")
    func wholeMealMassIsNotDoubleCounted() async throws {
        let recipe = try #require(await LocalRecipeDatabase().recipe(id: "it.spaghetti_carbonara.roman"))
        let quantity = ParsedMealResponse(
            foodName: "spaghetti carbonara",
            foodNameEnglish: "spaghetti carbonara",
            recipeID: "",
            languageCode: "en",
            localeIdentifier: "",
            cuisine: "Italian",
            amount: 1,
            unit: .serving,
            estimatedGrams: 150,
            hasExplicitTotalMass: true,
            modifications: [],
            isCompositeDish: true,
            proposedIngredients: [],
            fallbackCaloriesPer100g: 1
        )
        let details = ParsedKnownRecipeModificationsResponse(
            hasExplicitWholeMealGrams: false,
            quantityExcludesModifierMass: true,
            addedNewIngredients: []
        )

        let request = FoundationModelMealParser.makeRequest(
            quantity: quantity,
            existingModifications: [
                MealModification(
                    kind: .increase,
                    ingredientID: "bacon",
                    ingredientName: "Pancetta or bacon",
                    ingredientNameEnglish: "bacon",
                    estimatedGrams: 150
                )
            ],
            modifications: details,
            trustedRecipe: recipe,
            sourceDescriptions: ["spaghetti carbonara with 150g extra pancetta"]
        )

        #expect(request.quantity == .grams(150))
        #expect(request.quantityScope == .finalMeal)
        #expect(request.modifications == [
            MealModification(
                kind: .increase,
                ingredientID: "bacon",
                ingredientName: "Pancetta or bacon",
                ingredientNameEnglish: "bacon",
                estimatedGrams: nil
            )
        ])
        #expect(request.canonicalRequest?.modifications == [
            .increase(ingredientID: "bacon", grams: nil)
        ])
    }

    @Test("Unmodified Turkish chicken rice baseline remains byte-for-byte stable")
    func baselineUnchanged() async throws {
        let request = MealRequest(
            displayName: "tavuklu pilav",
            lookupName: "Turkish chicken rice",
            baseDisplayName: "tavuklu pilav",
            baseLookupName: "Turkish chicken rice",
            recipeID: "tr.tavuklu_pilav.default",
            languageCode: "tr",
            localeIdentifier: "tr-TR",
            cuisine: "Turkish",
            quantity: .grams(200),
            quantityScope: .finalMeal,
            modifications: [],
            isCompositeDish: true,
            proposedIngredients: [],
            modelCaloriesPer100g: 899
        )
        let estimator = CalorieEstimator(
            nutritionTable: LocalNutritionTable(),
            recipeDatabase: LocalRecipeDatabase(),
            mealParser: StubMealRequestParser(request: request)
        )

        let estimate = try await estimator.estimate(phrase: "200 gram tavuklu pilav")
        let ingredients = try #require(estimate.ingredients)
        let rows = ingredients.map {
            (FoodNameNormalizer.normalize($0.name), $0.grams, $0.calories)
        }

        #expect(estimate.grams == 200)
        #expect(estimate.calories == 381)
        #expect(rows.count == 4)
        #expect(rows[0].0 == "rice" && rows[0].1 == 114 && rows[0].2 == 148)
        #expect(rows[1].0 == "chicken" && rows[1].1 == 74 && rows[1].2 == 141)
        #expect(rows[2].0 == "butter" && rows[2].1 == 8 && rows[2].2 == 57)
        #expect(rows[3].0 == "olive oil" && rows[3].1 == 4 && rows[3].2 == 35)
    }

    private static func addition(_ name: String, english: String) -> MealModification {
        MealModification(kind: .add, ingredientName: name, ingredientNameEnglish: english, estimatedGrams: nil)
    }

    private static func increase(_ name: String, english: String? = nil) -> MealModification {
        MealModification(
            kind: .increase,
            ingredientName: name,
            ingredientNameEnglish: english ?? name,
            estimatedGrams: nil
        )
    }

    private static func removal(_ name: String) -> MealModification {
        MealModification(kind: .remove, ingredientName: name, ingredientNameEnglish: name, estimatedGrams: nil)
    }
}
