import Foundation

/// Errors thrown by ``CalorieEstimator``.
public enum CalorieEstimatorError: LocalizedError, Sendable {
    /// The model returned output that couldn't be turned into a usable estimate.
    case parsingFailed(response: String)
    /// The on-device model is unavailable (e.g. Apple Intelligence disabled or still downloading).
    case modelUnavailable(reason: String)
    /// The on-device semantic model did not complete within the bounded deadline.
    case modelTimedOut

    public var errorDescription: String? {
        switch self {
        case .parsingFailed(let response):
            return "The model returned an unusable estimate: \(response)"
        case .modelUnavailable(let reason):
            return "The on-device model is unavailable: \(reason)"
        case .modelTimedOut:
            return "The on-device model did not finish before the estimation deadline."
        }
    }
}
