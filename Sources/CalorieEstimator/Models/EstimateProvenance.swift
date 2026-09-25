/// The trust boundary that produced an estimate.
///
/// This is more precise than ``MealEstimate/Source`` while leaving the original
/// source enum intact for source compatibility.
public enum EstimateProvenance: Sendable, Equatable {
    /// A trusted local recipe supplied composition and local nutrition supplied energy.
    case localRecipe
    /// A trusted local nutrition entry directly described the requested food.
    case localNutrition
    /// The model proposed a composition, but every nutritional value came from local data.
    case modelAssistedRecipe
    /// The model supplied the nutritional density because no local knowledge resolved it.
    case modelNutrition
}
