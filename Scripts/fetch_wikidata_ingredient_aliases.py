#!/usr/bin/env python3
from __future__ import annotations

import json
import sqlite3
import sys
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path


repository = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(repository / "Scripts"))

from fooddb.ingredient_aliases import TARGET_LANGUAGES  # noqa: E402
from fooddb.normalize import normalize_name  # noqa: E402


GENERATED_ON = "2026-09-27"
USER_AGENT = "CalorieEstimator-fooddb/1.0 (offline alias snapshot builder)"
WIKIDATA_LICENSE = "CC0-1.0"
FOODON_LICENSE = "CC-BY-4.0"
FOODON_CROSS_CHECK_LIMIT = 40

REJECTED_MAPPING_OVERRIDES = {
    "egg_whole_raw_fresh.usda_sr_01123": "broad egg food concept overlaps the existing curated egg IngredientID",
    "celery_raw.usda_sr_11143": "Wikidata entity represents the plant species rather than the edible product",
    "cheese_parmesan_grated.usda_sr_01032": "broad Parmesan concept overlaps the existing curated parmesan IngredientID",
    "spices_pepper_black.usda_sr_02030": "concept overlaps the existing curated black_pepper IngredientID",
    "cheese_cheddar_includes_foods_for_usda_s_food_distributi.usda_sr_01009": "concept overlaps the existing curated cheddar IngredientID",
    "cheese_mozzarella_low_moisture_part_skim.usda_sr_01029": "Wikidata concept is broader than the low-moisture part-skim ingredient",
    "shortening_vegetable_household_composite.usda_sr_04615": "Wikidata concept is broader than the vegetable household composite",
    "cheese_ricotta_whole_milk.usda_sr_01036": "Wikidata concept is broader than whole-milk ricotta",
    "carrots_raw.usda_sr_11124": "concept overlaps the existing curated carrot IngredientID",
    "egg_yolk_raw_fresh.usda_sr_01125": "Wikidata entity represents a biological egg part rather than a verified food identity",
    "cream_sour_cultured.usda_sr_01056": "concept overlaps the existing curated sour_cream IngredientID",
    "raisins_dark_seedless_includes_foods_for_usda_s_food_dis.usda_sr_09298": "Wikidata concept is broader than dark seedless raisins",
    "cucumber_with_peel_raw.usda_sr_11205": "Wikidata concept is broader than raw cucumber with peel",
    "egg_white_raw_fresh.usda_sr_01124": "Wikidata entity represents a biological egg part rather than a verified food identity",
    "vanilla_extract_imitation_no_alcohol.usda_sr_02052": "Wikidata entity represents ethanol-based vanilla extract, not imitation alcohol-free extract",
    "margarine_regular_80_fat_composite_stick_with_salt.usda_sr_04610": "Wikidata concept is broader than the salted 80-percent-fat ingredient",
    "salad_dressing_mayonnaise_light.usda_sr_04641": "Wikidata entity is generic salad dressing, not light mayonnaise",
    "lime_juice_raw.usda_sr_09160": "Wikidata entity represents lime fruit, not lime juice",
    "mustard_prepared_yellow.usda_sr_02046": "Wikidata concept is broader than prepared yellow mustard",
    "jellies.usda_sr_19300": "Wikidata entity is the broader fruit-preserves category",
    "cheese_swiss.usda_sr_01040": "Wikidata entity represents cheeses from Switzerland, not the USDA Swiss-cheese identity",
    "wheat_flour_whole_grain_includes_foods_for_usda_s_food_d.usda_sr_20080": "Wikidata entity is broader wheat flour, not whole-grain wheat flour",
    "milk_nonfat_fluid_without_added_vitamin_a_and_vitamin_d.usda_sr_01151": "Wikidata entity is broader cow milk, not nonfat unfortified milk",
    "spices_thyme_dried.usda_sr_02042": "Wikidata entity is the broad herb concept, not specifically dried thyme",
    "catsup.usda_sr_11935": "concept overlaps the existing curated ketchup IngredientID",
    "capers_canned.usda_sr_02054": "Wikidata entity represents the plant species rather than canned capers",
}


def _json_request(url: str, timeout: int = 90) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def _sparql(query: str) -> dict:
    parameters = urllib.parse.urlencode({"query": query, "format": "json"}).encode("utf-8")
    request = urllib.request.Request(
        "https://query.wikidata.org/sparql",
        data=parameters,
        headers={"User-Agent": USER_AGENT, "Accept": "application/sparql-results+json"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


def _identifier_matches(values_by_property: dict[str, list[str]]) -> dict[str, dict[str, set[str]]]:
    value_rows = " ".join(
        f"(wdt:{property_id} {json.dumps(value)})"
        for property_id, values in values_by_property.items()
        for value in values
    )
    query = (
        "SELECT ?property ?identifier ?item WHERE { "
        f"VALUES (?property ?identifier) {{ {value_rows} }} "
        "?item ?property ?identifier. "
        "} ORDER BY ?property ?identifier ?item"
    )
    payload = _sparql(query)
    matches: dict[str, dict[str, set[str]]] = defaultdict(lambda: defaultdict(set))
    property_uri_to_id = {
        "http://www.wikidata.org/prop/direct/P1978": "P1978",
        "http://www.wikidata.org/prop/direct/P12917": "P12917",
    }
    for binding in payload["results"]["bindings"]:
        property_id = property_uri_to_id[binding["property"]["value"]]
        identifier = binding["identifier"]["value"]
        qid = binding["item"]["value"].rsplit("/", 1)[-1]
        matches[property_id][identifier].add(qid)
    return matches


def _fetch_entities(qids: list[str]) -> dict[str, dict]:
    entities: dict[str, dict] = {}
    languages = "|".join(TARGET_LANGUAGES)
    for start in range(0, len(qids), 50):
        batch = qids[start:start + 50]
        parameters = urllib.parse.urlencode({
            "action": "wbgetentities",
            "ids": "|".join(batch),
            "props": "labels|aliases|descriptions",
            "languages": languages,
            "format": "json",
        })
        payload = _json_request(f"https://www.wikidata.org/w/api.php?{parameters}")
        entities.update(payload.get("entities", {}))
    return entities


def _foodon_cross_check(label: str) -> dict | None:
    parameters = urllib.parse.urlencode({
        "q": label,
        "ontology": "foodon",
        "exact": "true",
        "rows": "10",
    })
    payload = _json_request(f"https://www.ebi.ac.uk/ols4/api/search?{parameters}")
    documents = payload.get("response", {}).get("docs", [])
    exact = [
        item for item in documents
        if normalize_name(item.get("label", "")) == normalize_name(label)
        and item.get("obo_id")
        and item.get("ontology_name") == "foodon"
        and item["obo_id"].startswith("FOODON:")
    ]
    identifiers = sorted({item["obo_id"] for item in exact})
    if len(identifiers) != 1:
        return None
    return {
        "foodon_id": identifiers[0],
        "matched_label": label,
        "match_method": "exact_normalized_preferred_label",
        "source": "FoodOn via EMBL-EBI OLS",
        "source_license": FOODON_LICENSE,
    }


def _top_ingredients(database: sqlite3.Connection) -> tuple[int, list[dict]]:
    total = database.execute("SELECT COUNT(*) FROM recipe_ingredients").fetchone()[0]
    rows = database.execute(
        """
        WITH counts AS (
            SELECT ingredient_id, COUNT(*) AS occurrence_count
            FROM recipe_ingredients
            GROUP BY ingredient_id
        ), ranked AS (
            SELECT ingredient_id, occurrence_count,
                   ROW_NUMBER() OVER (ORDER BY occurrence_count DESC, ingredient_id) AS rank
            FROM counts
        )
        SELECT ranked.rank, ingredients.id, ingredients.canonical_name,
               ingredients.nutrition_lookup_name, ranked.occurrence_count,
               ingredient_nutrition.source, ingredient_nutrition.source_record_id
        FROM ranked
        JOIN ingredients ON ingredients.id = ranked.ingredient_id
        JOIN ingredient_nutrition ON ingredient_nutrition.ingredient_id = ranked.ingredient_id
        WHERE ranked.rank <= 250
        ORDER BY ranked.rank
        """
    ).fetchall()
    cumulative = 0
    result = []
    for rank, ingredient_id, canonical_name, lookup_name, count, source, source_record_id in rows:
        cumulative += count
        aliases = [
            {
                "alias": alias,
                "language_code": language,
                "locale_identifier": locale,
                "source": alias_source,
            }
            for alias, language, locale, alias_source in database.execute(
                """
                SELECT alias, language_code, locale_identifier, source
                FROM ingredient_aliases
                WHERE ingredient_id = ?
                  AND source <> 'Wikidata'
                ORDER BY language_code, locale_identifier, normalized_alias, alias
                """,
                (ingredient_id,),
            )
        ]
        external_ids = {"food_data_central_id": source_record_id}
        if ".usda_sr_" in ingredient_id:
            external_ids["usda_ndb_number"] = ingredient_id.rsplit(".usda_sr_", 1)[1]
        elif ".usda_fndds_" in ingredient_id:
            external_ids["fndds_food_code"] = ingredient_id.rsplit(".usda_fndds_", 1)[1]
        result.append({
            "rank": rank,
            "ingredient_id": ingredient_id,
            "canonical_name": canonical_name,
            "nutrition_lookup_name": lookup_name,
            "existing_aliases": aliases,
            "nutrition_source": source,
            "external_ids_already_known": external_ids,
            "recipe_occurrence_count": count,
            "percentage_of_all_ingredient_occurrences": round(100.0 * count / total, 6),
            "cumulative_coverage_percent": round(100.0 * cumulative / total, 6),
        })
    if len(result) != 250:
        raise RuntimeError(f"expected exactly 250 ingredients, found {len(result)}")
    return total, result


def main() -> None:
    database_path = repository / "Sources/CalorieEstimator/Resources/Recipes.sqlite3"
    database = sqlite3.connect(f"file:{database_path}?mode=ro", uri=True)
    total_occurrences, selected = _top_ingredients(database)
    database.close()

    ndb_values = sorted({
        value
        for item in selected
        for value in (
            item["external_ids_already_known"].get("usda_ndb_number"),
            (item["external_ids_already_known"].get("usda_ndb_number") or "").lstrip("0"),
        )
        if value
    })
    fdc_values = sorted({
        item["external_ids_already_known"]["food_data_central_id"]
        for item in selected
    })
    identifier_matches = _identifier_matches({"P1978": ndb_values, "P12917": fdc_values})
    ndb_matches = identifier_matches["P1978"]
    fdc_matches = identifier_matches["P12917"]

    raw_candidates: list[dict] = []
    for item in selected:
        ingredient_id = item["ingredient_id"]
        evidence: list[dict] = []
        qids: set[str] = set()
        ndb = item["external_ids_already_known"].get("usda_ndb_number")
        if ndb:
            for match_value in (ndb, ndb.lstrip("0")):
                matched = sorted(ndb_matches.get(match_value, set()))
                if matched:
                    evidence.append({"property": "P1978", "value": match_value, "wikidata_ids": matched})
                    qids.update(matched)
        fdc = item["external_ids_already_known"]["food_data_central_id"]
        matched_fdc = sorted(fdc_matches.get(fdc, set()))
        if matched_fdc:
            evidence.append({"property": "P12917", "value": fdc, "wikidata_ids": matched_fdc})
            qids.update(matched_fdc)
        if ingredient_id == "olive_oil":
            evidence.append({
                "property": "manual_review",
                "value": "olive oil food product",
                "wikidata_ids": ["Q93165"],
            })
            qids.add("Q93165")
        raw_candidates.append({
            "ingredient_id": ingredient_id,
            "candidate_qids": sorted(qids),
            "evidence": evidence,
        })

    qid_claimants: dict[str, set[str]] = defaultdict(set)
    for candidate in raw_candidates:
        if len(candidate["candidate_qids"]) == 1:
            qid_claimants[candidate["candidate_qids"][0]].add(candidate["ingredient_id"])

    mappings: list[dict] = []
    for item, candidate in zip(selected, raw_candidates):
        qids = candidate["candidate_qids"]
        mapping = {
            "ingredient_id": item["ingredient_id"],
            "canonical_name": item["canonical_name"],
            "nutrition_lookup_name": item["nutrition_lookup_name"],
            "wikidata_id": qids[0] if len(qids) == 1 else None,
            "status": "manual_review_required",
            "confidence": "none",
            "evidence": candidate["evidence"],
            "reason": None,
            "foodon_cross_check": None,
        }
        if not qids:
            mapping["reason"] = "no direct Wikidata P1978/P12917 identity match"
        elif len(qids) > 1:
            mapping["reason"] = "direct external identifiers resolve to multiple Wikidata entities"
        elif len(qid_claimants[qids[0]]) > 1:
            mapping["reason"] = "Wikidata entity is shared by multiple existing IngredientIDs"
            mapping["candidate_ingredient_ids"] = sorted(qid_claimants[qids[0]])
        else:
            properties = {evidence["property"] for evidence in candidate["evidence"]}
            if "manual_review" in properties or {"P1978", "P12917"}.issubset(properties):
                mapping["status"] = "verified"
                mapping["confidence"] = "verified"
            else:
                mapping["status"] = "high_confidence"
                mapping["confidence"] = "high"
            mapping["reason"] = "direct source identifier match"
        mappings.append(mapping)

    all_qids = sorted({qid for candidate in raw_candidates for qid in candidate["candidate_qids"]})
    entities = _fetch_entities(all_qids)

    for mapping in mappings:
        if mapping["status"] not in {"verified", "high_confidence"}:
            continue
        entity = entities.get(mapping["wikidata_id"], {})
        label = entity.get("labels", {}).get("en", {}).get("value")
        description = entity.get("descriptions", {}).get("en", {}).get("value", "").casefold()
        rejection = REJECTED_MAPPING_OVERRIDES.get(mapping["ingredient_id"])
        if label is None:
            rejection = "Wikidata entity has no English preferred label in the source snapshot"
        elif label.casefold().startswith("category:") or "wikimedia category" in description:
            rejection = "Wikidata entity is a category rather than a food or ingredient concept"
        if rejection:
            mapping["status"] = "manual_review_required"
            mapping["confidence"] = "none"
            mapping["reason"] = rejection

    foodon_checked = 0
    for mapping in mappings:
        if foodon_checked >= FOODON_CROSS_CHECK_LIMIT:
            break
        if mapping["status"] not in {"verified", "high_confidence"}:
            continue
        entity = entities.get(mapping["wikidata_id"], {})
        label = entity.get("labels", {}).get("en", {}).get("value")
        if not label:
            continue
        mapping["foodon_cross_check"] = _foodon_cross_check(label)
        foodon_checked += 1

    mapping_payload = {
        "schema_version": 1,
        "generated_on": GENERATED_ON,
        "source_snapshot": {
            "wikidata_query_service": "P1978 and P12917 direct identifier queries",
            "wikidata_api": "wbgetentities labels, aliases, and descriptions",
            "wikidata_license": WIKIDATA_LICENSE,
            "foodon_service": "EMBL-EBI Ontology Lookup Service 4 exact search",
            "foodon_license": FOODON_LICENSE,
        },
        "baseline": {
            "ingredient_aliases": 11,
            "database_bytes": 8474624,
        },
        "selection": {
            "method": "recipe ingredient occurrence count, descending; IngredientID ascending as deterministic tie-breaker",
            "total_ingredient_occurrences": total_occurrences,
            "count": len(selected),
            "ingredients": selected,
        },
        "mappings": mappings,
    }
    entity_payload = {
        "schema_version": 1,
        "generated_on": GENERATED_ON,
        "snapshot": "Wikidata wbgetentities API snapshot 2026-09-27",
        "license": WIKIDATA_LICENSE,
        "languages": list(TARGET_LANGUAGES),
        "entities": {qid: entities[qid] for qid in sorted(entities)},
    }
    output_directory = repository / "DataSources/wikidata"
    output_directory.mkdir(parents=True, exist_ok=True)
    (output_directory / "ingredient_mappings.json").write_text(
        json.dumps(mapping_payload, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
        encoding="utf-8",
    )
    (output_directory / "ingredient_entities.json").write_text(
        json.dumps(entity_payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    accepted = sum(mapping["status"] in {"verified", "high_confidence"} for mapping in mappings)
    cross_checked = sum(mapping["foodon_cross_check"] is not None for mapping in mappings)
    print(f"selected={len(selected)} mapped={accepted} foodon_cross_checked={cross_checked} entities={len(entities)}")


if __name__ == "__main__":
    main()
