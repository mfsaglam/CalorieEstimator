from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import unittest
from pathlib import Path


repository = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repository / "Scripts"))

from fooddb.normalize import normalize_ingredient_alias, normalize_name  # noqa: E402


class IngredientAliasPipelineTests(unittest.TestCase):
    database_path = repository / "Sources/CalorieEstimator/Resources/Recipes.sqlite3"

    def connection(self) -> sqlite3.Connection:
        return sqlite3.connect(f"file:{self.database_path}?mode=ro", uri=True)

    def test_existing_duplicate_prevention_uses_project_normalization(self) -> None:
        self.assertEqual(normalize_name("egg"), normalize_name("Egg"))
        self.assertEqual(normalize_name("egg"), normalize_name(" egg "))
        self.assertEqual(normalize_name("huile-d’olive"), normalize_name("huile d olive"))

        database = self.connection()
        duplicate_count = database.execute(
            """
            SELECT COUNT(*) FROM (
                SELECT ingredient_id, normalized_alias,
                       ifnull(language_code, ''), ifnull(locale_identifier, '')
                FROM ingredient_aliases
                GROUP BY ingredient_id, normalized_alias,
                         ifnull(language_code, ''), ifnull(locale_identifier, '')
                HAVING COUNT(*) > 1
            )
            """
        ).fetchone()[0]
        database.close()
        self.assertEqual(duplicate_count, 0)

    def test_cross_id_ambiguity_is_not_shipped(self) -> None:
        database = self.connection()
        ambiguous_count = database.execute(
            """
            SELECT COUNT(*) FROM (
                SELECT normalized_alias
                FROM ingredient_aliases
                GROUP BY normalized_alias
                HAVING COUNT(DISTINCT ingredient_id) > 1
            )
            """
        ).fetchone()[0]
        canonical_collision_count = database.execute(
            """
            SELECT COUNT(*)
            FROM ingredient_aliases aliases
            JOIN ingredients ON ingredients.normalized_name = aliases.normalized_alias
            WHERE ingredients.id <> aliases.ingredient_id
            """
        ).fetchone()[0]
        database.close()
        self.assertEqual(ambiguous_count, 0)
        self.assertEqual(canonical_collision_count, 0)

    def test_unicode_aliases_resolve_to_existing_stable_id(self) -> None:
        cases = [
            ("Zeytinyağı", "tr"),
            ("оливковое масло", "ru"),
            ("زيت الزيتون", "ar"),
            ("橄欖油", "zh"),
            ("オリーブ油", "ja"),
            ("올리브유", "ko"),
            ("जैतून का तेल", "hi"),
        ]
        database = self.connection()
        for alias, language in cases:
            rows = database.execute(
                """
                SELECT ingredient_id
                FROM ingredient_aliases
                WHERE normalized_alias = ? AND language_code = ?
                """,
                (normalize_ingredient_alias(alias), language),
            ).fetchall()
            self.assertEqual(rows, [("olive_oil",)], alias)
        database.close()

    def test_mapping_snapshot_contains_exactly_250_unique_existing_ids(self) -> None:
        payload = json.loads(
            (repository / "DataSources/wikidata/ingredient_mappings.json").read_text(encoding="utf-8")
        )
        selected = payload["selection"]["ingredients"]
        ids = [item["ingredient_id"] for item in selected]
        self.assertEqual(len(ids), 250)
        self.assertEqual(len(set(ids)), 250)
        self.assertEqual([item["rank"] for item in selected], list(range(1, 251)))

        database = self.connection()
        placeholders = ",".join("?" for _ in ids)
        existing = database.execute(
            f"SELECT COUNT(*) FROM ingredients WHERE id IN ({placeholders})",
            ids,
        ).fetchone()[0]
        database.close()
        self.assertEqual(existing, 250)

    def test_repeated_generation_is_byte_for_byte_deterministic(self) -> None:
        outputs = [
            repository / "Sources/CalorieEstimator/Resources/Recipes.sqlite3",
            repository / "Data/recipes.sql",
            repository / "Data/Reports/food_database_build.json",
            repository / "Data/Reports/ingredient_alias_enrichment.json",
            repository / "Data/Reports/ingredient_alias_review.json",
        ]
        environment = dict(os.environ)
        environment["PYTHONPYCACHEPREFIX"] = "/tmp/calorie-estimator-test-pycache"

        def build_and_hash() -> dict[str, str]:
            subprocess.run(
                [sys.executable, str(repository / "Scripts/generate_food_database.py")],
                cwd=repository,
                env=environment,
                check=True,
                stdout=subprocess.DEVNULL,
            )
            return {
                str(path.relative_to(repository)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in outputs
            }

        self.assertEqual(build_and_hash(), build_and_hash())


if __name__ == "__main__":
    unittest.main()
