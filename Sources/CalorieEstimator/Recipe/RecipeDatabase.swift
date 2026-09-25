/// A source of trusted, canonical recipe knowledge.
public protocol RecipeDatabase: Sendable {
    /// Returns a confident match, or `nil` when the query is unknown or ambiguous.
    func recipe(matching query: RecipeQuery) async throws -> Recipe?

    /// Returns a recipe whose complete canonical name or alias appears as a
    /// bounded sequence of words in a modified meal description. Implementations
    /// must reject partial-word and ambiguous matches.
    func recipeCandidate(containedIn query: RecipeQuery) async throws -> Recipe?

    /// Returns the exact canonical recipe, or `nil` when the ID is not present.
    func recipe(id: RecipeID) async throws -> Recipe?
}

public extension RecipeDatabase {
    /// Source-compatible default for databases that support exact matching only.
    func recipeCandidate(containedIn query: RecipeQuery) async throws -> Recipe? {
        try await recipe(matching: query)
    }
}

/// A recipe database that never resolves a recipe.
public struct EmptyRecipeDatabase: RecipeDatabase {
    public init() {}

    public func recipe(matching query: RecipeQuery) async throws -> Recipe? { nil }
    public func recipe(id: RecipeID) async throws -> Recipe? { nil }
}

enum RecipeDatabaseError: Error, Sendable {
    case resourceMissing
    case sqlite(message: String)
    case invalidRecipe(id: String, reason: String)
}
