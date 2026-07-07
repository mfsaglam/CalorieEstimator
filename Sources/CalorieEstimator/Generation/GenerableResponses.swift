import FoundationModels

// MARK: - Generable Response Types
//
// The structured shapes the on-device model generates. Internal — callers only ever
// see the public ``MealEstimate``. Each schema that drives routing carries an
// `isCompositeDish` flag, so deciding whether to decompose costs no extra inference.

/// Model response for the natural-language phrase path (Siri intent).
///
/// One guided generation yields the food name (input language), its English name for
/// lookup, an approximate mass in grams for the stated amount, a per-100g figure, and
/// whether the item is a composite dish that should be decomposed instead.
@Generable
struct PhraseNutritionResponse {
    @Guide(description: "The food only, normalised, with NO quantity, number, or unit, in the SAME language as the description. E.g. \"grilled chicken\", \"somon\", \"weißer Reis\".")
    var foodName: String
    @Guide(description: "The food's common English name in lowercase, with NO quantity, for database lookup. Translate if the description is in another language. E.g. \"yumurta\" → \"eggs\", \"somon\" → \"salmon\", \"beyaz pilav\" → \"white rice\".")
    var foodNameEnglish: String = ""
    @Guide(description: "Approximate mass in grams for the stated amount. Convert using typical food densities and serving sizes. Anchors: 1 kg = 1000 g; 1 oz ≈ 28 g; 1 lb ≈ 454 g; watery foods and drinks are about 1 g per ml, so 250 ml ≈ 250 g and 1 litre ≈ 1000 g; 1 cup ≈ 240 g; 1 tbsp ≈ 15 g; 1 tsp ≈ 5 g. For counts, use one typical item (e.g. 1 egg ≈ 50 g, a handful ≈ 30 g). If no amount is stated, assume a single typical serving. This value is grams only — do not multiply by calories.", .range(1...3000))
    var grams: Int
    @Guide(description: "Typical calories (kcal) per 100 grams of this food — a stable nutritional fact independent of the amount. E.g. eggs ≈ 155, white rice (cooked) ≈ 130, grilled chicken ≈ 165, almonds ≈ 580. Do NOT multiply by the amount; report the per-100-gram value only.", .range(1...900))
    var caloriesPer100g: Int
    @Guide(description: "true ONLY when this is a composite, prepared dish of several ingredients (e.g. lasagna, stew, casserole, \"kremalı mantarlı makarna\") where a single per-100g value would be unreliable. false for a single, simple food (chicken, rice, an apple).")
    var isCompositeDish: Bool = false
}

/// Model response for the text-field path when the food isn't in the nutrition table.
///
/// The weight is supplied by the caller and converted to grams in code — the model is
/// asked only for the per-100g figure (and whether to decompose instead), never to
/// parse units.
@Generable
struct FoodLookupResponse {
    @Guide(description: "The food's common English name in lowercase, for database lookup. Translate if the input is in another language. E.g. \"yumurta\" → \"eggs\", \"pollo\" → \"chicken\", \"Reis\" → \"rice\".")
    var foodNameEnglish: String = ""
    @Guide(description: "Approximate calories per 100 grams of this food. Report the per-100-gram value only; do not consider any quantity.", .range(1...900))
    var caloriesPer100g: Int
    @Guide(description: "true ONLY when this is a composite, prepared dish of several ingredients (e.g. lasagna, stew, casserole) where a single per-100g value would be unreliable. false for a single, simple food.")
    var isCompositeDish: Bool = false
}

/// One ingredient the model identifies while decomposing a dish.
@Generable
struct RecipeIngredientResponse {
    @Guide(description: "The ingredient name, in the SAME language as the dish. E.g. \"krema\", \"mantar\", \"makarna\".")
    var name: String
    @Guide(description: "The ingredient's common English name in lowercase, for database lookup. Translate if needed. E.g. \"krema\" → \"cream\", \"mantar\" → \"mushroom\", \"makarna\" → \"pasta\".")
    var nameEnglish: String = ""
    @Guide(description: "Approximate mass in grams of this ingredient in ONE typical serving of the dish.", .range(1...2000))
    var grams: Int
    @Guide(description: "Typical calories (kcal) per 100 grams of this ingredient — used only if it isn't in the database.", .range(1...900))
    var caloriesPer100g: Int
}

/// Model response for dish decomposition.
///
/// The model returns two independent things: the ingredient breakdown (which we sum
/// ourselves through the nutrition table) and a holistic total-calorie guess made
/// without summing — the two are cross-checked to gauge confidence.
@Generable
struct RecipeResponse {
    @Guide(description: "The dish name, in the SAME language as the input.")
    var dishName: String
    @Guide(description: "The main ingredients of ONE typical serving of the dish (usually 3–8), each with an approximate mass in grams. Include calorie-dense additions like oil, butter, cream, and sauces.")
    var ingredients: [RecipeIngredientResponse]
    @Guide(description: "An INDEPENDENT holistic estimate of the TOTAL calories in one serving, judged from the whole dish WITHOUT adding up the ingredients above.", .range(1...5000))
    var holisticCalories: Int
}
