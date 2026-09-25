# CalorieEstimator

CalorieEstimator is a cuisine-agnostic Swift package for estimating meal calories with
on-device Apple Intelligence and trusted local data. It is offline, privacy-friendly,
and designed for food names, dishes, and languages from around the world.

The Foundation Model understands language. A local recipe database supplies known dish
composition, a nutrition table supplies energy density, and Swift performs every weight
and calorie calculation.

## Requirements

- iOS 26+, macOS 26+, or visionOS 26+
- Swift 6.2+
- Apple Intelligence enabled for inputs that local data cannot resolve directly

FoundationModels' on-device `SystemLanguageModel` is unavailable on tvOS and watchOS,
so those platforms are not declared by this package.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/mfsaglam/CalorieEstimator.git", from: "2.0.0")
]
```

Add `CalorieEstimator` to the consuming target's dependencies.

## Usage

### Natural-language input

```swift
import CalorieEstimator

let estimator = CalorieEstimator()
let result = try await estimator.estimate(phrase: "200 gram tavuklu pilav")

print(result.foodName)
print(result.grams)       // 200
print(result.calories)
print(result.provenance)  // .localRecipe when the bundled recipe matched
```

The structured parser supports mass, volume, serving, bowl, cup, slice, piece, and item
semantics. Explicit mass units are converted in Swift. A known recipe's default serving
weight is preferred for serving-like quantities; ambiguous long-tail portions can use an
on-device model estimate.

### Food name plus explicit weight

```swift
let salmon = try await estimator.estimate(
    meal: "salmon",
    weight: Measurement(value: 8, unit: .ounces)
)

let carbonara = try await estimator.estimate(meal: "spaghetti carbonara", grams: 150)
```

This path checks the local recipe database first, then the nutrition table. A confident
local hit never creates a model session.

## Architecture

```text
User input
   |
   v
Typed FoundationModels semantic parser
   |  name, language/locale hints, quantity, explicit modifiers
   v
Canonical recipe resolver  <---->  local SQLite RecipeDatabase tool
   |
   +-- known recipe --------> deterministic ratio scaling
   |                              |
   +-- known food ---------------+--> local NutritionTable
   |                              |
   +-- unknown composite ----> model ratios, locally resolved ingredients
   |                              |
   +-- unresolved food ------> lowest-trust model kcal/100 g
                                  |
                                  v
                         Swift arithmetic --> MealEstimate
```

The model can propose meaning, a recipe identity, an unknown-dish composition, or a final
nutrition fallback. Swift validates every model-proposed recipe ID. Local recipe and
nutrition values always win and cannot be overwritten by model output.

## Trust hierarchy

`MealEstimate.provenance` describes the result's trust boundary:

1. `.localRecipe` — trusted composition plus local nutrition, `high` confidence.
2. `.localNutrition` — a direct local food match, `high` confidence.
3. `.modelAssistedRecipe` — model-proposed composition for an unknown dish, with every
   ingredient resolved by local nutrition, `medium` confidence.
4. `.modelNutrition` — whole-food kcal/100 g from the model after all local paths fail,
   `low` confidence.

The original `MealEstimate.Source` cases (`database`, `model`, and `decomposed`) remain
available for source compatibility. `provenance` is the more precise signal.

## Canonical identity and multilingual matching

Recipe IDs are stable and independent of display language, for example:

```text
tr.tavuklu_pilav.default
it.spaghetti_carbonara.roman
jp.ramen.shoyu
```

Aliases carry optional language and locale metadata. Generic terms do not need to map to
a single regional recipe: `global.chicken_rice.default` and
`tr.tavuklu_pilav.default`, for example, remain separate identities. Cuisine and region
are metadata, never hard-coded branches in domain logic.

The model's supported languages depend on the OS and installed Apple Intelligence model.
The architecture is multilingual, but this package does not claim that every language or
regional term is supported equally well by every system release.

## Recipe database

`RecipeDatabase` is public and injectable:

```swift
let estimator = CalorieEstimator(
    nutritionTable: MyNutritionTable(),
    recipeDatabase: MyRecipeDatabase()
)
```

The bundled `LocalRecipeDatabase` is read-only SQLite. Its schema separates recipe
identity and aliases from ingredient composition:

```text
recipes(id, canonical_name, normalized_name, cuisine, region, variant,
        default_serving_grams)
recipe_aliases(recipe_id, alias, normalized_alias, language_code, locale_identifier)
ingredients(id, canonical_name, nutrition_lookup_name)
recipe_ingredients(recipe_id, ingredient_id, position, ratio)
```

Ingredient ratios must total approximately 1.0. Swift uses a largest-remainder allocation
so ingredient masses always sum exactly to the requested meal weight.

### Adding recipes and languages

1. Add canonical ingredients, recipes, aliases, and ratios to `Data/recipes.sql`.
2. Keep IDs stable and use separate IDs for nutritionally meaningful regional variants.
3. Ensure every ingredient's `nutrition_lookup_name` resolves through the nutrition table.
4. Rebuild the resource:

   ```sh
   sh Scripts/build_recipe_database.sh
   ```

5. Add multilingual/cuisine evaluation entries to
   `Tests/CalorieEstimatorTests/Resources/MealEvaluations.json`.
6. Run `swift test`.

The seed is intentionally small and globally varied. It validates the architecture; it is
not intended to enumerate world cuisine.

## FoundationModels tool calling

The semantic parser installs a typed `RecipeDatabaseTool`. The tool returns a trusted
recipe ID and identity metadata. It does not let the model edit recipe ratios or local
nutrition. The resolver re-fetches and validates the ID before using it.

Explicit user changes such as “without cheese” or “with extra mushroom” are represented
separately from the base recipe. Only explicit modifiers may alter a known composition.

## Nutrition source

`NutritionTable` remains the lightweight public abstraction:

```swift
public protocol NutritionTable: Sendable {
    func caloriesPer100g(for foodName: String) -> Int?
}
```

`LocalNutritionTable` contains common food and ingredient values. `EmptyNutritionTable`
forces misses. Custom implementations can use a larger bundled database without changing
the estimator API.

The local matcher accepts exact names, singular/plural variants, and a small set of
preparation modifiers. It deliberately does not match arbitrary substrings, so “chicken
rice” cannot silently resolve as chicken or rice.

## Result types

```swift
public struct MealEstimate: Sendable, Equatable {
    public let foodName: String
    public let grams: Int
    public let calories: Int
    public let source: Source
    public let provenance: EstimateProvenance
    public let recipeID: RecipeID?
    public let confidence: Confidence?
    public let ingredients: [IngredientEstimate]?
}
```

Known and model-assisted composite dishes include their deterministic ingredient calorie
breakdown. `IngredientEstimate.source` describes the nutrition source for that ingredient.

## Testing

```sh
swift test
```

The default suite is deterministic and does not require Apple Intelligence. To opt into
the real on-device integration tests:

```sh
CALORIE_ESTIMATOR_RUN_MODEL_TESTS=1 swift test
```

The JSON evaluation fixtures cover several cuisines, aliases, exact total weights, and
forbidden-ingredient regressions. They are intentionally lightweight so the corpus can
grow without creating an ML evaluation framework.

## Limitations

- Recipe entries are representative defaults, not universal culinary truths. Restaurants,
  regions, households, brands, and preparation methods vary.
- The bundled seed and nutrition table are deliberately small.
- Portion units such as slices and bowls remain approximate unless a trusted recipe default
  or future portion metadata resolves them.
- Explicit modifier quantities are approximate when the user does not state an amount.
- The final model nutrition fallback preserves long-tail coverage but is intentionally
  marked low-confidence.

## License

MIT License. See [LICENSE](LICENSE).
