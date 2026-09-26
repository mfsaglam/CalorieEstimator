from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class SourceProvenance:
    source: str
    record_id: str
    url: str
    license: str
    import_version: str
    import_date: str
    confidence: str
    verification_status: str


@dataclass(frozen=True)
class ImportedAlias:
    alias: str
    language_code: str | None = None
    locale_identifier: str | None = None
    provenance: SourceProvenance | None = None


@dataclass(frozen=True)
class ImportedNutritionRecord:
    kcal_per_100g: float
    protein_g: float | None = None
    fat_g: float | None = None
    carbohydrate_g: float | None = None
    fiber_g: float | None = None
    prepared_state: str = "as_listed"
    provenance: SourceProvenance | None = None


@dataclass
class ImportedIngredient:
    id: str
    canonical_name: str
    nutrition_lookup_name: str
    aliases: list[ImportedAlias] = field(default_factory=list)
    nutrition: ImportedNutritionRecord | None = None


@dataclass(frozen=True)
class ImportedRecipeIngredient:
    ingredient_id: str
    grams: float


@dataclass
class ImportedRecipe:
    id: str
    canonical_name: str
    cuisine: str | None
    region: str | None
    variant: str | None
    default_serving_grams: int
    ingredients: list[ImportedRecipeIngredient]
    aliases: list[ImportedAlias]
    provenance: SourceProvenance
    quality_tier: str = "A"


@dataclass
class ImportedDataset:
    source: str
    ingredients: dict[str, ImportedIngredient] = field(default_factory=dict)
    recipes: list[ImportedRecipe] = field(default_factory=list)
    rejected: dict[str, int] = field(default_factory=dict)
    discovered: int = 0
    accepted_aliases: int = 0

    def reject(self, reason: str) -> None:
        self.rejected[reason] = self.rejected.get(reason, 0) + 1
