from __future__ import annotations

import json
import zipfile
from collections import defaultdict
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
from fooddb.normalize import normalize_name, prepared_state, stable_slug


ALLOWED_CATEGORIES = {
    "Bagels and English muffins", "Bean, pea, legume dishes", "Beans, peas, legumes",
    "Beef, excludes ground", "Biscuits, muffins, quick breads", "Burgers", "Burritos and tacos",
    "Cakes and pies", "Cheese sandwiches", "Chicken fillet sandwiches",
    "Chicken patties, nuggets and tenders", "Chicken, whole pieces", "Coleslaw, non-lettuce salads",
    "Cookies and brownies", "Deli and cured meat sandwiches", "Dips, gravies, other sauces",
    "Doughnuts, sweet rolls, pastries", "Egg rolls, dumplings, sushi", "Egg/breakfast sandwiches",
    "Eggs and omelets", "Fish", "Frankfurter sandwiches", "French fries and other fried white potatoes",
    "Fried rice and lo/chow mein", "Fried vegetables", "Gelatins, ices, sorbets",
    "Grits and other cooked cereals", "Ground beef", "Ice cream and frozen dairy desserts",
    "Lamb, goat, game", "Lettuce and lettuce salads", "Liver and organ meats",
    "Macaroni and cheese", "Mashed potatoes and white potato mixtures", "Meat and BBQ sandwiches",
    "Meat mixed dishes", "Nachos", "Oatmeal", "Other Mexican mixed dishes",
    "Other vegetables and combinations", "Pancakes, waffles, French toast",
    "Pasta mixed dishes, excludes macaroni and cheese", "Pasta sauces, tomato-based",
    "Pasta, noodles, cooked grains", "Peanut butter and jelly sandwiches", "Pizza", "Pork",
    "Poultry mixed dishes", "Pudding", "Ramen and Asian broth-based soups", "Rice mixed dishes",
    "Seafood mixed dishes", "Seafood sandwiches", "Shellfish", "Soups, broth-based",
    "Soups, cream-based", "Soy and meat-alternative products",
    "Stir-fry and soy-based sauce mixtures", "Turkey, duck, other poultry",
    "Turnovers and other grain-based items", "Vegetable dishes", "Vegetable sandwiches/burgers",
    "White potatoes, baked or boiled", "Yeast breads",
}

CUISINE_RULES = (
    (("arepa dominicana",), ("Dominican", "Dominican Republic")),
    (("pupusa",), ("Salvadoran", "El Salvador")),
    (("puerto rican",), ("Puerto Rican", "Puerto Rico")),
    (("empanada",), ("Latin American", None)),
    (("taco", "burrito", "enchilada", "tamale", "quesadilla", "nacho", "mexican"), ("Mexican", "Mexico")),
    (("pizza", "lasagna", "ravioli", "tortellini", "risotto", "cannoli", "italian"), ("Italian", "Italy")),
    (("chow mein", "lo mein", "chop suey", "wonton", "egg roll", "chinese"), ("Chinese", "China")),
    (("sushi", "tempura", "teriyaki", "miso", "japanese"), ("Japanese", "Japan")),
    (("kimchi", "bibimbap", "korean"), ("Korean", "Korea")),
    (("pad thai", "thai"), ("Thai", "Thailand")),
    (("pho", "vietnamese"), ("Vietnamese", "Vietnam")),
    (("biryani", "tandoori", "samosa", "indian"), ("Indian", "India")),
    (("hummus", "falafel", "tabbouleh", "middle eastern"), ("Middle Eastern", None)),
    (("shish kabob",), ("Eastern Mediterranean", None)),
    (("couscous",), ("North African", None)),
    (("gyro", "moussaka", "greek"), ("Greek", "Greece")),
    (("paella", "spanish"), ("Spanish", "Spain")),
    (("borscht", "russian"), ("Eastern European", None)),
    (("swedish meatball",), ("Nordic", "Sweden")),
    (("shepherd s pie",), ("British / Irish", None)),
    (("jerk", "jamaican", "caribbean"), ("Caribbean", None)),
    (("gumbo", "jambalaya", "cajun", "creole"), ("American", "United States")),
)


def _read_zip_json(path: Path) -> dict:
    with zipfile.ZipFile(path) as archive:
        names = [name for name in archive.namelist() if name.endswith(".json")]
        if len(names) != 1:
            raise ValueError(f"expected one JSON file in {path}")
        with archive.open(names[0]) as source:
            return json.load(source)


def _nutrient(food: dict, number: str) -> float | None:
    values = [
        item.get("amount")
        for item in food.get("foodNutrients", [])
        if item.get("nutrient", {}).get("number") == number and item.get("amount") is not None
    ]
    return float(values[0]) if values else None


def _serving_grams(food: dict) -> int:
    portions = sorted(food.get("foodPortions", []), key=lambda item: item.get("sequenceNumber", 9999))
    preferred = [
        portion for portion in portions
        if 10 <= float(portion.get("gramWeight") or 0) <= 1500
        and "quantity not specified" not in (portion.get("portionDescription") or "").lower()
    ]
    if not preferred:
        preferred = [portion for portion in portions if 1 <= float(portion.get("gramWeight") or 0) <= 2000]
    return max(1, int(round(float(preferred[0]["gramWeight"])))) if preferred else 100


def _cuisine(description: str) -> tuple[str | None, str | None]:
    normalized = normalize_name(description)
    for needles, result in CUISINE_RULES:
        if any(needle in normalized for needle in needles):
            return result
    return None, None


def load(
    survey_zip: Path,
    sr_zip: Path,
    reserved_names: set[str],
    stable_ingredient_ids: dict[str, str],
) -> ImportedDataset:
    dataset = ImportedDataset(source="usda_fndds_2021_2023")
    sr_foods = _read_zip_json(sr_zip)["SRLegacyFoods"]
    sr_by_code = {str(food["ndbNumber"]): food for food in sr_foods}
    survey_foods = _read_zip_json(survey_zip)["SurveyFoods"]
    survey_by_code = {str(food["foodCode"]): food for food in survey_foods}
    canonical_source_by_name: dict[str, tuple[str, str, dict]] = {}
    for code, source_food in sr_by_code.items():
        if _nutrient(source_food, "208") is not None:
            canonical_source_by_name[normalize_name(source_food["description"])] = ("sr", code, source_food)
    for code, source_food in survey_by_code.items():
        if _nutrient(source_food, "208") is not None:
            canonical_source_by_name.setdefault(
                normalize_name(source_food["description"]), ("fndds", code, source_food)
            )
    dataset.discovered = len(survey_foods)

    for food in sorted(survey_foods, key=lambda item: str(item.get("foodCode", ""))):
        inputs = food.get("inputFoods", [])
        category = food.get("wweiaFoodCategory", {}).get("wweiaFoodCategoryDescription")
        if category not in ALLOWED_CATEGORIES:
            dataset.reject("category_excluded")
            continue
        if len(inputs) < 2:
            dataset.reject("fewer_than_two_components")
            continue
        normalized_description = normalize_name(food.get("description", ""))
        if not normalized_description:
            dataset.reject("empty_description")
            continue
        if normalized_description in reserved_names:
            dataset.reject("duplicate_curated_identity")
            continue

        weights: dict[str, float] = defaultdict(float)
        component_sources: dict[str, tuple[str, str, dict] | None] = {}
        uses_legacy_nutrition = False
        invalid_reason = None
        for item in inputs:
            code = str(item.get("ingredientCode", ""))
            weight = item.get("ingredientWeight")
            # FNDDS's ingredientWeight is the authoritative normalized gram
            # value even when the source amount was expressed as cups, spoons,
            # pounds, or a source-specific portion code.
            if not isinstance(weight, (int, float)) or weight <= 0:
                invalid_reason = "missing_normalized_gram_weight"
                break
            source_food = sr_by_code.get(code) or survey_by_code.get(code)
            if source_food is None:
                invalid_reason = "missing_canonical_ingredient"
                break
            kcal = _nutrient(source_food, "208")
            if kcal is None or not 0 <= kcal <= 1000:
                invalid_reason = "missing_or_invalid_nutrition"
                break
            normalized_source_name = normalize_name(source_food["description"])
            stable_id = stable_ingredient_ids.get(normalized_source_name)
            if stable_id is not None:
                component_key = stable_id
                component_sources[component_key] = None
                uses_legacy_nutrition = True
            else:
                source_kind, canonical_code, canonical_food = canonical_source_by_name[normalized_source_name]
                component_key = f"{source_kind}:{canonical_code}"
                component_sources[component_key] = (source_kind, canonical_code, canonical_food)
            weights[component_key] += float(weight)
        if invalid_reason:
            dataset.reject(invalid_reason)
            continue
        if len(weights) < 2 or len(weights) > 40:
            dataset.reject("invalid_component_count")
            continue

        recipe_ingredients: list[ImportedRecipeIngredient] = []
        for component_key, grams in weights.items():
            canonical_source = component_sources[component_key]
            if canonical_source is None:
                recipe_ingredients.append(ImportedRecipeIngredient(component_key, grams))
                continue
            source_kind, code, source_food = canonical_source
            description = source_food["description"]
            is_sr = source_kind == "sr"
            ingredient_id = f"{stable_slug(description)}.usda_{source_kind}_{int(code):05d}"
            source_provenance = SourceProvenance(
                source="USDA FoodData Central SR Legacy" if is_sr else "USDA FoodData Central FNDDS",
                record_id=str(source_food["fdcId"]),
                url=f"https://fdc.nal.usda.gov/fdc-app.html#/food-details/{source_food['fdcId']}/nutrients",
                license="CC0-1.0 / U.S. public domain",
                import_version="SR Legacy 2018-04" if is_sr else "FNDDS 2021-2023 (2024-10-31)",
                import_date="2026-09-26",
                confidence="high",
                verification_status="source_record",
            )
            if ingredient_id not in dataset.ingredients:
                dataset.ingredients[ingredient_id] = ImportedIngredient(
                    id=ingredient_id,
                    canonical_name=description,
                    nutrition_lookup_name=f"usda_{source_kind}_{int(code):05d}",
                    aliases=[],
                    nutrition=ImportedNutritionRecord(
                        kcal_per_100g=_nutrient(source_food, "208") or 0,
                        protein_g=_nutrient(source_food, "203"),
                        fat_g=_nutrient(source_food, "204"),
                        carbohydrate_g=_nutrient(source_food, "205"),
                        fiber_g=_nutrient(source_food, "291"),
                        prepared_state=prepared_state(description),
                        provenance=source_provenance,
                    ),
                )
            recipe_ingredients.append(ImportedRecipeIngredient(ingredient_id, grams))

        fdc_id = str(food["fdcId"])
        food_code = str(food["foodCode"])
        name = food["description"]
        cuisine, region = _cuisine(name)
        provenance = SourceProvenance(
            source="USDA FoodData Central FNDDS",
            record_id=fdc_id,
            url=f"https://fdc.nal.usda.gov/fdc-app.html#/food-details/{fdc_id}/nutrients",
            license="CC0-1.0 / U.S. public domain",
            import_version="FNDDS 2021-2023 (2024-10-31)",
            import_date="2026-09-26",
            confidence="high",
            verification_status="source_composition",
        )
        dataset.recipes.append(
            ImportedRecipe(
                id=f"global.{stable_slug(name)}.fndds_{food_code}",
                canonical_name=name,
                cuisine=cuisine,
                region=region,
                variant=f"FNDDS {food_code}",
                default_serving_grams=_serving_grams(food),
                ingredients=recipe_ingredients,
                aliases=[ImportedAlias(name, "en", "en-US", provenance)],
                provenance=provenance,
                quality_tier="B" if uses_legacy_nutrition else "A",
            )
        )
    return dataset
