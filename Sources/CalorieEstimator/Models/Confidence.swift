/// How much to trust a calorie estimate.
///
/// For single foods this reflects where the calories-per-100g figure came from
/// (database vs model). For decomposed dishes it reflects whether composition
/// came from trusted local data or a model proposal resolved through local nutrition.
public enum Confidence: Sendable, Equatable {
    /// Strong: resolved from the database, or a well-covered, self-consistent breakdown.
    case high
    /// Moderate: a model figure, or a partially-covered / loosely-consistent breakdown.
    case medium
    /// Weak: the estimate is implausible or the model's breakdown didn't hold together.
    case low
}
