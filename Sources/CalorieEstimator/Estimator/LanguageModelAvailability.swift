import FoundationModels

/// Application-boundary view of Apple Intelligence availability.
///
/// Keeping this injectable lets callers be tested without requiring particular
/// hardware while FoundationModels remains isolated from domain and data layers.
protocol LanguageModelAvailabilityProviding: Sendable {
    /// Nil when the on-device model is available; otherwise a user-facing reason.
    var unavailableReason: String? { get }
}

struct SystemLanguageModelAvailabilityProvider: LanguageModelAvailabilityProviding {
    var unavailableReason: String? {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        return Self.unavailableReason(for: model.availability)
    }

    static func unavailableReason(
        for availability: SystemLanguageModel.Availability
    ) -> String? {
        guard case .available = availability else {
            return FoundationModelMealParser.description(for: availability)
        }
        return nil
    }
}
