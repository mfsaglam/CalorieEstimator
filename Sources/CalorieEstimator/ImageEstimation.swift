import Foundation
import CoreGraphics
import ImageIO
import Vision

// MARK: - Food Classification

/// A single food label produced by a ``FoodImageClassifier``.
public struct FoodClassification: Sendable, Equatable {
    /// The classifier's label for the food (e.g. "cheeseburger", "banana").
    public let identifier: String
    /// The classifier's confidence in this label, normalised to `0...1`.
    public let confidence: Float

    public init(identifier: String, confidence: Float) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

/// Identifies the food(s) present in an image.
///
/// The package ships ``VisionFoodClassifier`` as a zero-dependency default that
/// uses Vision's on-device image classifier. Conform your own type to swap in a
/// food-specific Core ML model (e.g. a Food-101 classifier or a YOLO detector)
/// without changing the estimation pipeline.
public protocol FoodImageClassifier: Sendable {
    /// Classify the food in an image, ordered most-confident first.
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - orientation: The image's display orientation.
    /// - Returns: Candidate food labels, sorted by descending confidence.
    func classify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [FoodClassification]
}

// MARK: - Default Vision Classifier

/// A ``FoodImageClassifier`` backed by Vision's built-in `ClassifyImageRequest`.
///
/// This runs entirely on-device with no model to bundle. It classifies the
/// *whole* image against Vision's general taxonomy, so it works best on a photo
/// of a single dominant dish rather than a plate of several separate items.
public struct VisionFoodClassifier: FoodImageClassifier {

    /// The minimum precision (for a fixed recall) an observation must meet to be
    /// kept. Higher precision means fewer, more trustworthy labels.
    public let minimumPrecision: Float
    /// The recall paired with ``minimumPrecision`` when filtering observations.
    public let recall: Float

    /// - Parameters:
    ///   - minimumPrecision: Precision floor for kept labels (default `0.1`).
    ///   - recall: Recall paired with the precision floor (default `0.8`).
    public init(minimumPrecision: Float = 0.1, recall: Float = 0.8) {
        self.minimumPrecision = minimumPrecision
        self.recall = recall
    }

    public func classify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [FoodClassification] {
        let request = ClassifyImageRequest()
        let observations = try await request.perform(on: image, orientation: orientation)
            .filter { $0.hasMinimumPrecision(minimumPrecision, forRecall: recall) }

        return observations
            .sorted { $0.confidence > $1.confidence }
            .map { FoodClassification(identifier: $0.identifier, confidence: $0.confidence) }
    }
}

// MARK: - Image Estimate Result

/// The result of estimating a meal from a photo.
public struct ClassifiedMeal: Sendable, Equatable {
    /// The food name, grams, and calories for the detected dish.
    public let estimate: MealEstimate
    /// The raw label the classifier assigned to the dish.
    public let detectedLabel: String
    /// The classifier's confidence in ``detectedLabel`` (`0...1`).
    public let confidence: Float
    /// Other candidate labels the classifier considered, for disambiguation UI.
    public let alternatives: [FoodClassification]

    public init(
        estimate: MealEstimate,
        detectedLabel: String,
        confidence: Float,
        alternatives: [FoodClassification]
    ) {
        self.estimate = estimate
        self.detectedLabel = detectedLabel
        self.confidence = confidence
        self.alternatives = alternatives
    }
}

// MARK: - Image-Based Estimation

extension CalorieEstimator {

    /// Estimate a meal from a photo of a single dominant dish.
    ///
    /// The image is classified on-device to identify the food, and that label is
    /// fed into ``estimate(phrase:)`` to derive an approximate serving in grams
    /// and its calories — so the whole flow stays on-device.
    ///
    /// Because a single 2D photo carries no scale, the grams reflect a *typical
    /// serving* for the detected food rather than a measurement of the portion
    /// shown. For best results, photograph one dish at a time.
    ///
    /// - Parameters:
    ///   - image: A photo of one dish.
    ///   - orientation: The image's display orientation (default `.up`).
    ///   - classifier: The food classifier to use (default ``VisionFoodClassifier``).
    /// - Returns: A ``ClassifiedMeal`` with the estimate, detected label,
    ///   confidence, and alternative labels.
    /// - Throws: ``CalorieEstimatorError/noFoodDetected`` when the classifier
    ///   finds nothing, or the errors thrown by ``estimate(phrase:)``.
    public func estimate(
        image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        using classifier: any FoodImageClassifier = VisionFoodClassifier()
    ) async throws -> ClassifiedMeal {
        let classifications = try await classifier.classify(image, orientation: orientation)

        guard let top = classifications.first else {
            throw CalorieEstimatorError.noFoodDetected
        }

        let estimate = try await estimate(phrase: top.identifier)

        return ClassifiedMeal(
            estimate: estimate,
            detectedLabel: top.identifier,
            confidence: top.confidence,
            alternatives: Array(classifications.dropFirst().prefix(4))
        )
    }
}
