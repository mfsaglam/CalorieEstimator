from __future__ import annotations

import json
import os
import sqlite3
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

from fooddb.models import ImportedAlias, ImportedDataset, ImportedIngredient, ImportedRecipe
from fooddb.normalize import is_compact_script, normalize_name
from fooddb.sources import manual, usda, wikidata


SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE recipes (
    id TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    normalized_name TEXT NOT NULL UNIQUE,
    first_token TEXT NOT NULL,
    compact_script INTEGER NOT NULL DEFAULT 0 CHECK (compact_script IN (0, 1)),
    cuisine TEXT,
    region TEXT,
    variant TEXT,
    default_serving_grams INTEGER NOT NULL CHECK (default_serving_grams > 0),
    quality_tier TEXT NOT NULL CHECK (quality_tier IN ('A', 'B'))
);
CREATE INDEX recipe_name_lookup ON recipes(normalized_name);
CREATE INDEX recipe_contained_lookup ON recipes(first_token);
CREATE INDEX recipe_compact_lookup ON recipes(compact_script) WHERE compact_script = 1;

CREATE TABLE recipe_aliases (
    recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    alias TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    first_token TEXT NOT NULL,
    compact_script INTEGER NOT NULL DEFAULT 0 CHECK (compact_script IN (0, 1)),
    language_code TEXT,
    locale_identifier TEXT,
    source TEXT NOT NULL,
    confidence TEXT NOT NULL,
    UNIQUE (recipe_id, normalized_alias, language_code, locale_identifier)
);
CREATE INDEX recipe_alias_lookup ON recipe_aliases(normalized_alias);
CREATE INDEX recipe_alias_contained_lookup ON recipe_aliases(first_token);
CREATE INDEX recipe_alias_compact_lookup ON recipe_aliases(compact_script) WHERE compact_script = 1;

CREATE TABLE ingredients (
    id TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    nutrition_lookup_name TEXT NOT NULL UNIQUE,
    normalized_nutrition_lookup_name TEXT NOT NULL UNIQUE
);
CREATE INDEX ingredient_name_lookup ON ingredients(normalized_name);

CREATE TABLE ingredient_aliases (
    ingredient_id TEXT NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
    alias TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    language_code TEXT,
    locale_identifier TEXT,
    source TEXT NOT NULL,
    confidence TEXT NOT NULL,
    UNIQUE (ingredient_id, normalized_alias, language_code, locale_identifier)
);
CREATE INDEX ingredient_alias_lookup ON ingredient_aliases(normalized_alias);

CREATE TABLE recipe_ingredients (
    recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    ingredient_id TEXT NOT NULL REFERENCES ingredients(id),
    position INTEGER NOT NULL CHECK (position > 0),
    ratio REAL NOT NULL CHECK (ratio > 0 AND ratio <= 1),
    source_grams REAL NOT NULL CHECK (source_grams > 0),
    PRIMARY KEY (recipe_id, ingredient_id),
    UNIQUE (recipe_id, position)
);

CREATE TABLE recipe_provenance (
    recipe_id TEXT PRIMARY KEY REFERENCES recipes(id) ON DELETE CASCADE,
    source TEXT NOT NULL,
    source_record_id TEXT NOT NULL,
    source_url TEXT NOT NULL,
    source_license TEXT NOT NULL,
    import_version TEXT NOT NULL,
    import_date TEXT NOT NULL,
    confidence TEXT NOT NULL,
    verification_status TEXT NOT NULL
);
CREATE INDEX recipe_provenance_source ON recipe_provenance(source, source_record_id);

CREATE TABLE ingredient_nutrition (
    ingredient_id TEXT PRIMARY KEY REFERENCES ingredients(id) ON DELETE CASCADE,
    kcal_per_100g REAL NOT NULL CHECK (kcal_per_100g >= 0 AND kcal_per_100g <= 1000),
    protein_g REAL,
    fat_g REAL,
    carbohydrate_g REAL,
    fiber_g REAL,
    prepared_state TEXT NOT NULL,
    source TEXT NOT NULL,
    source_record_id TEXT NOT NULL,
    source_url TEXT NOT NULL,
    source_license TEXT NOT NULL,
    import_version TEXT NOT NULL,
    import_date TEXT NOT NULL,
    confidence TEXT NOT NULL,
    verification_status TEXT NOT NULL
);
"""


def _deduplicate_aliases(recipes: list[ImportedRecipe]) -> dict[str, list[ImportedAlias]]:
    claims: dict[tuple[str, str | None, str | None], set[str]] = defaultdict(set)
    per_recipe: dict[str, list[ImportedAlias]] = defaultdict(list)
    for recipe in recipes:
        aliases = list(recipe.aliases)
        parts = [part.strip() for part in recipe.canonical_name.split(",") if part.strip()]
        if len(parts) >= 2:
            aliases.append(ImportedAlias(
                alias=f"{parts[0]}, {parts[1]}",
                language_code="en",
                locale_identifier="en-US",
                provenance=recipe.provenance,
            ))
        for alias in aliases:
            normalized = normalize_name(alias.alias)
            if normalized:
                claims[(normalized, alias.language_code, alias.locale_identifier)].add(recipe.id)
                per_recipe[recipe.id].append(alias)

    result: dict[str, list[ImportedAlias]] = defaultdict(list)
    for recipe_id, aliases in per_recipe.items():
        seen: set[tuple[str, str | None, str | None]] = set()
        for alias in aliases:
            key = (normalize_name(alias.alias), alias.language_code, alias.locale_identifier)
            if key in seen or len(claims[key]) != 1:
                continue
            seen.add(key)
            result[recipe_id].append(alias)
    return result


def _merge(datasets: list[ImportedDataset]) -> tuple[dict[str, ImportedIngredient], list[ImportedRecipe]]:
    ingredients: dict[str, ImportedIngredient] = {}
    recipes: list[ImportedRecipe] = []
    recipe_ids: set[str] = set()
    names: set[str] = set()
    for dataset in datasets:
        for ingredient_id, ingredient in dataset.ingredients.items():
            existing = ingredients.get(ingredient_id)
            if existing and existing != ingredient:
                raise ValueError(f"conflicting ingredient identity: {ingredient_id}")
            ingredients[ingredient_id] = ingredient
        for recipe in dataset.recipes:
            normalized = normalize_name(recipe.canonical_name)
            if recipe.id in recipe_ids:
                raise ValueError(f"duplicate recipe ID: {recipe.id}")
            if normalized in names:
                dataset.reject("duplicate_canonical_name")
                continue
            recipe_ids.add(recipe.id)
            names.add(normalized)
            recipes.append(recipe)
    return ingredients, recipes


def _insert(database: sqlite3.Connection, ingredients: dict[str, ImportedIngredient], recipes: list[ImportedRecipe]) -> None:
    aliases = _deduplicate_aliases(recipes)
    for ingredient in sorted(ingredients.values(), key=lambda item: item.id):
        if ingredient.nutrition is None or ingredient.nutrition.provenance is None:
            raise ValueError(f"ingredient lacks nutrition provenance: {ingredient.id}")
        normalized_name = normalize_name(ingredient.canonical_name)
        normalized_lookup = normalize_name(ingredient.nutrition_lookup_name)
        if not normalized_name or not normalized_lookup:
            raise ValueError(f"ingredient has empty normalized name: {ingredient.id}")
        database.execute(
            "INSERT INTO ingredients VALUES (?, ?, ?, ?, ?)",
            (ingredient.id, ingredient.canonical_name, normalized_name, ingredient.nutrition_lookup_name, normalized_lookup),
        )
        nutrition = ingredient.nutrition
        provenance = nutrition.provenance
        database.execute(
            "INSERT INTO ingredient_nutrition VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                ingredient.id, nutrition.kcal_per_100g, nutrition.protein_g, nutrition.fat_g,
                nutrition.carbohydrate_g, nutrition.fiber_g, nutrition.prepared_state,
                provenance.source, provenance.record_id, provenance.url, provenance.license,
                provenance.import_version, provenance.import_date, provenance.confidence,
                provenance.verification_status,
            ),
        )
        seen_aliases: set[tuple[str, str | None, str | None]] = set()
        for alias in ingredient.aliases:
            normalized = normalize_name(alias.alias)
            key = (normalized, alias.language_code, alias.locale_identifier)
            if not normalized or key in seen_aliases:
                continue
            seen_aliases.add(key)
            provenance = alias.provenance or nutrition.provenance
            database.execute(
                "INSERT INTO ingredient_aliases VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    ingredient.id, alias.alias, normalized, alias.language_code, alias.locale_identifier,
                    provenance.source, provenance.confidence,
                ),
            )

    for recipe in sorted(recipes, key=lambda item: item.id):
        normalized = normalize_name(recipe.canonical_name)
        first_token = normalized.split()[0]
        database.execute(
            "INSERT INTO recipes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                recipe.id, recipe.canonical_name, normalized, first_token, int(is_compact_script(normalized)),
                recipe.cuisine, recipe.region, recipe.variant, recipe.default_serving_grams, recipe.quality_tier,
            ),
        )
        provenance = recipe.provenance
        database.execute(
            "INSERT INTO recipe_provenance VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                recipe.id, provenance.source, provenance.record_id, provenance.url, provenance.license,
                provenance.import_version, provenance.import_date, provenance.confidence,
                provenance.verification_status,
            ),
        )
        total_grams = sum(item.grams for item in recipe.ingredients)
        if total_grams <= 0:
            raise ValueError(f"recipe has non-positive mass: {recipe.id}")
        ratios = [item.grams / total_grams for item in recipe.ingredients]
        ratios[-1] += 1.0 - sum(ratios)
        for position, (item, ratio) in enumerate(zip(recipe.ingredients, ratios), start=1):
            if item.ingredient_id not in ingredients:
                raise ValueError(f"recipe references unknown ingredient: {recipe.id}/{item.ingredient_id}")
            database.execute(
                "INSERT INTO recipe_ingredients VALUES (?, ?, ?, ?, ?)",
                (recipe.id, item.ingredient_id, position, ratio, item.grams),
            )
        for alias in aliases[recipe.id]:
            normalized_alias = normalize_name(alias.alias)
            first_alias_token = normalized_alias.split()[0]
            provenance = alias.provenance or recipe.provenance
            database.execute(
                "INSERT INTO recipe_aliases VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    recipe.id, alias.alias, normalized_alias, first_alias_token,
                    int(is_compact_script(normalized_alias)), alias.language_code, alias.locale_identifier,
                    provenance.source, provenance.confidence,
                ),
            )


def _validate(database: sqlite3.Connection) -> dict:
    checks = {
        "foreign_keys": "SELECT COUNT(*) FROM pragma_foreign_key_check",
        "invalid_ratios": "SELECT COUNT(*) FROM (SELECT recipe_id FROM recipe_ingredients GROUP BY recipe_id HAVING abs(sum(ratio)-1.0)>0.000001)",
        "recipes_without_components": "SELECT COUNT(*) FROM recipes r WHERE NOT EXISTS (SELECT 1 FROM recipe_ingredients ri WHERE ri.recipe_id=r.id)",
        "recipes_without_provenance": "SELECT COUNT(*) FROM recipes r WHERE NOT EXISTS (SELECT 1 FROM recipe_provenance p WHERE p.recipe_id=r.id)",
        "ingredients_without_nutrition": "SELECT COUNT(*) FROM ingredients i WHERE NOT EXISTS (SELECT 1 FROM ingredient_nutrition n WHERE n.ingredient_id=i.id)",
        "empty_aliases": "SELECT (SELECT COUNT(*) FROM recipe_aliases WHERE normalized_alias='') + (SELECT COUNT(*) FROM ingredient_aliases WHERE normalized_alias='')",
        "ambiguous_recipe_aliases": "SELECT COUNT(*) FROM (SELECT normalized_alias, language_code, locale_identifier FROM recipe_aliases GROUP BY normalized_alias, language_code, locale_identifier HAVING COUNT(DISTINCT recipe_id)>1)",
        "invalid_kcal": "SELECT COUNT(*) FROM ingredient_nutrition WHERE kcal_per_100g<0 OR kcal_per_100g>1000",
        "duplicate_canonical_ingredient_names": "SELECT COUNT(*) FROM (SELECT normalized_name FROM ingredients GROUP BY normalized_name HAVING COUNT(*)>1)",
    }
    results = {name: database.execute(sql).fetchone()[0] for name, sql in checks.items()}
    failures = {name: count for name, count in results.items() if count}
    if failures:
        raise ValueError(f"database validation failed: {failures}")
    return results


def _statistics(database: sqlite3.Connection) -> dict:
    scalar = lambda sql: database.execute(sql).fetchone()[0]
    return {
        "recipes": scalar("SELECT COUNT(*) FROM recipes"),
        "ingredients": scalar("SELECT COUNT(*) FROM ingredients"),
        "recipe_aliases": scalar("SELECT COUNT(*) FROM recipe_aliases"),
        "ingredient_aliases": scalar("SELECT COUNT(*) FROM ingredient_aliases"),
        "languages": scalar("SELECT COUNT(DISTINCT language_code) FROM recipe_aliases WHERE language_code IS NOT NULL"),
        "cuisines": [row[0] for row in database.execute("SELECT DISTINCT cuisine FROM recipes WHERE cuisine IS NOT NULL ORDER BY cuisine")],
        "regions": [row[0] for row in database.execute("SELECT DISTINCT region FROM recipes WHERE region IS NOT NULL ORDER BY region")],
        "nutrition_coverage_percent": round(100.0 * scalar("SELECT COUNT(*) FROM ingredient_nutrition") / scalar("SELECT COUNT(*) FROM ingredients"), 2),
        "quality_tiers": dict(database.execute("SELECT quality_tier, COUNT(*) FROM recipes GROUP BY quality_tier")),
    }


def build(repository: Path) -> dict:
    manual_dataset = manual.load(
        repository / "DataSources/manual/seed.sql",
        repository / "DataSources/manual/seed_nutrition.json",
    )
    reserved_names = {normalize_name(recipe.canonical_name) for recipe in manual_dataset.recipes}
    reserved_names.update(normalize_name(alias.alias) for recipe in manual_dataset.recipes for alias in recipe.aliases)
    usda_dataset = usda.load(
        repository / "DataSources/usda/FoodData_Central_survey_food_json_2024-10-31.zip",
        repository / "DataSources/usda/FoodData_Central_sr_legacy_food_json_2018-04.zip",
        reserved_names,
        {
            normalize_name(ingredient.canonical_name): ingredient.id
            for ingredient in manual_dataset.ingredients.values()
        },
    )
    wikidata_dataset, wikidata_aliases = wikidata.load_aliases(
        repository / "DataSources/wikidata/entities.json"
    )
    recipes_by_id = {
        recipe.id: recipe
        for dataset in (manual_dataset, usda_dataset)
        for recipe in dataset.recipes
    }
    for recipe_id, aliases in wikidata_aliases.items():
        recipe = recipes_by_id.get(recipe_id)
        if recipe is None:
            wikidata_dataset.reject("mapped_recipe_missing")
            continue
        recipe.aliases.extend(aliases)
    datasets = [manual_dataset, usda_dataset, wikidata_dataset]
    ingredients, recipes = _merge(datasets)

    output_database = repository / "Sources/CalorieEstimator/Resources/Recipes.sqlite3"
    output_sql = repository / "Data/recipes.sql"
    output_report = repository / "Data/Reports/food_database_build.json"
    output_database.parent.mkdir(parents=True, exist_ok=True)
    output_sql.parent.mkdir(parents=True, exist_ok=True)
    output_report.parent.mkdir(parents=True, exist_ok=True)

    file_descriptor, temporary_name = tempfile.mkstemp(prefix="calorie-estimator-recipes-", suffix=".sqlite3")
    os.close(file_descriptor)
    temporary = Path(temporary_name)
    try:
        database = sqlite3.connect(temporary)
        database.executescript(SCHEMA)
        with database:
            _insert(database, ingredients, recipes)
        validation = _validate(database)
        statistics = _statistics(database)
        database.execute("ANALYZE")
        database.execute("VACUUM")
        database.commit()
        dump = "\n".join(database.iterdump()) + "\n"
        database.close()
        output_sql.write_text(dump, encoding="utf-8")
        os.replace(temporary, output_database)
    finally:
        if temporary.exists():
            temporary.unlink()

    statistics["database_bytes"] = output_database.stat().st_size
    statistics["sources"] = {
        dataset.source: {
            "discovered": dataset.discovered,
            "accepted": len(dataset.recipes),
            "accepted_aliases": dataset.accepted_aliases,
            "rejected": sum(dataset.rejected.values()),
            "rejection_reasons": dict(sorted(dataset.rejected.items())),
        }
        for dataset in datasets
    }
    report = {
        "pipeline_version": 1,
        "generated_on": "2026-09-26",
        "baseline": {
            "recipes": 16,
            "ingredients": 46,
            "recipe_aliases": 38,
            "ingredient_aliases": 11,
            "database_bytes": 53248,
        },
        "result": statistics,
        "validation": validation,
        "commands": ["Scripts/build_recipe_database.sh", "swift test"],
    }
    output_report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return report
