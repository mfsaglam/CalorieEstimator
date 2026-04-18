# CalorieEstimator

A lightweight Swift package that estimates calories for any food item using on-device Apple Intelligence via the [FoundationModels](https://developer.apple.com/documentation/foundationmodels) framework.

All processing happens on-device. No network requests, no API keys, no third-party services.

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

1. The on-device model is asked for the **calories per 100g** of the given food item — a factual recall task it handles well.
2. The actual calorie count is **calculated in code** (`caloriesPer100g * grams / 100`), ensuring consistent and proportional results regardless of portion size.
3. Greedy sampling is used so the same food always returns the same per-100g value.

## API Reference

### `CalorieEstimator`

```swift
public struct CalorieEstimator: Sendable {
    public init()
    public func estimate(meal: String, grams: Int) async throws -> CalorieEstimation
}
```

### `CalorieEstimation`

```swift
public struct CalorieEstimation: Sendable {
    public let calories: Int        // Total estimated calories (kcal)
    public let explanation: String?  // e.g. "Chicken breast has ~165 kcal per 100g."
}
```

### `CalorieEstimatorError`

```swift
public enum CalorieEstimatorError: LocalizedError {
    case parsingFailed(response: String)
}
```

## License

MIT License. See [LICENSE](LICENSE) for details.
