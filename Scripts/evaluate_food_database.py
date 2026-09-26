#!/usr/bin/env python3
"""Deterministic, offline quality audit for the bundled recipe database.

This script intentionally does not invoke FoundationModels or mutate the database.
It writes reproducible benchmark ground truth and database-quality findings under
Data/Reports. A separate Swift test harness appends live public-API results.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import difflib
import hashlib
import json
import math
import re
import sqlite3
import statistics
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "Sources/CalorieEstimator/Resources/Recipes.sqlite3"
REPORT_DIR = ROOT / "Data/Reports"
JSON_PATH = REPORT_DIR / "database_evaluation.json"
MD_PATH = REPORT_DIR / "database_evaluation.md"

MANUAL_SOURCE = "CalorieEstimator manually curated seed"
USDA_SOURCE = "USDA FoodData Central FNDDS"

SURVEY_RE = re.compile(
    r"\b(?:nfs|ns as to|not specified|unspecified|lean (?:only|and fat) eaten|"
    r"fat eaten|no added fat|fat added|including carrots|excluding carrots|"
    r"frozen meal|school|fast food|restaurant|ready[- ]to[- ]heat|"
    r"from restaurant|type unknown|various types|with or without)\b",
    re.I,
)

CATEGORY_RULES = [
    ("rice dishes", re.compile(r"\b(?:rice|biryani|paella|jambalaya|risotto)\b", re.I)),
    ("pasta/noodles", re.compile(r"\b(?:pasta|spaghetti|noodle|ramen|lasagna|macaroni|chow mein|pad thai)\b", re.I)),
    ("soups/stews", re.compile(r"\b(?:soup|stew|chowder|gumbo|borscht|pho)\b", re.I)),
    ("meat dishes", re.compile(r"\b(?:beef|pork|chicken|turkey|lamb|steak|meat)\b", re.I)),
    ("seafood", re.compile(r"\b(?:fish|shrimp|crab|lobster|salmon|tuna|seafood|clam)\b", re.I)),
    ("breakfast", re.compile(r"\b(?:breakfast|pancake|waffle|french toast|egg)\b", re.I)),
    ("sandwiches", re.compile(r"\b(?:sandwich|burger|sub|taco|burrito)\b", re.I)),
    ("curries", re.compile(r"\bcurr(?:y|ies)\b", re.I)),
    ("dumplings", re.compile(r"\b(?:dumpling|wonton|pot sticker)\b", re.I)),
    ("salads", re.compile(r"\bsalad\b", re.I)),
    ("desserts", re.compile(r"\b(?:cake|pie|tiramisu|cookie|pudding|dessert|beignet|donut|ice cream)\b", re.I)),
]


BASE_CASES: list[dict[str, Any]] = [
    # Original curated seed recipes; localized lookups are exact trusted aliases.
    {"id": "base-01", "input": "200 gram tavuklu pilav", "lookup": "tavuklu pilav", "language": "tr", "category": "rice dishes", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "tr.tavuklu_pilav.default"},
    {"id": "base-02", "input": "200 Gramm Spaghetti alla carbonara", "lookup": "Spaghetti alla carbonara", "language": "de", "category": "pasta/noodles", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "it.spaghetti_carbonara.roman"},
    {"id": "base-03", "input": "비빔밥 200그램", "lookup": "비빔밥", "language": "ko", "category": "rice dishes", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "kr.bibimbap.default"},
    {"id": "base-04", "input": "200 граммов борща", "lookup": "борщ", "language": "ru", "category": "soups/stews", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "ru.borscht.default"},
    {"id": "base-05", "input": "ラーメン200グラム", "lookup": "ラーメン", "language": "ja", "category": "pasta/noodles", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "jp.ramen.shoyu"},
    {"id": "base-06", "input": "200 gramos de paella de marisco", "lookup": "paella de marisco", "language": "es", "category": "rice dishes", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "es.paella.seafood"},
    {"id": "base-07", "input": "200 ग्राम चिकन बिरयानी", "lookup": "चिकन बिरयानी", "language": "hi", "category": "rice dishes", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "in.chicken_biryani.default"},
    {"id": "base-08", "input": "200g beef pho", "lookup": "beef pho", "language": "en", "category": "soups/stews", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "vn.pho.beef"},
    {"id": "base-09", "input": "200g shrimp pad thai", "lookup": "shrimp pad thai", "language": "en", "category": "pasta/noodles", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "th.pad_thai.shrimp"},
    {"id": "base-10", "input": "200 grammes de ratatouille", "lookup": "ratatouille", "language": "fr", "category": "stews", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "fr.ratatouille.default"},
    {"id": "base-11", "input": "200g pork schnitzel", "lookup": "pork schnitzel", "language": "en", "category": "meat dishes", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "de.schnitzel.pork"},
    {"id": "base-12", "input": "200 غرام حمص", "lookup": "حمص", "language": "ar", "category": "dips", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "me.hummus.default"},
    {"id": "base-13", "input": "200g beef taco", "lookup": "beef taco", "language": "en", "category": "sandwiches", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "mx.beef_taco.default"},
    {"id": "base-14", "input": "200克蛋炒饭", "lookup": "蛋炒饭", "language": "zh", "category": "rice dishes", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "cn.fried_rice.egg"},
    {"id": "base-15", "input": "200 grammi di carbonara", "lookup": "carbonara", "language": "it", "category": "pasta/noodles", "cohort": "curated_seed", "grams": 200, "expected_recipe_id": "it.spaghetti_carbonara.roman"},

    # Imported FNDDS recipes, deliberately spanning common and survey-style variants.
    {"id": "base-16", "input": "200g falafel", "lookup": "falafel", "language": "en", "category": "meatless dishes", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.falafel.fndds_41209000"},
    {"id": "base-17", "input": "200g sushi", "lookup": "sushi", "language": "en", "category": "seafood", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.sushi_nfs.fndds_58151100"},
    {"id": "base-18", "input": "200g beef curry", "lookup": "beef curry", "language": "en", "category": "curries", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.beef_curry.fndds_27116100"},
    {"id": "base-19", "input": "200g chicken curry", "lookup": "chicken curry", "language": "en", "category": "curries", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.chicken_curry.fndds_27146150"},
    {"id": "base-20", "input": "200g fish curry", "lookup": "fish curry", "language": "en", "category": "curries", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.fish_curry.fndds_27150320"},
    {"id": "base-21", "input": "200g lentil curry", "lookup": "lentil curry", "language": "en", "category": "curries", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.lentil_curry.fndds_41311030"},
    {"id": "base-22", "input": "200g vegetable curry", "lookup": "vegetable curry", "language": "en", "category": "curries", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.vegetable_curry.fndds_75440600"},
    {"id": "base-23", "input": "200g beef enchilada", "lookup": "enchilada, beef", "language": "en", "category": "meat dishes", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.enchilada_beef.fndds_58102810"},
    {"id": "base-24", "input": "200g chicken enchilada", "lookup": "enchilada, chicken", "language": "en", "category": "meat dishes", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.enchilada_chicken.fndds_58102830"},
    {"id": "base-25", "input": "200g meatless enchilada", "lookup": "enchilada, no meat", "language": "en", "category": "meatless dishes", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.enchilada_no_meat.fndds_58102840"},
    {"id": "base-26", "input": "200g homemade meat lasagna", "lookup": "lasagna with meat, home recipe", "language": "en", "category": "pasta/noodles", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.lasagna_with_meat_home_recipe.fndds_58130015"},
    {"id": "base-27", "input": "200g vegetable lasagna", "lookup": "lasagna, meatless, with vegetables", "language": "en", "category": "pasta/noodles", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.lasagna_meatless_with_vegetables.fndds_58130320"},
    {"id": "base-28", "input": "200g New England clam chowder", "lookup": "soup, New England clam chowder", "language": "en", "category": "soups/stews", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.soup_new_england_clam_chowder.fndds_28355110"},
    {"id": "base-29", "input": "200g gumbo with rice", "lookup": "gumbo with rice", "language": "en", "category": "soups/stews", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.gumbo_with_rice.fndds_27363000"},
    {"id": "base-30", "input": "200g jambalaya with meat and rice", "lookup": "jambalaya with meat and rice", "language": "en", "category": "rice dishes", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.jambalaya_with_meat_and_rice.fndds_27363100"},
    {"id": "base-31", "input": "200g chicken and dumplings", "lookup": "chicken or turkey with dumplings", "language": "en", "category": "dumplings", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.chicken_or_turkey_with_dumplings.fndds_27246100"},
    {"id": "base-32", "input": "200g plain French toast", "lookup": "French toast, plain", "language": "en", "category": "breakfast", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.french_toast_plain.fndds_55301000"},
    {"id": "base-33", "input": "200g plain pancakes", "lookup": "pancakes, plain", "language": "en", "category": "breakfast", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.pancakes_plain.fndds_55101000"},
    {"id": "base-34", "input": "200g club sandwich on wheat", "lookup": "club sandwich on wheat", "language": "en", "category": "sandwiches", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.club_sandwich_on_wheat.fndds_27540125"},
    {"id": "base-35", "input": "200g tiramisu", "lookup": "tiramisu", "language": "en", "category": "desserts", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.tiramisu.fndds_13252600"},
    {"id": "base-36", "input": "200g black bean salad", "lookup": "black bean salad", "language": "en", "category": "salads", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.black_bean_salad.fndds_41203030"},
    {"id": "base-37", "input": "200g falafel sandwich", "lookup": "falafel sandwich", "language": "en", "category": "sandwiches", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.falafel_sandwich.fndds_41901030"},
    {"id": "base-38", "input": "200g chicken pad thai", "lookup": "Pad Thai with chicken", "language": "en", "category": "pasta/noodles", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.pad_thai_with_chicken.fndds_58137230"},
    {"id": "base-39", "input": "200g California sushi roll", "lookup": "sushi roll, California", "language": "en", "category": "seafood", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.sushi_roll_california.fndds_58151180"},
    {"id": "base-40", "input": "200g beignet", "lookup": "beignet", "language": "en", "category": "desserts", "cohort": "imported_usda", "grams": 200, "expected_recipe_id": "global.beignet.fndds_53520510"},

    # Intentional fallback controls. The first two should stop at local nutrition;
    # the remaining three deliberately exercise the semantic fallback chain.
    {"id": "base-41", "input": "200g banana", "lookup": "banana", "language": "en", "category": "single food", "cohort": "intentional_fallback", "grams": 200, "expected_recipe_id": None, "expected_provenance": "localNutrition"},
    {"id": "base-42", "input": "200g grilled chicken breast", "lookup": "grilled chicken breast", "language": "en", "category": "single food", "cohort": "intentional_fallback", "grams": 200, "expected_recipe_id": None, "expected_provenance": "localNutrition"},
    {"id": "base-43", "input": "200g tofu scramble", "lookup": "tofu scramble", "language": "en", "category": "breakfast", "cohort": "intentional_fallback", "grams": 200, "expected_recipe_id": None, "expected_provenance": "fallback_unspecified"},
    {"id": "base-44", "input": "200g chicken shawarma plate", "lookup": "chicken shawarma plate", "language": "en", "category": "meat dishes", "cohort": "intentional_fallback", "grams": 200, "expected_recipe_id": None, "expected_provenance": "fallback_unspecified"},
    {"id": "base-45", "input": "200g quinoa avocado bowl", "lookup": "quinoa avocado bowl", "language": "en", "category": "salads", "cohort": "intentional_fallback", "grams": 200, "expected_recipe_id": None, "expected_provenance": "fallback_unspecified"},
]


MODIFIER_CASES: list[dict[str, Any]] = [
    {"id": "mod-01", "input": "200 gram tavuklu pilav, tavuksuz", "language": "tr", "category": "rice dishes", "cohort": "curated_seed", "expected_recipe_id": "tr.tavuklu_pilav.default", "grams": 200, "operation": "remove", "ingredient_id": "chicken", "modifier_grams": None},
    {"id": "mod-02", "input": "200g spaghetti carbonara without bacon", "language": "en", "category": "pasta/noodles", "cohort": "curated_seed", "expected_recipe_id": "it.spaghetti_carbonara.roman", "grams": 200, "operation": "remove", "ingredient_id": "bacon", "modifier_grams": None},
    {"id": "mod-03", "input": "200 Gramm Bibimbap ohne Ei", "language": "de", "category": "rice dishes", "cohort": "curated_seed", "expected_recipe_id": "kr.bibimbap.default", "grams": 200, "operation": "remove", "ingredient_id": "egg", "modifier_grams": None},
    {"id": "mod-04", "input": "200 gramos de paella con 30 gramos extra de camarones", "language": "es", "category": "rice dishes", "cohort": "curated_seed", "expected_recipe_id": "es.paella.seafood", "grams": 230, "base_grams": 200, "operation": "increase", "ingredient_id": "shrimp", "modifier_grams": 30},
    {"id": "mod-05", "input": "200 grammes de ratatouille sans aubergine", "language": "fr", "category": "stews", "cohort": "curated_seed", "expected_recipe_id": "fr.ratatouille.default", "grams": 200, "operation": "remove", "ingredient_id": "eggplant", "modifier_grams": None},
    {"id": "mod-06", "input": "200 grammi di carbonara con 20 grammi di parmigiano in più", "language": "it", "category": "pasta/noodles", "cohort": "curated_seed", "expected_recipe_id": "it.spaghetti_carbonara.roman", "grams": 220, "base_grams": 200, "operation": "increase", "ingredient_id": "parmesan", "modifier_grams": 20},
    {"id": "mod-07", "input": "200 граммов борща без сметаны", "language": "ru", "category": "soups/stews", "cohort": "curated_seed", "expected_recipe_id": "ru.borscht.default", "grams": 200, "operation": "remove", "ingredient_id": "sour_cream", "modifier_grams": None},
    {"id": "mod-08", "input": "卵なしのラーメン200グラム", "language": "ja", "category": "pasta/noodles", "cohort": "curated_seed", "expected_recipe_id": "jp.ramen.shoyu", "grams": 200, "operation": "remove", "ingredient_id": "egg", "modifier_grams": None},
    {"id": "mod-09", "input": "계란 없이 비빔밥 200그램", "language": "ko", "category": "rice dishes", "cohort": "curated_seed", "expected_recipe_id": "kr.bibimbap.default", "grams": 200, "operation": "remove", "ingredient_id": "egg", "modifier_grams": None},
    {"id": "mod-10", "input": "不要鸡蛋的200克蛋炒饭", "language": "zh", "category": "rice dishes", "cohort": "curated_seed", "expected_recipe_id": "cn.fried_rice.egg", "grams": 200, "operation": "remove", "ingredient_id": "egg", "modifier_grams": None},
    {"id": "mod-11", "input": "200 غرام حمص بدون زيت زيتون", "language": "ar", "category": "dips", "cohort": "curated_seed", "expected_recipe_id": "me.hummus.default", "grams": 200, "operation": "remove", "ingredient_id": "olive_oil", "modifier_grams": None},
    {"id": "mod-12", "input": "200 ग्राम चिकन बिरयानी बिना दही", "language": "hi", "category": "rice dishes", "cohort": "curated_seed", "expected_recipe_id": "in.chicken_biryani.default", "grams": 200, "operation": "remove", "ingredient_id": "yogurt", "modifier_grams": None},
    {"id": "mod-13", "input": "200g cheeseburger with 25g extra cheese", "language": "en", "category": "sandwiches", "cohort": "curated_seed", "expected_recipe_id": "us.cheeseburger.default", "grams": 225, "base_grams": 200, "operation": "increase", "ingredient_id": "cheddar", "modifier_grams": 25},
    {"id": "mod-14", "input": "200g beef taco with less beef", "language": "en", "category": "sandwiches", "cohort": "curated_seed", "expected_recipe_id": "mx.beef_taco.default", "grams": 200, "operation": "decrease", "ingredient_id": "beef", "modifier_grams": None},
]


def rows(cur: sqlite3.Cursor, sql: str, params: Iterable[Any] = ()) -> list[dict[str, Any]]:
    cur.execute(sql, tuple(params))
    return [dict(row) for row in cur.fetchall()]


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * p
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def distribution(values: list[float], bins: list[tuple[str, float, float]]) -> list[dict[str, Any]]:
    return [
        {"bucket": label, "count": sum(low <= value < high for value in values)}
        for label, low, high in bins
    ]


def category_for(name: str) -> str:
    for category, pattern in CATEGORY_RULES:
        if pattern.search(name):
            return category
    return "other"


def usda_classification(name: str, ingredient_count: int) -> tuple[str, str]:
    """A documented name/metadata heuristic, not a cultural judgement."""
    if SURVEY_RE.search(name):
        return "survey-specific / overly specific", "contains FNDDS survey/preparation qualifier"
    words = re.findall(r"[A-Za-z]+", name)
    if ingredient_count < 2 or (len(words) <= 2 and category_for(name) == "other"):
        return "questionable", "resembles a single food/preparation rather than a reusable dish"
    if "," in name or re.search(r"\bwith(?:out)?\b|\bon (?:white|wheat)\b", name, re.I):
        return "useful prepared-food variant", "specific but reusable prepared-food variant"
    return "canonical dish", "concise dish identity"


def normalized_near_key(name: str) -> str:
    value = name.lower()
    value = SURVEY_RE.sub(" ", value)
    value = re.sub(r"\b(?:fresh|frozen|canned|cooked|plain|home recipe|reduced sodium|reduced fat)\b", " ", value)
    return " ".join(re.findall(r"[a-z0-9]+", value))


def enrich_benchmark(cur: sqlite3.Cursor) -> dict[str, Any]:
    cases = [dict(case) for case in BASE_CASES + MODIFIER_CASES]
    for case in cases:
        case["benchmark_group"] = "modifier" if case["id"].startswith("mod-") else "base"
        case["route"] = "phrase" if case["benchmark_group"] == "modifier" or case["cohort"] == "intentional_fallback" and case["id"] >= "base-43" else "explicitWeight"
        recipe_id = case.get("expected_recipe_id")
        if recipe_id:
            recipe = rows(cur, """
                SELECT r.id, r.canonical_name, r.default_serving_grams, r.quality_tier,
                       p.source, p.confidence, p.verification_status
                FROM recipes r JOIN recipe_provenance p ON p.recipe_id = r.id
                WHERE r.id = ?
            """, [recipe_id])
            if not recipe:
                raise RuntimeError(f"Benchmark recipe missing: {recipe_id}")
            ingredients = rows(cur, """
                SELECT i.id AS ingredient_id, i.canonical_name, ri.position, ri.ratio
                FROM recipe_ingredients ri JOIN ingredients i ON i.id = ri.ingredient_id
                WHERE ri.recipe_id = ? ORDER BY ri.position
            """, [recipe_id])
            case["expected_trusted_source"] = recipe[0]["source"]
            case["expected_provenance"] = "localRecipe"
            case["expected_base_ingredient_ids"] = [item["ingredient_id"] for item in ingredients]
            case["expected_default_serving_grams"] = recipe[0]["default_serving_grams"]
            case["expected_quality_tier"] = recipe[0]["quality_tier"]
        else:
            case.setdefault("expected_trusted_source", None)
            case.setdefault("expected_base_ingredient_ids", [])
            case.setdefault("expected_quality_tier", None)
        if case["benchmark_group"] == "modifier":
            case["expected_modifier"] = {
                "operation": case.pop("operation"),
                "ingredient_id": case.pop("ingredient_id"),
                "grams": case.pop("modifier_grams"),
            }
            case["expected_final_weight_grams"] = case.pop("grams")
        else:
            case["expected_modifier"] = None
            case["expected_final_weight_grams"] = case.pop("grams")
    return {
        "case_count": len(cases),
        "base_case_count": len(BASE_CASES),
        "modifier_case_count": len(MODIFIER_CASES),
        "languages": sorted({case["language"] for case in cases}),
        "cases": cases,
        "execution_policy": {
            "one_run_per_case": True,
            "maximum_foundationmodels_requests": 70,
            "retry_policy": "No automatic retries; up to two retries would be permitted for at most five nondeterministic failures, but are not scheduled.",
            "route_note": "Exact base identity cases use the public explicit-weight path, which resolves trusted recipes before model creation. Modifier and intentional semantic-fallback cases use the public phrase path.",
        },
    }


def analyze(cur: sqlite3.Cursor) -> dict[str, Any]:
    counts = rows(cur, """
        SELECT (SELECT COUNT(*) FROM recipes) AS recipes,
               (SELECT COUNT(*) FROM ingredients) AS ingredients,
               (SELECT COUNT(*) FROM recipe_aliases) AS recipe_aliases,
               (SELECT COUNT(*) FROM ingredient_aliases) AS ingredient_aliases
    """)[0]
    tier_counts = rows(cur, "SELECT quality_tier AS tier, COUNT(*) AS count FROM recipes GROUP BY quality_tier ORDER BY quality_tier")
    provenance_counts = rows(cur, "SELECT source, COUNT(*) AS count FROM recipe_provenance GROUP BY source ORDER BY count DESC, source")
    by_cuisine = rows(cur, "SELECT COALESCE(cuisine, '(unspecified)') AS value, COUNT(*) AS count FROM recipes GROUP BY cuisine ORDER BY count DESC, value")
    by_region = rows(cur, "SELECT COALESCE(region, '(unspecified)') AS value, COUNT(*) AS count FROM recipes GROUP BY region ORDER BY count DESC, value")
    by_source = provenance_counts

    recipe_metrics = rows(cur, """
        SELECT r.id, r.canonical_name, r.default_serving_grams, r.quality_tier,
               r.cuisine, r.region, p.source,
               COUNT(ri.ingredient_id) AS ingredient_count,
               SUM(ri.ratio * n.kcal_per_100g) AS kcal_per_100g,
               MAX(ri.ratio) AS max_ingredient_ratio
        FROM recipes r
        JOIN recipe_provenance p ON p.recipe_id = r.id
        JOIN recipe_ingredients ri ON ri.recipe_id = r.id
        JOIN ingredient_nutrition n ON n.ingredient_id = ri.ingredient_id
        GROUP BY r.id
    """)
    ingredient_counts = [float(row["ingredient_count"]) for row in recipe_metrics]
    kcal_values = [float(row["kcal_per_100g"]) for row in recipe_metrics]
    servings = [float(row["default_serving_grams"]) for row in recipe_metrics]

    stats = {
        "counts": counts,
        "provenance_counts": provenance_counts,
        "tier_counts": tier_counts,
        "recipes_by_cuisine": by_cuisine,
        "recipes_by_region": by_region,
        "recipes_by_source": by_source,
        "ingredient_count_distribution": distribution(ingredient_counts, [
            ("1", 1, 2), ("2-3", 2, 4), ("4-5", 4, 6), ("6-10", 6, 11),
            ("11-15", 11, 16), ("16-25", 16, 26), (">25", 26, math.inf),
        ]),
        "serving_size_distribution_grams": distribution(servings, [
            ("1-30", 1, 31), ("31-100", 31, 101), ("101-200", 101, 201),
            ("201-350", 201, 351), ("351-500", 351, 501), (">500", 501, math.inf),
        ]),
        "kcal_per_100g_distribution": distribution(kcal_values, [
            ("<25", 0, 25), ("25-74", 25, 75), ("75-149", 75, 150),
            ("150-249", 150, 250), ("250-399", 250, 400), ("400-699", 400, 700),
            (">=700", 700, math.inf),
        ]),
        "ingredient_count_percentiles": {
            "p10": percentile(ingredient_counts, .10),
            "p50": percentile(ingredient_counts, .50),
            "p90": percentile(ingredient_counts, .90),
            "median": statistics.median(ingredient_counts),
        },
        "kcal_per_100g_percentiles": {
            "p5": percentile(kcal_values, .05),
            "p50": percentile(kcal_values, .50),
            "p95": percentile(kcal_values, .95),
            "median": statistics.median(kcal_values),
        },
    }

    under_two = [row for row in recipe_metrics if row["ingredient_count"] < 2]
    over_25 = [row for row in recipe_metrics if row["ingredient_count"] > 25]
    low_kcal = sorted((row for row in recipe_metrics if row["kcal_per_100g"] < 15), key=lambda row: row["kcal_per_100g"])
    high_kcal = sorted((row for row in recipe_metrics if row["kcal_per_100g"] > 700), key=lambda row: -row["kcal_per_100g"])
    dominated = sorted((row for row in recipe_metrics if row["max_ingredient_ratio"] > .95), key=lambda row: -row["max_ingredient_ratio"])
    survey_names = [row for row in recipe_metrics if SURVEY_RE.search(row["canonical_name"])]

    exact_groups: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for row in recipe_metrics:
        exact_groups[normalized_near_key(row["canonical_name"])].append(row)
    near_duplicates: list[dict[str, Any]] = []
    for key, group in exact_groups.items():
        if key and len(group) > 1:
            near_duplicates.append({"normalized_identity": key, "records": [{"id": item["id"], "name": item["canonical_name"]} for item in group]})
    # Add only high-similarity pairs not already collapsed to the same heuristic key.
    by_prefix: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for row in recipe_metrics:
        key = normalized_near_key(row["canonical_name"])
        by_prefix[key[:12]].append(row)
    fuzzy_pairs = []
    for group in by_prefix.values():
        if len(group) > 80:
            group = group[:80]
        for index, left in enumerate(group):
            left_key = normalized_near_key(left["canonical_name"])
            for right in group[index + 1:]:
                right_key = normalized_near_key(right["canonical_name"])
                if left_key == right_key:
                    continue
                ratio = difflib.SequenceMatcher(None, left_key, right_key).ratio()
                if ratio >= .94:
                    fuzzy_pairs.append({"similarity": round(ratio, 3), "left": {"id": left["id"], "name": left["canonical_name"]}, "right": {"id": right["id"], "name": right["canonical_name"]}})
    fuzzy_pairs.sort(key=lambda pair: (-pair["similarity"], pair["left"]["name"], pair["right"]["name"]))

    def compact(items: list[dict[str, Any]], limit: int = 100) -> list[dict[str, Any]]:
        fields = ("id", "canonical_name", "source", "ingredient_count", "default_serving_grams", "kcal_per_100g", "max_ingredient_ratio")
        return [{field: item[field] for field in fields} for item in items[:limit]]

    suspicious = {
        "thresholds": {"implausibly_low_kcal_per_100g": 15, "implausibly_high_kcal_per_100g": 700, "dominant_ingredient_ratio": .95},
        "fewer_than_2_meaningful_ingredients": compact(under_two),
        "more_than_25_ingredients": compact(over_25),
        "implausibly_low_kcal_per_100g": compact(low_kcal),
        "implausibly_high_kcal_per_100g": compact(high_kcal),
        "dominated_by_one_ingredient_over_95_percent": compact(dominated),
        "survey_description_names": compact(survey_names),
        "duplicate_or_near_duplicate_identity_groups": near_duplicates[:100],
        "high_similarity_name_pairs": fuzzy_pairs[:100],
        "counts": {
            "fewer_than_2_ingredients": len(under_two),
            "more_than_25_ingredients": len(over_25),
            "low_kcal": len(low_kcal),
            "high_kcal": len(high_kcal),
            "dominated": len(dominated),
            "survey_description_names": len(survey_names),
            "near_duplicate_groups": len(near_duplicates),
            "high_similarity_pairs": len(fuzzy_pairs),
        },
    }

    ingredient_frequency = rows(cur, """
        SELECT i.id AS ingredient_id, i.canonical_name, COUNT(DISTINCT ri.recipe_id) AS recipe_count,
               COUNT(DISTINCT ia.rowid) AS alias_rows,
               COUNT(DISTINCT CASE WHEN ia.language_code IS NOT NULL AND ia.language_code != 'en' THEN ia.language_code END) AS multilingual_language_count
        FROM recipe_ingredients ri
        JOIN ingredients i ON i.id = ri.ingredient_id
        LEFT JOIN ingredient_aliases ia ON ia.ingredient_id = i.id
        GROUP BY i.id
        ORDER BY recipe_count DESC, i.id
    """)
    occurrence_total = sum(int(item["recipe_count"]) for item in ingredient_frequency)
    current_aliased_ids = {item["ingredient_id"] for item in ingredient_frequency if item["multilingual_language_count"] > 0}
    recipe_sets = rows(cur, "SELECT recipe_id, ingredient_id FROM recipe_ingredients ORDER BY recipe_id")
    ingredients_by_recipe: dict[str, set[str]] = collections.defaultdict(set)
    for item in recipe_sets:
        ingredients_by_recipe[item["recipe_id"]].add(item["ingredient_id"])
    alias_coverage = []
    for size in (0, 50, 100, 250, 500):
        added = {item["ingredient_id"] for item in ingredient_frequency[:size]}
        covered = current_aliased_ids | added
        covered_occurrences = sum(int(item["recipe_count"]) for item in ingredient_frequency if item["ingredient_id"] in covered)
        fully_covered = sum(recipe_ingredients <= covered for recipe_ingredients in ingredients_by_recipe.values())
        alias_coverage.append({
            "top_n_added": size,
            "covered_ingredient_ids": len(covered),
            "ingredient_occurrence_coverage_percent": round(100 * covered_occurrences / occurrence_total, 2),
            "fully_covered_recipe_percent": round(100 * fully_covered / len(ingredients_by_recipe), 2),
            "fully_covered_recipe_count": fully_covered,
        })

    usda_rows = [row for row in recipe_metrics if row["source"] == USDA_SOURCE]
    classified = []
    for row in usda_rows:
        label, reason = usda_classification(row["canonical_name"], row["ingredient_count"])
        classified.append({**row, "classification": label, "reason": reason, "category": category_for(row["canonical_name"])})
    by_category: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for item in classified:
        by_category[item["category"]].append(item)
    sample: list[dict[str, Any]] = []
    categories = sorted(by_category)
    # Stable stratification: round-robin categories, deterministic SHA256 order within each.
    for values in by_category.values():
        values.sort(key=lambda item: hashlib.sha256(item["id"].encode()).hexdigest())
    offsets = collections.Counter()
    while len(sample) < 120:
        progressed = False
        for category in categories:
            index = offsets[category]
            if index < len(by_category[category]):
                item = by_category[category][index]
                sample.append({key: item[key] for key in ("id", "canonical_name", "category", "classification", "reason", "ingredient_count", "kcal_per_100g")})
                offsets[category] += 1
                progressed = True
                if len(sample) == 120:
                    break
        if not progressed:
            break
    sample_counts = collections.Counter(item["classification"] for item in sample)
    population_counts = collections.Counter(item["classification"] for item in classified)
    usda_quality = {
        "method": "Heuristic classification from canonical names and ingredient counts only; no FoundationModels call. Stable 120-record category-stratified sample. Subjective labels should be reviewed manually before any deletion.",
        "population_classification_counts": dict(population_counts),
        "sample_size": len(sample),
        "sample_classification_counts": dict(sample_counts),
        "sample": sample,
        "representative_examples": {
            label: [{"id": item["id"], "name": item["canonical_name"], "reason": item["reason"]} for item in classified if item["classification"] == label][:8]
            for label in ("canonical dish", "useful prepared-food variant", "survey-specific / overly specific", "questionable")
        },
    }

    # Separate invariant/plausibility review of every trusted recipe.
    plausibility_records = []
    for row in recipe_metrics:
        signals = []
        if row["kcal_per_100g"] < 15 or row["kcal_per_100g"] > 700:
            signals.append("energy-density extreme")
        if row["max_ingredient_ratio"] > .95:
            signals.append("single ingredient exceeds 95%")
        if row["ingredient_count"] < 2 or row["ingredient_count"] > 25:
            signals.append("ingredient-count extreme")
        if SURVEY_RE.search(row["canonical_name"]):
            signals.append("survey-specific name")
        if row["default_serving_grams"] <= 10 or row["default_serving_grams"] > 700:
            signals.append("serving-size extreme")
        classification = "clearly suspicious" if any(signal in signals for signal in ("energy-density extreme", "single ingredient exceeds 95%")) else "questionable" if signals else "plausible"
        plausibility_records.append({"id": row["id"], "name": row["canonical_name"], "classification": classification, "signals": signals, "kcal_per_100g": round(row["kcal_per_100g"], 2), "ingredient_count": row["ingredient_count"]})
    plausibility_counts = collections.Counter(item["classification"] for item in plausibility_records)
    suspicious_ranked = sorted(
        (item for item in plausibility_records if item["classification"] != "plausible" and item["id"].startswith("global.")),
        key=lambda item: (-len(item["signals"]), item["classification"] != "clearly suspicious", item["name"]),
    )

    return {
        "statistics": stats,
        "suspicious_records": suspicious,
        "ingredient_alias_gap_analysis": {
            "definition": "Coverage assumes current multilingual ingredient aliases plus hypothetical aliases for the N most frequent IngredientIDs. Occurrence coverage counts recipe-ingredient rows; full-recipe coverage requires every IngredientID in the recipe to be covered.",
            "top_100_ingredients": ingredient_frequency[:100],
            "current_multilingual_ingredient_ids": sorted(current_aliased_ids),
            "coverage_scenarios": alias_coverage,
        },
        "usda_quality_analysis": usda_quality,
        "plausibility_review": {
            "method": "Deterministic screening, not cultural validation. Extreme thresholds and survey/serving-name heuristics identify records for human review.",
            "classification_counts": dict(plausibility_counts),
            "ten_most_suspicious_imported_recipes": suspicious_ranked[:10],
        },
    }


def fmt_pct(value: float | int | None) -> str:
    return "n/a" if value is None else f"{value:.2f}%"


def render_markdown(report: dict[str, Any]) -> str:
    stats = report["database_analysis"]["statistics"]
    suspicious = report["database_analysis"]["suspicious_records"]
    alias = report["database_analysis"]["ingredient_alias_gap_analysis"]
    usda = report["database_analysis"]["usda_quality_analysis"]
    plausibility = report["database_analysis"]["plausibility_review"]
    benchmark = report["benchmark"]
    live = report.get("live_evaluation")
    recommendations = report.get("recommended_next_actions", [
        "Add a non-destructive canonicality/reusability review state and exclude survey-specific variants from canonical recipe matching without deleting source records.",
        "Expand reviewed multilingual aliases for the most frequent 100–250 IngredientIDs; use the measured coverage table to choose the cutoff.",
        "Introduce deterministic family/group metadata for near-duplicate FNDDS variants so the resolver can prefer a canonical representative.",
        "Review energy, dominance, and serving-size extremes listed in the JSON report before enabling them as trusted canonical matches.",
        "Repeat this fixed benchmark after data curation, preserving the exact cases and one-run policy for comparable regression evidence.",
    ])
    counts = stats["counts"]
    lines = [
        "# CalorieEstimator database evaluation",
        "",
        f"Generated: {report['generated_at']}  ",
        "Scope: bundled offline database and fixed evaluation benchmark. No recipe rows, aliases, prompts, or runtime behavior were changed.",
        "",
        "## Executive summary",
        "",
        f"- Database: {counts['recipes']:,} recipes, {counts['ingredients']:,} ingredients, {counts['recipe_aliases']:,} recipe aliases, {counts['ingredient_aliases']:,} ingredient aliases.",
        f"- Tiers: " + ", ".join(f"Tier {item['tier']} {item['count']:,}" for item in stats["tier_counts"]) + ".",
        f"- Median recipe composition: {stats['ingredient_count_percentiles']['median']:.1f} ingredients; p10/p50/p90 = {stats['ingredient_count_percentiles']['p10']:.1f}/{stats['ingredient_count_percentiles']['p50']:.1f}/{stats['ingredient_count_percentiles']['p90']:.1f}.",
        f"- Median energy density: {stats['kcal_per_100g_percentiles']['median']:.1f} kcal/100g; p5/p50/p95 = {stats['kcal_per_100g_percentiles']['p5']:.1f}/{stats['kcal_per_100g_percentiles']['p50']:.1f}/{stats['kcal_per_100g_percentiles']['p95']:.1f}.",
        f"- Fixed benchmark: {benchmark['base_case_count']} base + {benchmark['modifier_case_count']} modifier = {benchmark['case_count']} cases across {len(benchmark['languages'])} languages.",
    ]
    if live:
        metrics = live.get("aggregate_metrics", {})
        lines.extend([
            f"- Live cases executed: {live.get('executed_case_count', 0)} of {metrics.get('total_benchmark_cases', benchmark['case_count'])}; successful: {metrics.get('successfully_completed_cases', 'n/a')}; exact FoundationModels requests: {live.get('foundationmodels_request_count', 'n/a')}.",
            f"- Trusted RecipeID hit rate: {fmt_pct(metrics.get('trusted_recipe_hit_rate_percent'))}; failures/timeouts/safety refusals: {fmt_pct(metrics.get('failure_timeout_safety_refusal_rate_percent'))}; batch-terminated before execution: {fmt_pct(metrics.get('not_executed_batch_terminated_rate_percent'))}; mass conservation: {fmt_pct(metrics.get('mass_conservation_pass_rate_percent'))}.",
        ])
    else:
        lines.append("- Live model run: not yet executed; deterministic findings and ground truth are complete.")

    lines.extend([
        "",
        "## Database statistics",
        "",
        "### Provenance and quality tiers",
        "",
        "| Source | Recipes |",
        "|---|---:|",
    ])
    lines.extend(f"| {item['source']} | {item['count']:,} |" for item in stats["provenance_counts"])
    lines.extend(["", "| Tier | Recipes |", "|---|---:|"])
    lines.extend(f"| {item['tier']} | {item['count']:,} |" for item in stats["tier_counts"])
    for title, key in (("Cuisine", "recipes_by_cuisine"), ("Region", "recipes_by_region")):
        lines.extend(["", f"### Recipes by {title.lower()}", "", f"| {title} | Recipes |", "|---|---:|"])
        lines.extend(f"| {item['value']} | {item['count']:,} |" for item in stats[key])
    for title, key in (("Ingredients per recipe", "ingredient_count_distribution"), ("Default serving grams", "serving_size_distribution_grams"), ("kcal per 100g", "kcal_per_100g_distribution")):
        lines.extend(["", f"### {title}", "", "| Bucket | Recipes |", "|---|---:|"])
        lines.extend(f"| {item['bucket']} | {item['count']:,} |" for item in stats[key])

    lines.extend([
        "",
        "## Suspicious-record screen",
        "",
        "These are deterministic review flags, not deletion recommendations.",
        "",
        "| Signal | Count |",
        "|---|---:|",
    ])
    lines.extend(f"| {key.replace('_', ' ')} | {value:,} |" for key, value in suspicious["counts"].items())
    lines.extend(["", "### Ten most suspicious imported recipes", "", "| Recipe | Classification | Signals | kcal/100g | Ingredients |", "|---|---|---|---:|---:|"])
    for item in plausibility["ten_most_suspicious_imported_recipes"]:
        lines.append(f"| `{item['id']}` — {item['name']} | {item['classification']} | {', '.join(item['signals'])} | {item['kcal_per_100g']:.1f} | {item['ingredient_count']} |")

    lines.extend([
        "",
        "## USDA/FNDDS canonical-dish quality",
        "",
        usda["method"],
        "",
        f"Sample size: **{usda['sample_size']}**.",
        "",
        "| Heuristic class | Sample count | Population count |",
        "|---|---:|---:|",
    ])
    labels = ("canonical dish", "useful prepared-food variant", "survey-specific / overly specific", "questionable")
    for label in labels:
        lines.append(f"| {label} | {usda['sample_classification_counts'].get(label, 0)} | {usda['population_classification_counts'].get(label, 0)} |")
    for label in labels:
        lines.extend(["", f"Representative **{label}** examples:"])
        for item in usda["representative_examples"][label][:5]:
            lines.append(f"- {item['name']} (`{item['id']}`) — {item['reason']}")

    lines.extend([
        "",
        "## Ingredient-alias gap analysis",
        "",
        alias["definition"],
        "",
        "| Hypothetical top-N alias expansion | Covered IngredientIDs | Ingredient occurrences covered | Trusted recipes fully covered |",
        "|---:|---:|---:|---:|",
    ])
    for item in alias["coverage_scenarios"]:
        lines.append(f"| {item['top_n_added']} | {item['covered_ingredient_ids']} | {item['ingredient_occurrence_coverage_percent']:.2f}% | {item['fully_covered_recipe_percent']:.2f}% ({item['fully_covered_recipe_count']:,}) |")
    lines.extend(["", "### Top 100 ingredients by recipe frequency", "", "| Rank | IngredientID | Name | Recipe occurrences | Existing aliases | Multilingual languages |", "|---:|---|---|---:|---:|---:|"])
    for rank, item in enumerate(alias["top_100_ingredients"], 1):
        lines.append(f"| {rank} | `{item['ingredient_id']}` | {item['canonical_name']} | {item['recipe_count']} | {item['alias_rows']} | {item['multilingual_language_count']} |")

    lines.extend([
        "",
        "## Benchmark definition and ground truth",
        "",
        benchmark["execution_policy"]["route_note"],
        "",
        "| ID | Input | Language | Cohort | Route | Expected RecipeID | Expected modifier |",
        "|---|---|---|---|---|---|---|",
    ])
    for case in benchmark["cases"]:
        modifier = case.get("expected_modifier")
        modifier_text = "—" if not modifier else f"{modifier['operation']} {modifier['ingredient_id']}" + (f" {modifier['grams']}g" if modifier['grams'] else "")
        lines.append(f"| {case['id']} | {case['input']} | {case['language']} | {case['cohort']} | {case['route']} | `{case.get('expected_recipe_id') or 'none'}` | {modifier_text} |")

    if live:
        metrics = live["aggregate_metrics"]
        lines.extend([
            "",
            "## Live public-API results",
            "",
            f"Executed {live['executed_case_count']} of {metrics['total_benchmark_cases']} cases; {metrics['successfully_completed_cases']} completed successfully. The remaining cases are retained as failures, timeouts, safety refusals, or not-executed outcomes after an earlier case terminated their predefined batch.",
            "",
            "| Metric | Result |",
            "|---|---:|",
            f"| Trusted RecipeID hit rate | {fmt_pct(metrics.get('trusted_recipe_hit_rate_percent'))} |",
            f"| localRecipe rate | {fmt_pct(metrics.get('localRecipe_rate_percent'))} |",
            f"| localNutrition rate | {fmt_pct(metrics.get('localNutrition_rate_percent'))} |",
            f"| modelAssistedRecipe rate | {fmt_pct(metrics.get('modelAssistedRecipe_rate_percent'))} |",
            f"| modelNutrition rate | {fmt_pct(metrics.get('modelNutrition_rate_percent'))} |",
            f"| Failure/timeout/safety-refusal rate | {fmt_pct(metrics.get('failure_timeout_safety_refusal_rate_percent'))} ({metrics.get('failure_timeout_safety_refusal_count', 0)}/{metrics['total_benchmark_cases']}) |",
            f"| Not executed after batch termination | {fmt_pct(metrics.get('not_executed_batch_terminated_rate_percent'))} ({metrics.get('not_executed_batch_terminated_count', 0)}/{metrics['total_benchmark_cases']}) |",
            f"| Overall non-success rate | {fmt_pct(metrics.get('overall_non_success_rate_percent'))} ({metrics.get('overall_non_success_count', 0)}/{metrics['total_benchmark_cases']}) |",
            f"| Mass-conservation pass rate | {fmt_pct(metrics.get('mass_conservation_pass_rate_percent'))} |",
            f"| Raw modifier accuracy among successful modifier parses | {fmt_pct(metrics.get('modifier_accuracy_percent'))} ({metrics.get('modifier_correct_count', 0)}/{metrics.get('modifier_successfully_evaluated_count', 0)}) |",
            f"| Product-semantic modifier accuracy (excluding mod-13 spec issue) | {fmt_pct(metrics.get('modifier_product_semantics_accuracy_percent'))} |",
            f"| Average / median / p95 case latency | {metrics.get('average_case_latency_ms', 0):.2f} / {metrics.get('median_case_latency_ms', 0):.2f} / {metrics.get('p95_case_latency_ms', 0):.2f} ms |",
            f"| FoundationModels requests | {metrics.get('foundationmodels_request_count', live['foundationmodels_request_count'])} |",
            f"| External watchdog terminations | {metrics.get('watchdog_terminations', 0)} |",
            f"| Batch hard-timeout terminations | {metrics.get('batch_hard_timeout_terminations', 0)} |",
            f"| Internal model-timeout batch stops | {metrics.get('internal_model_timeout_batch_stops', 0)} |",
            "",
            "### Results by language",
            "",
            "| Language | Cases | Successful | Recipe hits | Failure/timeout/refusal | Not executed | Modifier correct |",
            "|---|---:|---:|---:|---:|---:|---:|",
        ])
        for item in live.get("by_language", []):
            lines.append(f"| {item['language']} | {item['cases']} | {item['successful']} | {item['recipe_hits']} | {item['failures_timeouts_refusals']} | {item['not_executed']} | {item['modifier_correct']} |")
        lines.extend(["", "### Results by cohort", "", "| Cohort | Cases | Successful | Recipe hits | Failure/timeout/refusal | Not executed |", "|---|---:|---:|---:|---:|---:|"])
        for item in live.get("by_cohort", []):
            lines.append(f"| {item['cohort']} | {item['cases']} | {item['successful']} | {item['recipe_hits']} | {item['failures_timeouts_refusals']} | {item['not_executed']} |")
        lines.extend(["", "### Results by input script", "", "| Script | Cases | Successful | Recipe hits | Failure/timeout/refusal | Not executed |", "|---|---:|---:|---:|---:|---:|"])
        for item in live.get("by_script", []):
            lines.append(f"| {item['script']} | {item['cases']} | {item['successful']} | {item['recipe_hits']} | {item['failures_timeouts_refusals']} | {item['not_executed']} |")
        lines.extend(["", "### Provenance breakdown", "", "| Provenance | Count |", "|---|---:|"])
        for key, value in live.get("provenance_breakdown", {}).items():
            lines.append(f"| {key} | {value} |")
        lines.extend(["", "### Most common fallback/failure reasons"])
        for item in live.get("fallback_reasons", []):
            lines.append(f"- {item['reason']}: {item['count']}")
        lines.extend(["", "### Ten best-performing imported recipes"])
        for item in live.get("ten_best_imported", []):
            lines.append(f"- {item['input']} → `{item.get('actual_recipe_id')}`; {item.get('calories')} kcal for {item.get('total_grams')}g")
        special = live.get("special_analysis", {})
        if special:
            cheeseburger = special["mod_13_cheeseburger"]
            tofu = special["base_43_tofu_scramble"]
            lines.extend([
                "",
                "### Special-case analysis",
                "",
                f"- `mod-13` is an **{cheeseburger['classification']}**, not a product failure. Existing semantics say: {cheeseburger['documented_semantics']} Therefore the consistent final mass is **{cheeseburger['actual_final_grams']}g**, not the benchmark's {cheeseburger['benchmark_expected_final_grams']}g. {cheeseburger['evidence']}",
                f"- `base-43` is recorded exactly as a **{tofu['classification']}**: `{tofu['exact_error']}`. No workaround or prompt change was attempted.",
            ])

    lines.extend([
        "",
        "## Strengths",
        "",
        "- The database is internally relational: trusted recipes reference existing IngredientIDs and nutrition rows, with normalized ratios and explicit provenance.",
        "- The expansion adds broad prepared-food coverage across multiple dish categories, with deterministic energy calculation.",
        "- Recipe aliases cover 34 languages and several major non-Latin scripts for a small set of prominent dishes.",
        "- Stable RecipeID and IngredientID boundaries make invariant checking and regression benchmarking practical.",
        "",
        "## Weaknesses",
        "",
        "- FNDDS dominates the recipe population; many identities encode survey/preparation qualifiers rather than reusable canonical dishes.",
        "- Cuisine and region metadata are unspecified for most records.",
        "- Only 11 ingredient-alias rows exist, so multilingual ingredient-level modifier resolution is far behind recipe-level aliasing.",
        "- Many closely related survey variants create identity ambiguity and inflate apparent dish coverage.",
        "- Serving sizes inherited from FNDDS often describe a reference amount, not a natural meal serving.",
        "",
        "## Highest-value next actions",
        "",
    ])
    lines.extend(f"{index}. {recommendation}" for index, recommendation in enumerate(recommendations, 1))
    lines.extend([
        "",
        "## Artifacts",
        "",
        f"- `{JSON_PATH.relative_to(ROOT)}` — full statistics, raw benchmark ground truth/results, samples, and record-level flags.",
        f"- `{MD_PATH.relative_to(ROOT)}` — human-readable evaluation report.",
        "",
        "No production data or behavior was modified, and no commit was created.",
    ])
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preserve-live", action="store_true", help="Keep a prior live_evaluation section when regenerating deterministic analysis.")
    args = parser.parse_args()
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    previous_live = None
    if args.preserve_live and JSON_PATH.exists():
        previous_live = json.loads(JSON_PATH.read_text())["live_evaluation"]
    connection = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        cur = connection.cursor()
        report = {
            "schema_version": 1,
            "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "database_path": str(DB_PATH.relative_to(ROOT)),
            "database_sha256": hashlib.sha256(DB_PATH.read_bytes()).hexdigest(),
            "constraints": {
                "database_mutated": False,
                "prompts_tuned": False,
                "aliases_added": False,
                "external_recipe_sites_used": False,
                "committed": False,
            },
            "database_analysis": analyze(cur),
            "benchmark": enrich_benchmark(cur),
            "live_evaluation": previous_live,
        }
    finally:
        connection.close()
    JSON_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    MD_PATH.write_text(render_markdown(report))
    print(f"Wrote {JSON_PATH}")
    print(f"Wrote {MD_PATH}")


if __name__ == "__main__":
    main()
