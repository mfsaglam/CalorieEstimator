import FoundationModels

struct RecipeDatabaseTool: Tool {
    let name = "lookupLocalRecipe"
    let description = "Find a trusted local recipe identity from an unmodified base-dish name. Use its returned ID exactly; do not invent IDs."
    let database: any RecipeDatabase

    func call(arguments: RecipeLookupArguments) async throws -> String {
        let query = RecipeQuery(
            name: arguments.name,
            languageCode: Self.nonempty(arguments.languageCode),
            localeIdentifier: Self.nonempty(arguments.localeIdentifier),
            cuisine: Self.nonempty(arguments.cuisine)
        )
        guard let recipe = try await database.recipe(matching: query) else {
            return "No confident local recipe match."
        }
        let metadata = [recipe.cuisine, recipe.region, recipe.variant]
            .compactMap { $0 }
            .joined(separator: ", ")
        return "Trusted recipe ID: \(recipe.id.rawValue); canonical name: \(recipe.canonicalName); metadata: \(metadata)"
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
