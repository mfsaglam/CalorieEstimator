/// A language-aware query for a canonical recipe.
public struct RecipeQuery: Sendable, Equatable {
    public let name: String
    public let languageCode: String?
    public let localeIdentifier: String?
    public let cuisine: String?

    public init(
        name: String,
        languageCode: String? = nil,
        localeIdentifier: String? = nil,
        cuisine: String? = nil
    ) {
        self.name = name
        self.languageCode = languageCode
        self.localeIdentifier = localeIdentifier
        self.cuisine = cuisine
    }
}

/// A language-aware exact query for a canonical ingredient identity.
public struct IngredientQuery: Sendable, Equatable {
    public let name: String
    public let languageCode: String?
    public let localeIdentifier: String?

    public init(
        name: String,
        languageCode: String? = nil,
        localeIdentifier: String? = nil
    ) {
        self.name = name
        self.languageCode = languageCode
        self.localeIdentifier = localeIdentifier
    }
}

/// Stable ingredient identity and trusted lookup metadata, independent of any recipe ratio.
public struct IngredientIdentity: Sendable, Equatable {
    public let id: IngredientID
    public let canonicalName: String
    public let nutritionLookupName: String

    public init(
        id: IngredientID,
        canonicalName: String,
        nutritionLookupName: String
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.nutritionLookupName = nutritionLookupName
    }
}

/// One ingredient in a canonical recipe, expressed as a fraction of total mass.
public struct RecipeIngredient: Sendable, Equatable {
    public let id: IngredientID
    public let canonicalName: String
    public let nutritionLookupName: String
    public let ratio: Double

    public init(
        id: IngredientID,
        canonicalName: String,
        nutritionLookupName: String,
        ratio: Double
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.nutritionLookupName = nutritionLookupName
        self.ratio = ratio
    }
}

/// A trusted default composition for a canonical dish.
public struct Recipe: Sendable, Equatable {
    public let id: RecipeID
    public let canonicalName: String
    public let cuisine: String?
    public let region: String?
    public let variant: String?
    public let defaultServingGrams: Int?
    public let ingredients: [RecipeIngredient]

    public init(
        id: RecipeID,
        canonicalName: String,
        cuisine: String? = nil,
        region: String? = nil,
        variant: String? = nil,
        defaultServingGrams: Int? = nil,
        ingredients: [RecipeIngredient]
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.cuisine = cuisine
        self.region = region
        self.variant = variant
        self.defaultServingGrams = defaultServingGrams
        self.ingredients = ingredients
    }
}
