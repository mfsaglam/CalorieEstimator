import FoundationModels

// MARK: - Generable Response Types
//
// The structured shapes the on-device model generates. They are internal — callers
// only ever see the public estimate types (``CalorieEstimation``, ``MealEstimate``,
// ``DishEstimate``).

/// Model response for grams-based estimation.
@Generable
struct NutritionResponse {
    @Guide(description: "Approximate calories per 100 grams of this food")
    var caloriesPer100g: Int
    @Guide(description: "The name of the food item, in the same language as the input")
    var foodName: String
    @Guide(description: "The food's common English name in lowercase, for database lookup. Translate if the input is in another language. E.g. \"yumurta\" → \"eggs\", \"pollo\" → \"chicken\", \"Reis\" → \"rice\".")
    var foodNameEnglish: String = ""
}

/// Model response for amount-based estimation.
@Generable
struct AmountNutritionResponse {
    @Guide(description: "Approximate calories per 100 grams of this food")
    var caloriesPer100g: Int
    @Guide(description: "Estimated total weight in grams for the given amount")
    var estimatedGrams: Int
    @Guide(description: "The name of the food item, in the same language as the input")
    var foodName: String
    @Guide(description: "The food's common English name in lowercase, for database lookup. Translate if the input is in another language. E.g. \"yumurta\" → \"eggs\", \"pollo\" → \"chicken\", \"Reis\" → \"rice\".")
    var foodNameEnglish: String = ""
}

/// Model response for phrase-based estimation.
///
/// A single guided generation produces the cleaned food name, an approximate
/// mass in grams, and the calories for that mass — so the whole phrase is parsed
/// and estimated in one inference call.
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
/// The model returns two independent things: the ingredient breakdown (which we
/// sum ourselves through the nutrition table) and a holistic total-calorie guess
/// made without summing — the two are cross-checked to gauge confidence.
@Generable
struct RecipeResponse {
    @Guide(description: "The dish name, in the SAME language as the input.")
    var dishName: String
    @Guide(description: "The main ingredients of ONE typical serving of the dish (usually 3–8), each with an approximate mass in grams. Include calorie-dense additions like oil, butter, cream, and sauces.")
    var ingredients: [RecipeIngredientResponse]
    @Guide(description: "An INDEPENDENT holistic estimate of the TOTAL calories in one serving, judged from the whole dish WITHOUT adding up the ingredients above.", .range(1...5000))
    var holisticCalories: Int
}
