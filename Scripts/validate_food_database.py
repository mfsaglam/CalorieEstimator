#!/usr/bin/env python3
from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

repository = Path(__file__).resolve().parent.parent
database_path = repository / "Sources/CalorieEstimator/Resources/Recipes.sqlite3"
database = sqlite3.connect(f"file:{database_path}?mode=ro", uri=True)

checks = {
    "foreign key errors": "SELECT COUNT(*) FROM pragma_foreign_key_check",
    "bad mass ratios": "SELECT COUNT(*) FROM (SELECT recipe_id FROM recipe_ingredients GROUP BY recipe_id HAVING abs(sum(ratio)-1)>0.000001)",
    "orphan aliases": "SELECT COUNT(*) FROM recipe_aliases a LEFT JOIN recipes r ON r.id=a.recipe_id WHERE r.id IS NULL",
    "trusted recipes missing provenance": "SELECT COUNT(*) FROM recipes r LEFT JOIN recipe_provenance p ON p.recipe_id=r.id WHERE p.recipe_id IS NULL",
    "recipe ingredients missing nutrition": "SELECT COUNT(*) FROM recipe_ingredients ri LEFT JOIN ingredient_nutrition n ON n.ingredient_id=ri.ingredient_id WHERE n.ingredient_id IS NULL",
    "invalid calories": "SELECT COUNT(*) FROM ingredient_nutrition WHERE kcal_per_100g<0 OR kcal_per_100g>1000",
    "duplicate canonical ingredient names": "SELECT COUNT(*) FROM (SELECT normalized_name FROM ingredients GROUP BY normalized_name HAVING COUNT(*)>1)",
    "ambiguous localized aliases": "SELECT COUNT(*) FROM (SELECT normalized_alias, language_code, locale_identifier FROM recipe_aliases GROUP BY normalized_alias, language_code, locale_identifier HAVING COUNT(DISTINCT recipe_id)>1)",
}
failures = []
for label, query in checks.items():
    count = database.execute(query).fetchone()[0]
    print(f"{label}: {count}")
    if count:
        failures.append(label)
database.close()
if failures:
    print("Validation failed: " + ", ".join(failures), file=sys.stderr)
    sys.exit(1)
print("Database validation passed")
