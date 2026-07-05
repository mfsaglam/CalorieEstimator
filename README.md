# CalorieEstimator

A lightweight Swift package that estimates calories for any food item using on-device Apple Intelligence via the [FoundationModels](https://developer.apple.com/documentation/foundationmodels) framework.

All processing happens on-device. No network requests, no API keys, no third-party services.

Calorie figures for common foods come from a **bundled nutrition table** rather than the model's memory, so they're accurate and reproducible. When a food isn't in the table, the model supplies an estimate instead — and every result carries a **confidence** level so you know which is which. Non-English descriptions are supported: the model translates the food name for the lookup while the result keeps the food name in the user's language.

## Requirements

- iOS 26+ / macOS 26+ / tvOS 26+ / watchOS 26+ / visionOS 26+
- Swift 6.2+
- A device with Apple Intelligence enabled

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mfsaglam/CalorieEstimator.git", from: "1.0.0")
]
```

Then add `CalorieEstimator` to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["CalorieEstimator"]
)
```

### Xcode

1. Go to **File > Add Package Dependencies...**
2. Enter the repository URL
3. Add **CalorieEstimator** to your target

## Usage

### Basic

```swift
import CalorieEstimator

let estimator = CalorieEstimator()
let result = try await estimator.estimate(meal: "chicken breast", grams: 150)

print(result.calories)    // 247
print(result.explanation) // "Chicken breast has ~165 kcal per 100g."
print(result.confidence)  // .high  (resolved from the nutrition table)
```

### By count / amount

When you know the number of items rather than a weight, use `estimate(meal:amount:)`.
The model estimates a typical mass for that many items, and the calories are computed
from it. The result's `estimatedGrams` tells you the mass it assumed.

```swift
let result = try await estimator.estimate(meal: "eggs", amount: 2)

print(result.calories)       // 155
print(result.estimatedGrams) // 100
print(result.confidence)     // .high
```

### From a natural-language phrase

When you have a single spoken/typed phrase and don't want to parse the food and
quantity yourself, use `estimate(phrase:)`. It extracts the food, converts the
amount — weight, volume, or count — into an approximate gram weight, and estimates
the calories, all in one on-device inference call.

```swift
import CalorieEstimator

let estimator = CalorieEstimator()

let a = try await estimator.estimate(phrase: "200 grams of grilled chicken")
print(a.foodName, a.grams, a.calories) // "grilled chicken", 200, 330

let b = try await estimator.estimate(phrase: "eight ounces of salmon") // word-numbers work
let c = try await estimator.estimate(phrase: "250 ml orange juice")    // volume → grams
let d = try await estimator.estimate(phrase: "two eggs")               // counts → grams
let e = try await estimator.estimate(phrase: "banana")                 // no amount → 1 serving
```

The returned `foodName` is normalised and contains no quantity or units. If no
amount is stated, a single typical serving is assumed. Inspect `source`
(`.database` / `.modelEstimate`) or `confidence` (`.high` / `.medium`) to see how
the calories were resolved.

### Other languages

Descriptions in any language work. The food name comes back in the user's
language, while an English translation is used internally for the nutrition
lookup — so common foods still resolve from the table with `.high` confidence.

```swift
let tr = try await estimator.estimate(phrase: "iki yumurta") // Turkish: "two eggs"
print(tr.foodName)    // "yumurta"   (kept in the user's language)
print(tr.calories)    // 155         (from the nutrition table)
print(tr.confidence)  // .high
```

### SwiftUI

```swift
import SwiftUI
import CalorieEstimator

struct ContentView: View {
    @State private var calories: Int?

    var body: some View {
        VStack {
            if let calories {
                Text("\(calories) kcal")
            }

            Button("Estimate") {
                Task {
                    let estimator = CalorieEstimator()
                    let result = try await estimator.estimate(meal: "rice", grams: 200)
                    calories = result.calories
                }
            }
        }
    }
}
```

### Error Handling

```swift
do {
    let result = try await estimator.estimate(meal: "pizza", grams: 300)
    print("\(result.calories) kcal")
} catch let error as CalorieEstimatorError {
    // The model response couldn't be parsed into a calorie value
    print(error.localizedDescription)
} catch {
    // FoundationModels errors (model unavailable, guardrail violation, etc.)
    print(error.localizedDescription)
}
```

## How It Works

1. The on-device model parses the request into a **food name** (kept in the user's language), an **English name** for lookup, an approximate **mass in grams**, and a fallback **calories-per-100g** figure.
2. The calories-per-100g is resolved from the **bundled nutrition table** using the English name. Real data beats a memorized guess; the model's own figure is used only when the food isn't in the table.
3. The calorie count is **calculated in code** (`caloriesPer100g * grams / 100`), ensuring consistent, proportional results regardless of portion size — and never a model arithmetic error.
4. **Greedy sampling** is used, so the same input always returns the same result.
5. Each result reports **confidence**: `.high` when the figure came from the table, `.medium` when it came from the model.

### Customising the nutrition source

The nutrition table is pluggable via the `NutritionTable` protocol. Pass your own
implementation (or `EmptyNutritionTable` to rely solely on the model):

```swift
let estimator = CalorieEstimator(nutritionTable: MyNutritionTable())
```

## API Reference

### `CalorieEstimator`

```swift
public struct CalorieEstimator: Sendable {
    public init(nutritionTable: NutritionTable = LocalNutritionTable())
    public func estimate(meal: String, grams: Int) async throws -> CalorieEstimation
    public func estimate(meal: String, amount: Int) async throws -> CalorieEstimation
    public func estimate(phrase: String) async throws -> MealEstimate
}
```

### `Confidence`

How much to trust an estimate, based on where its calories-per-100g figure came from.

```swift
public enum Confidence: Sendable, Equatable {
    case high    // resolved from the nutrition table
    case medium  // supplied by the model (food not in the table)
}
```

### `MealEstimate`

Returned by `estimate(phrase:)`.

```swift
public struct MealEstimate: Sendable, Equatable {
    public let foodName: String  // cleaned food, in the user's language, without the quantity
    public let grams: Int         // approximate mass in grams for the described amount
    public let calories: Int      // estimated calories (kcal) for that amount
    public let source: Source     // .database or .modelEstimate
    public var confidence: Confidence  // .high for .database, .medium for .modelEstimate

    public enum Source: Sendable, Equatable {
        case database      // figure came from the nutrition table
        case modelEstimate // figure came from the model
    }
}
```

### `CalorieEstimation`

Returned by `estimate(meal:grams:)` and `estimate(meal:amount:)`.

```swift
public struct CalorieEstimation: Sendable {
    public let calories: Int         // total estimated calories (kcal)
    public let explanation: String?   // e.g. "Chicken breast has ~165 kcal per 100g."
    public let estimatedGrams: Int?   // assumed mass (populated by estimate(meal:amount:))
    public let confidence: Confidence // .high (table) or .medium (model)
}
```

### `NutritionTable`

The pluggable source of calories-per-100g figures. `LocalNutritionTable` (the
default) is a bundled, offline table of common foods; `EmptyNutritionTable` always
misses, deferring to the model.

```swift
public protocol NutritionTable: Sendable {
    func caloriesPer100g(for foodName: String) -> Int?
}
```

### `CalorieEstimatorError`

```swift
public enum CalorieEstimatorError: LocalizedError {
    case parsingFailed(response: String)    // model returned unusable output
    case modelUnavailable(reason: String)   // Apple Intelligence off / still downloading
}
```

## License

MIT License. See [LICENSE](LICENSE) for details.
