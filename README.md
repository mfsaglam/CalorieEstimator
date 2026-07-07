# CalorieEstimator

A lightweight Swift package that estimates calories for a meal using on-device Apple Intelligence via the [FoundationModels](https://developer.apple.com/documentation/foundationmodels) framework.

All processing happens on-device. No network requests, no API keys, no third-party services.

Calorie figures for common foods come from a **bundled nutrition table** rather than the model's memory, so they're accurate and reproducible — and for the text-field path, a table hit returns **without ever calling the model** (instant, offline). When a food isn't in the table, the model supplies a figure instead. Composite dishes ("lasagna", "kremalı mantarlı makarna") are detected and **broken into ingredients automatically**. Non-English input is supported: the food name is kept in the user's language while an English translation is used for the lookup.

## Requirements

- iOS 26+ / macOS 26+ / tvOS 26+ / watchOS 26+ / visionOS 26+
- Swift 6.2+
- A device with Apple Intelligence enabled (for anything not resolved from the table)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/mfsaglam/CalorieEstimator.git", from: "2.0.0")
]
```

Then add `CalorieEstimator` to your target's dependencies:

```swift
.target(name: "YourTarget", dependencies: ["CalorieEstimator"])
```

### Xcode

1. **File > Add Package Dependencies...**
2. Enter the repository URL
3. Add **CalorieEstimator** to your target

## Usage

There are exactly two entry points, matching how a meal gets logged. Both return the
same `MealEstimate`, so you render the result the same way regardless of source.

### 1. Natural-language phrase (Siri intent)

```swift
import CalorieEstimator

let estimator = CalorieEstimator()

let a = try await estimator.estimate(phrase: "200 grams of grilled chicken")
print(a.foodName, a.grams, a.calories) // "grilled chicken", 200, 330

_ = try await estimator.estimate(phrase: "eight ounces of salmon") // word-numbers
_ = try await estimator.estimate(phrase: "250 ml orange juice")    // volume → grams
_ = try await estimator.estimate(phrase: "two eggs")               // counts → grams
_ = try await estimator.estimate(phrase: "banana")                 // no amount → 1 serving
_ = try await estimator.estimate(phrase: "iki yumurta")            // any language
```

### 2. Food name + weight (text field)

The weight is any `Measurement<UnitMass>` — grams, ounces, pounds, kilograms — and is
converted to grams **in code**; the model never parses units on this path.

```swift
let a = try await estimator.estimate(meal: "chicken breast",
                                     weight: Measurement(value: 8, unit: .ounces))
print(a.grams, a.calories) // 227, 374  (165 kcal/100g × 227 g)

// Convenience overload when you already have grams:
let b = try await estimator.estimate(meal: "white rice", grams: 250)
print(b.calories, b.source) // 325, .database  (resolved from the table — no model call)
```

### Composite dishes (automatic)

You never choose "single food" vs "dish". When the input names a composite dish, both
methods break it into ingredients and sum them:

```swift
let dish = try await estimator.estimate(phrase: "kremalı mantarlı makarna")
print(dish.calories)          // e.g. 337
print(dish.source)            // .decomposed
for i in dish.ingredients ?? [] {
    print(i.name, i.grams, i.calories) // makarna 120 188, krema 40 136, mantar 60 13
}
```

On the text-field path, the decomposed serving is scaled to the weight you pass in.

### Reading the result

```swift
let e = try await estimator.estimate(phrase: "two eggs")
e.foodName      // "eggs"        — in the user's language
e.grams         // 100
e.calories      // 155
e.source        // .database / .model / .decomposed
e.confidence    // .high / .medium / .low  (optional)
e.ingredients   // nil for a single food; the breakdown for a decomposed dish
```

### Error handling

```swift
do {
    let result = try await estimator.estimate(meal: "pizza", grams: 300)
    print("\(result.calories) kcal")
} catch let error as CalorieEstimatorError {
    print(error.localizedDescription) // unusable output, or model unavailable
}
```

Note: a table hit on `estimate(meal:weight:)` never touches the model, so it never
throws `modelUnavailable`.

## How It Works

1. **Text-field path — table first.** The food is looked up in the `NutritionTable` *before any model session is created*. On a hit, calories are computed in code (`caloriesPer100g × grams / 100`) and returned immediately — zero model calls, works offline, `.high` confidence.
2. **On a miss (or for phrases), one model call.** The model returns the per-100g figure (resolved against the table by English name, so non-English input still benefits from real data), an approximate mass for phrases, and an `isCompositeDish` flag — so routing costs no extra inference.
3. **Composite dishes are decomposed.** The model lists the main ingredients with masses; each ingredient's per-100g is resolved through the same table (falling back to the model) and summed in code. The total is cross-checked against an independent holistic estimate.
4. **Calories are always computed in code**, never trusted from model arithmetic, so they stay consistent with the grams.
5. **Greedy sampling** for single-shot calls makes results reproducible; the internal multi-attempt dish decomposition uses seeded random sampling and reports lower confidence when the attempts disagree.

### Customising the nutrition source

The table is pluggable via the `NutritionTable` protocol (default `LocalNutritionTable`;
`EmptyNutritionTable` defers everything to the model):

```swift
let estimator = CalorieEstimator(nutritionTable: MyNutritionTable())
```

## API Reference

### `CalorieEstimator`

```swift
public struct CalorieEstimator: Sendable {
    public init(nutritionTable: NutritionTable = LocalNutritionTable())

    // Siri-intent path.
    public func estimate(phrase: String) async throws -> MealEstimate

    // Text-field path (units converted to grams in code).
    public func estimate(meal: String, weight: Measurement<UnitMass>) async throws -> MealEstimate
    public func estimate(meal: String, grams: Int) async throws -> MealEstimate // convenience
}
```

### `MealEstimate`

The unified result of both methods.

```swift
public struct MealEstimate: Sendable, Equatable {
    public let foodName: String            // in the user's language
    public let grams: Int
    public let calories: Int
    public let source: Source              // .database / .model / .decomposed
    public let confidence: Confidence?     // .high / .medium / .low, where available
    public let ingredients: [IngredientEstimate]?  // non-nil only for decomposed dishes

    public enum Source: Sendable, Equatable { case database, model, decomposed }
}
```

### `IngredientEstimate`

```swift
public struct IngredientEstimate: Sendable, Equatable {
    public let name: String
    public let grams: Int
    public let calories: Int
    public let source: Source // .database or .model

    public enum Source: Sendable, Equatable { case database, model }
}
```

### `Confidence`

```swift
public enum Confidence: Sendable, Equatable {
    case high    // from the table, or a well-covered, self-consistent breakdown
    case medium  // a model figure, or a partially-covered breakdown
    case low     // implausible, or a breakdown that didn't hold together
}
```

### `NutritionTable`

```swift
public protocol NutritionTable: Sendable {
    func caloriesPer100g(for foodName: String) -> Int?
}
```

`LocalNutritionTable` is the bundled, offline default; `EmptyNutritionTable` always misses.

### `CalorieEstimatorError`

```swift
public enum CalorieEstimatorError: LocalizedError {
    case parsingFailed(response: String)    // unusable model output / non-positive weight
    case modelUnavailable(reason: String)   // Apple Intelligence off / still downloading
}
```

## License

MIT License. See [LICENSE](LICENSE) for details.
