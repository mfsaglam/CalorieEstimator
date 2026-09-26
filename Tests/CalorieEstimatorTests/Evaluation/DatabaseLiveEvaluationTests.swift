import Foundation
import Testing
@testable import CalorieEstimator

@Suite("Database Live Evaluation", .serialized)
struct DatabaseLiveEvaluationTests {
    struct Report: Decodable {
        let benchmark: Benchmark
    }

    struct Benchmark: Decodable {
        let cases: [BenchmarkCase]
    }

    struct BenchmarkCase: Decodable {
        struct Modifier: Codable {
            let operation: String
            let ingredientID: String
            let grams: Int?

            enum CodingKeys: String, CodingKey {
                case operation
                case ingredientID = "ingredient_id"
                case grams
            }
        }

        let id: String
        let input: String
        let lookup: String?
        let language: String
        let category: String
        let cohort: String
        let route: String
        let expectedRecipeID: String?
        let expectedProvenance: String?
        let expectedBaseIngredientIDs: [String]
        let expectedFinalWeightGrams: Int
        let baseGrams: Int?
        let expectedModifier: Modifier?

        enum CodingKeys: String, CodingKey {
            case id, input, lookup, language, category, cohort, route
            case expectedRecipeID = "expected_recipe_id"
            case expectedProvenance = "expected_provenance"
            case expectedBaseIngredientIDs = "expected_base_ingredient_ids"
            case expectedFinalWeightGrams = "expected_final_weight_grams"
            case baseGrams = "base_grams"
            case expectedModifier = "expected_modifier"
        }
    }

    struct IngredientResult: Codable {
        let ingredientID: String?
        let name: String
        let grams: Int
        let calories: Int
        let source: String

        enum CodingKeys: String, CodingKey {
            case ingredientID = "ingredient_id"
            case name, grams, calories, source
        }
    }

    struct Invariants: Codable {
        let massConserved: Bool?
        let noNegativeIngredientGrams: Bool
        let noDuplicateIngredientIDs: Bool
        let noZeroWeightIngredients: Bool
        let nonnegativeCalories: Bool
        let trustedIngredientsExist: Bool
        let localRecipeHasTrustedRecipeID: Bool
        let hardFailure: Bool

        enum CodingKeys: String, CodingKey {
            case massConserved = "mass_conserved"
            case noNegativeIngredientGrams = "no_negative_ingredient_grams"
            case noDuplicateIngredientIDs = "no_duplicate_ingredient_ids"
            case noZeroWeightIngredients = "no_zero_weight_ingredients"
            case nonnegativeCalories = "nonnegative_calories"
            case trustedIngredientsExist = "trusted_ingredients_exist"
            case localRecipeHasTrustedRecipeID = "local_recipe_has_trusted_recipe_id"
            case hardFailure = "hard_failure"
        }
    }

    struct Result: Codable {
        let id: String
        let input: String
        let lookup: String?
        let language: String
        let category: String
        let cohort: String
        let route: String
        let expectedRecipeID: String?
        let actualRecipeID: String?
        let recipeHit: Bool
        let provenance: String?
        let confidence: String?
        let ingredients: [IngredientResult]?
        let totalGrams: Int?
        let calories: Int?
        let fallbackStage: String?
        let modifierExpected: BenchmarkCase.Modifier?
        let modifierActual: String?
        let modifierCorrect: Bool?
        let timeoutOrFailure: String?
        let invariants: Invariants?
        let plausibility: String?
        let plausibilityReasons: [String]
        let estimatedFoundationModelsRequests: Int
        let elapsedMilliseconds: Int

        enum CodingKeys: String, CodingKey {
            case id, input, lookup, language, category, cohort, route, provenance, confidence, ingredients, calories, plausibility
            case expectedRecipeID = "expected_recipe_id"
            case actualRecipeID = "actual_recipe_id"
            case recipeHit = "recipe_hit"
            case totalGrams = "total_grams"
            case fallbackStage = "fallback_stage"
            case modifierExpected = "modifier_expected"
            case modifierActual = "modifier_actual"
            case modifierCorrect = "modifier_correct"
            case timeoutOrFailure = "timeout_or_failure"
            case invariants
            case plausibilityReasons = "plausibility_reasons"
            case estimatedFoundationModelsRequests = "foundationmodels_requests"
            case elapsedMilliseconds = "elapsed_milliseconds"
        }
    }

    struct Event: Codable {
        let event: String
        let batchID: String
        let caseID: String?
        let timestamp: String
        let elapsedMilliseconds: Int?
        let modelAvailability: String?
        let result: Result?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case event
            case batchID = "batch_id"
            case caseID = "case_id"
            case timestamp
            case elapsedMilliseconds = "elapsed_milliseconds"
            case modelAvailability = "model_availability"
            case result, reason
        }
    }

    @Test("Run bounded fixed benchmark", .enabled(if: ProcessInfo.processInfo.environment["RUN_DATABASE_LIVE_EVALUATION"] == "1"))
    func runBoundedBenchmark() async throws {
        let root = try projectRoot()
        let reportURL = root.appending(path: "Data/Reports/database_evaluation.json")
        let report = try JSONDecoder().decode(Report.self, from: Data(contentsOf: reportURL))
        let environment = ProcessInfo.processInfo.environment
        let requestedIDs = environment["LIVE_EVALUATION_CASE_IDS", default: ""]
            .split(separator: ",")
            .map(String.init)
        guard !requestedIDs.isEmpty, requestedIDs.count <= 5, Set(requestedIDs).count == requestedIDs.count else {
            throw HarnessError.invalidCaseSelection("LIVE_EVALUATION_CASE_IDS must contain 1-5 unique comma-separated IDs")
        }
        let casesByID = Dictionary(uniqueKeysWithValues: report.benchmark.cases.map { ($0.id, $0) })
        let selectedCases = try requestedIDs.map { id in
            guard let benchmarkCase = casesByID[id] else { throw HarnessError.unknownCase(id) }
            return benchmarkCase
        }
        let batchID = environment["LIVE_EVALUATION_BATCH_ID"] ?? "batch-\(UUID().uuidString.lowercased())"
        let defaultOutput = root.appending(path: "Data/Reports/live_batches/\(batchID).jsonl")
        let outputURL = environment["LIVE_EVALUATION_OUTPUT"].map { URL(filePath: $0) } ?? defaultOutput
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: outputURL.path()) else {
            throw HarnessError.outputAlreadyExists(outputURL.path())
        }
        FileManager.default.createFile(atPath: outputURL.path(), contents: nil)
        let estimator = CalorieEstimator()
        let database = LocalRecipeDatabase()
        let modelAvailability: String
        do {
            _ = try CalorieEstimator.availableModel()
            modelAvailability = "available"
        } catch {
            modelAvailability = "unavailable: \(String(reflecting: error))"
        }

        try appendEvent(Event(
            event: "BATCH_START",
            batchID: batchID,
            caseID: nil,
            timestamp: timestamp(),
            elapsedMilliseconds: nil,
            modelAvailability: modelAvailability,
            result: nil,
            reason: "\(selectedCases.count) cases; no retries"
        ), to: outputURL)
        for benchmarkCase in selectedCases {
            let start = ContinuousClock.now
            emit("START \(benchmarkCase.id) \(timestamp())")
            try appendEvent(Event(
                event: "START",
                batchID: batchID,
                caseID: benchmarkCase.id,
                timestamp: timestamp(),
                elapsedMilliseconds: 0,
                modelAvailability: nil,
                result: nil,
                reason: nil
            ), to: outputURL)
            let anticipatedRequests = try await anticipatedFoundationModelRequests(
                for: benchmarkCase,
                database: database,
                modelAvailable: modelAvailability == "available"
            )
            do {
                let estimate: MealEstimate
                if benchmarkCase.route == "explicitWeight" {
                    estimate = try await estimator.estimate(
                        meal: benchmarkCase.lookup ?? benchmarkCase.input,
                        grams: benchmarkCase.expectedFinalWeightGrams
                    )
                } else {
                    estimate = try await estimator.estimate(phrase: benchmarkCase.input)
                }
                let result = try await makeResult(
                    benchmarkCase: benchmarkCase,
                    estimate: estimate,
                    database: database,
                    requests: anticipatedRequests,
                    elapsed: start.duration(to: .now)
                )
                let elapsed = milliseconds(start.duration(to: .now))
                try appendEvent(Event(
                    event: "DONE",
                    batchID: batchID,
                    caseID: benchmarkCase.id,
                    timestamp: timestamp(),
                    elapsedMilliseconds: elapsed,
                    modelAvailability: nil,
                    result: result,
                    reason: "success"
                ), to: outputURL)
                emit("DONE \(benchmarkCase.id) elapsed_ms=\(elapsed) status=success")
            } catch {
                let description = String(reflecting: error)
                let isTimeout = description.contains("modelTimedOut") || description.localizedCaseInsensitiveContains("timed out")
                let actualRequests = isFoundationModelFailure(description) ? 1 : anticipatedRequests
                let result = Result(
                    id: benchmarkCase.id,
                    input: benchmarkCase.input,
                    lookup: benchmarkCase.lookup,
                    language: benchmarkCase.language,
                    category: benchmarkCase.category,
                    cohort: benchmarkCase.cohort,
                    route: benchmarkCase.route,
                    expectedRecipeID: benchmarkCase.expectedRecipeID,
                    actualRecipeID: nil,
                    recipeHit: false,
                    provenance: nil,
                    confidence: nil,
                    ingredients: nil,
                    totalGrams: nil,
                    calories: nil,
                    fallbackStage: "failure",
                    modifierExpected: benchmarkCase.expectedModifier,
                    modifierActual: nil,
                    modifierCorrect: benchmarkCase.expectedModifier == nil ? nil : false,
                    timeoutOrFailure: description,
                    invariants: nil,
                    plausibility: nil,
                    plausibilityReasons: [],
                    estimatedFoundationModelsRequests: actualRequests,
                    elapsedMilliseconds: milliseconds(start.duration(to: .now))
                )
                let elapsed = milliseconds(start.duration(to: .now))
                try appendEvent(Event(
                    event: isTimeout ? "TIMEOUT" : "DONE",
                    batchID: batchID,
                    caseID: benchmarkCase.id,
                    timestamp: timestamp(),
                    elapsedMilliseconds: elapsed,
                    modelAvailability: nil,
                    result: result,
                    reason: description
                ), to: outputURL)
                emit("DONE \(benchmarkCase.id) elapsed_ms=\(elapsed) status=\(isTimeout ? "timeout" : "failure")")
                // FoundationModels cancellation is not reliable enough to prove that
                // a timed-out request has stopped. End this batch; the external
                // supervisor also kills the entire process on a silent case timeout.
                if isTimeout { break }
            }
        }
        try appendEvent(Event(
            event: "BATCH_DONE",
            batchID: batchID,
            caseID: nil,
            timestamp: timestamp(),
            elapsedMilliseconds: nil,
            modelAvailability: nil,
            result: nil,
            reason: nil
        ), to: outputURL)
    }

    private func anticipatedFoundationModelRequests(
        for benchmarkCase: BenchmarkCase,
        database: LocalRecipeDatabase,
        modelAvailable: Bool
    ) async throws -> Int {
        guard benchmarkCase.route == "phrase", modelAvailable else { return 0 }
        let candidate = try await database.recipeCandidate(containedIn: RecipeQuery(name: benchmarkCase.input))
        return candidate == nil ? 1 : 4
    }

    private func makeResult(
        benchmarkCase: BenchmarkCase,
        estimate: MealEstimate,
        database: LocalRecipeDatabase,
        requests: Int,
        elapsed: Duration
    ) async throws -> Result {
        let ingredients = estimate.ingredients?.map {
            IngredientResult(
                ingredientID: $0.ingredientID?.rawValue,
                name: $0.name,
                grams: $0.grams,
                calories: $0.calories,
                source: ingredientSource($0.source)
            )
        }
        let ingredientIDs = ingredients?.compactMap(\.ingredientID) ?? []
        let massConserved = ingredients.map { $0.reduce(0) { $0 + $1.grams } == estimate.grams }
        let trustedRecipeExists: Bool
        if let recipeID = estimate.recipeID {
            trustedRecipeExists = try await database.recipe(id: recipeID) != nil
        } else {
            trustedRecipeExists = estimate.provenance != .localRecipe
        }
        let trustedIngredientsExist: Bool
        if estimate.provenance == .localRecipe {
            trustedIngredientsExist = ingredients?.allSatisfy { $0.ingredientID != nil } == true
        } else {
            trustedIngredientsExist = true
        }
        let invariants = Invariants(
            massConserved: massConserved,
            noNegativeIngredientGrams: ingredients?.allSatisfy { $0.grams >= 0 } ?? true,
            noDuplicateIngredientIDs: Set(ingredientIDs).count == ingredientIDs.count,
            noZeroWeightIngredients: ingredients?.allSatisfy { $0.grams > 0 } ?? true,
            nonnegativeCalories: estimate.calories >= 0,
            trustedIngredientsExist: trustedIngredientsExist,
            localRecipeHasTrustedRecipeID: trustedRecipeExists,
            hardFailure: massConserved == false
                || ingredients?.contains(where: { $0.grams <= 0 }) == true
                || Set(ingredientIDs).count != ingredientIDs.count
                || estimate.calories < 0
                || !trustedIngredientsExist
                || !trustedRecipeExists
        )
        let modifier = try await modifierAssessment(
            benchmarkCase: benchmarkCase,
            estimate: estimate,
            database: database
        )
        let plausibility = plausibilityAssessment(estimate)
        return Result(
            id: benchmarkCase.id,
            input: benchmarkCase.input,
            lookup: benchmarkCase.lookup,
            language: benchmarkCase.language,
            category: benchmarkCase.category,
            cohort: benchmarkCase.cohort,
            route: benchmarkCase.route,
            expectedRecipeID: benchmarkCase.expectedRecipeID,
            actualRecipeID: estimate.recipeID?.rawValue,
            recipeHit: benchmarkCase.expectedRecipeID != nil && estimate.recipeID?.rawValue == benchmarkCase.expectedRecipeID,
            provenance: provenance(estimate.provenance),
            confidence: confidence(estimate.confidence),
            ingredients: ingredients,
            totalGrams: estimate.grams,
            calories: estimate.calories,
            fallbackStage: provenance(estimate.provenance),
            modifierExpected: benchmarkCase.expectedModifier,
            modifierActual: modifier.actual,
            modifierCorrect: modifier.correct,
            timeoutOrFailure: nil,
            invariants: invariants,
            plausibility: plausibility.classification,
            plausibilityReasons: plausibility.reasons,
            estimatedFoundationModelsRequests: requests,
            elapsedMilliseconds: milliseconds(elapsed)
        )
    }

    private func modifierAssessment(
        benchmarkCase: BenchmarkCase,
        estimate: MealEstimate,
        database: LocalRecipeDatabase
    ) async throws -> (actual: String?, correct: Bool?) {
        guard let expected = benchmarkCase.expectedModifier else { return (nil, nil) }
        let target = estimate.ingredients?.first { $0.ingredientID?.rawValue == expected.ingredientID }
        let baseRatio: Double?
        if let recipeID = benchmarkCase.expectedRecipeID,
           let recipe = try await database.recipe(id: RecipeID(rawValue: recipeID)) {
            baseRatio = recipe.ingredients.first { $0.id.rawValue == expected.ingredientID }?.ratio
        } else {
            baseRatio = nil
        }
        switch expected.operation {
        case "remove":
            return (target == nil ? "remove \(expected.ingredientID)" : "ingredient retained at \(target!.grams)g", target == nil)
        case "increase":
            guard let target else { return ("ingredient missing", false) }
            if let explicit = expected.grams,
               let baseRatio,
               let baseGrams = benchmarkCase.baseGrams {
                let baseline = Int((Double(baseGrams) * baseRatio).rounded())
                return ("increase \(expected.ingredientID) to \(target.grams)g", target.grams >= baseline + explicit - 1)
            }
            return ("increase \(expected.ingredientID) to \(target.grams)g", true)
        case "decrease":
            guard let target,
                  let ratio = baseRatio else {
                return (target == nil ? "ingredient removed, not decreased" : nil, false)
            }
            let baseline = Int((Double(estimate.grams) * ratio).rounded())
            return ("decrease \(expected.ingredientID) to \(target.grams)g", target.grams < baseline)
        default:
            return ("unrecognized operation", false)
        }
    }

    private func plausibilityAssessment(_ estimate: MealEstimate) -> (classification: String, reasons: [String]) {
        var reasons: [String] = []
        guard estimate.grams > 0 else { return ("clearly suspicious", ["non-positive total mass"]) }
        let density = Double(estimate.calories) * 100 / Double(estimate.grams)
        if density < 15 || density > 700 { reasons.append("energy-density extreme") }
        if let ingredients = estimate.ingredients,
           let maximum = ingredients.map(\.grams).max(),
           Double(maximum) / Double(estimate.grams) > 0.95 {
            reasons.append("one ingredient exceeds 95% of final mass")
        }
        return reasons.isEmpty ? ("plausible", []) : ("clearly suspicious", reasons)
    }

    private func projectRoot() throws -> URL {
        var url = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path()) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func provenance(_ value: EstimateProvenance) -> String {
        switch value {
        case .localRecipe: "localRecipe"
        case .localNutrition: "localNutrition"
        case .modelAssistedRecipe: "modelAssistedRecipe"
        case .modelNutrition: "modelNutrition"
        }
    }

    private func ingredientSource(_ value: IngredientEstimate.Source) -> String {
        switch value {
        case .database: "database"
        case .model: "model"
        }
    }

    private func confidence(_ value: Confidence?) -> String? {
        switch value {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        case nil: nil
        }
    }

    private func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func emit(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
        fflush(stderr)
    }

    private func appendEvent(_ event: Event, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(event)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private func isFoundationModelFailure(_ description: String) -> Bool {
        description.contains("FoundationModels")
            || description.contains("ModelManager")
            || description.contains("Underlying connection was invalidated")
    }

    enum HarnessError: Error {
        case invalidCaseSelection(String)
        case unknownCase(String)
        case outputAlreadyExists(String)
    }
}
