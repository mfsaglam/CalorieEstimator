from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from fooddb.models import (
    ImportedAlias,
    ImportedDataset,
    ImportedIngredient,
    ImportedNutritionRecord,
    ImportedRecipe,
    ImportedRecipeIngredient,
    SourceProvenance,
)


def load(seed_sql: Path, nutrition_json: Path) -> ImportedDataset:
    database = sqlite3.connect(":memory:")
    database.executescript(seed_sql.read_text(encoding="utf-8"))
    nutrition = json.loads(nutrition_json.read_text(encoding="utf-8"))
    dataset = ImportedDataset(source="manual_seed")
    provenance = SourceProvenance(
        source="CalorieEstimator manually curated seed",
        record_id="seed-v1",
        url="DataSources/manual/seed.sql",
        license="Project-authored",
        import_version="1",
        import_date="2026-09-26",
        confidence="high",
        verification_status="manually_curated",
    )

    for row in database.execute("SELECT id, canonical_name, nutrition_lookup_name FROM ingredients ORDER BY id"):
        ingredient_id, canonical_name, lookup_name = row
        aliases = [
            ImportedAlias(alias, language, locale, provenance)
            for alias, language, locale in database.execute(
                "SELECT alias, language_code, locale_identifier FROM ingredient_aliases WHERE ingredient_id = ?",
                (ingredient_id,),
            )
        ]
        dataset.ingredients[ingredient_id] = ImportedIngredient(
            id=ingredient_id,
            canonical_name=canonical_name,
            nutrition_lookup_name=lookup_name,
            aliases=aliases,
            nutrition=ImportedNutritionRecord(
                kcal_per_100g=float(nutrition[ingredient_id]),
                prepared_state="as_eaten_legacy",
                provenance=provenance,
            ),
        )

    for row in database.execute(
        "SELECT id, canonical_name, cuisine, region, variant, default_serving_grams FROM recipes ORDER BY id"
    ):
        recipe_id, name, cuisine, region, variant, serving = row
        aliases = [
            ImportedAlias(alias, language, locale, provenance)
            for alias, language, locale in database.execute(
                "SELECT alias, language_code, locale_identifier FROM recipe_aliases WHERE recipe_id = ?",
                (recipe_id,),
            )
        ]
        ingredients = [
            ImportedRecipeIngredient(ingredient_id, float(ratio) * 1000.0)
            for ingredient_id, ratio in database.execute(
                "SELECT ingredient_id, ratio FROM recipe_ingredients WHERE recipe_id = ? ORDER BY position",
                (recipe_id,),
            )
        ]
        dataset.recipes.append(
            ImportedRecipe(
                id=recipe_id,
                canonical_name=name,
                cuisine=cuisine,
                region=region,
                variant=variant,
                default_serving_grams=serving,
                ingredients=ingredients,
                aliases=aliases,
                provenance=SourceProvenance(**{**provenance.__dict__, "record_id": recipe_id}),
                quality_tier="B",
            )
        )
    dataset.discovered = len(dataset.recipes)
    database.close()
    return dataset
