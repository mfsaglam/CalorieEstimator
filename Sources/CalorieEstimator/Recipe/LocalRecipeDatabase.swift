import Foundation
import SQLite3

/// The bundled, read-only SQLite recipe knowledge base.
public actor LocalRecipeDatabase: RecipeDatabase {
    private let databasePath: String?

    /// Uses the recipe database bundled with this package.
    public init() {
        databasePath = Bundle.module.url(forResource: "Recipes", withExtension: "sqlite3")?.path
    }

    /// Uses a database at an explicit URL. Primarily useful for applications that
    /// ship an expanded database and for tests.
    public init(databaseURL: URL) {
        databasePath = databaseURL.path
    }

    public func recipe(matching query: RecipeQuery) async throws -> Recipe? {
        let normalized = FoodNameNormalizer.normalize(query.name)
        guard !normalized.isEmpty else { return nil }

        return try withDatabase { database in
            let sql = """
            SELECT r.id, r.cuisine, a.language_code, a.locale_identifier,
                   CASE WHEN r.normalized_name = ?1 THEN 1 ELSE 0 END
            FROM recipes r
            LEFT JOIN recipe_aliases a ON a.recipe_id = r.id
            WHERE r.normalized_name = ?1 OR a.normalized_alias = ?1
            """
            let statement = try Self.prepare(sql, in: database)
            defer { sqlite3_finalize(statement) }
            try Self.bind(normalized, at: 1, in: statement, database: database)

            var scores: [String: Int] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Self.text(statement, column: 0)
                var score = sqlite3_column_int(statement, 4) == 1 ? 1 : 0
                if Self.matches(query.cuisine, Self.optionalText(statement, column: 1)) { score += 2 }
                if Self.matches(query.languageCode, Self.optionalText(statement, column: 2)) { score += 4 }
                if Self.matches(query.localeIdentifier, Self.optionalText(statement, column: 3)) { score += 8 }
                scores[id] = max(scores[id] ?? Int.min, score)
            }

            guard !scores.isEmpty else { return nil }
            let ranked = scores.sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }
            if ranked.count > 1, ranked[0].value == ranked[1].value { return nil }
            return try Self.loadRecipe(id: ranked[0].key, from: database)
        }
    }

    public func recipe(id: RecipeID) async throws -> Recipe? {
        try withDatabase { try Self.loadRecipe(id: id.rawValue, from: $0) }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let databasePath else { throw RecipeDatabaseError.resourceMissing }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            if let handle { sqlite3_close(handle) }
            throw RecipeDatabaseError.sqlite(message: message)
        }
        defer { sqlite3_close(handle) }
        return try body(handle)
    }

    private static func loadRecipe(id: String, from database: OpaquePointer) throws -> Recipe? {
        let recipeStatement = try prepare(
            "SELECT canonical_name, cuisine, region, variant, default_serving_grams FROM recipes WHERE id = ?1",
            in: database
        )
        defer { sqlite3_finalize(recipeStatement) }
        try bind(id, at: 1, in: recipeStatement, database: database)
        guard sqlite3_step(recipeStatement) == SQLITE_ROW else { return nil }

        let canonicalName = text(recipeStatement, column: 0)
        let cuisine = optionalText(recipeStatement, column: 1)
        let region = optionalText(recipeStatement, column: 2)
        let variant = optionalText(recipeStatement, column: 3)
        let serving = sqlite3_column_type(recipeStatement, 4) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int(recipeStatement, 4))

        let ingredientStatement = try prepare(
            """
            SELECT i.id, i.canonical_name, i.nutrition_lookup_name, ri.ratio
            FROM recipe_ingredients ri
            JOIN ingredients i ON i.id = ri.ingredient_id
            WHERE ri.recipe_id = ?1
            ORDER BY ri.position
            """,
            in: database
        )
        defer { sqlite3_finalize(ingredientStatement) }
        try bind(id, at: 1, in: ingredientStatement, database: database)

        var ingredients: [RecipeIngredient] = []
        while sqlite3_step(ingredientStatement) == SQLITE_ROW {
            ingredients.append(
                RecipeIngredient(
                    id: IngredientID(rawValue: text(ingredientStatement, column: 0)),
                    canonicalName: text(ingredientStatement, column: 1),
                    nutritionLookupName: text(ingredientStatement, column: 2),
                    ratio: sqlite3_column_double(ingredientStatement, 3)
                )
            )
        }

        guard !ingredients.isEmpty else {
            throw RecipeDatabaseError.invalidRecipe(id: id, reason: "recipe has no ingredients")
        }
        let ratioTotal = ingredients.reduce(0) { $0 + $1.ratio }
        guard abs(ratioTotal - 1) <= 0.001 else {
            throw RecipeDatabaseError.invalidRecipe(id: id, reason: "ratios total \(ratioTotal)")
        }
        return Recipe(
            id: RecipeID(rawValue: id),
            canonicalName: canonicalName,
            cuisine: cuisine,
            region: region,
            variant: variant,
            defaultServingGrams: serving,
            ingredients: ingredients
        )
    }

    private static func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RecipeDatabaseError.sqlite(message: String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private static func bind(
        _ value: String,
        at index: Int32,
        in statement: OpaquePointer,
        database: OpaquePointer
    ) throws {
        let result = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else {
            throw RecipeDatabaseError.sqlite(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    private static func text(_ statement: OpaquePointer, column: Int32) -> String {
        String(cString: sqlite3_column_text(statement, column))
    }

    private static func optionalText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return text(statement, column: column)
    }

    private static func matches(_ requested: String?, _ stored: String?) -> Bool {
        guard let requested, let stored else { return false }
        return requested.caseInsensitiveCompare(stored) == .orderedSame
    }
}
