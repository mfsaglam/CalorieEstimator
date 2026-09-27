from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from fooddb.models import ImportedAlias, ImportedDataset, ImportedIngredient, ImportedRecipe, SourceProvenance
from fooddb.normalize import normalize_ingredient_alias, normalize_name


TARGET_LANGUAGES = ("en", "tr", "de", "es", "fr", "it", "pt", "ru", "ar", "hi", "zh", "ja", "ko")
ALLOWED_MAPPING_STATUSES = {"verified", "high_confidence"}
MAX_ALIAS_CHARACTERS = 80
MAX_ALIAS_WORDS = 8
PRE_ENRICHMENT_ALIAS_COUNT = 11
PRE_ENRICHMENT_DATABASE_BYTES = 8_474_624
SCIENTIFIC_NAME_TOKENS = {
    "adeps", "camphora", "cinnamomum", "laurus", "persea", "suillus",
}
REJECTED_SOURCE_TERMS = {
    "aceite de oliva virgen": "specific_subtype",
    "arbol de la canela": "plant_or_dish_term",
    "blume des öls": "descriptive_or_non_equivalent",
    "darçini üzerine gerçek": "descriptive_or_non_equivalent",
    "flor de aceite": "descriptive_or_non_equivalent",
    "maïzena": "brand_specific",
    "oleicultura": "category_or_process",
    "te de canela": "prepared_dish",
    "west country farmhouse cheddar": "specific_subtype",
    "zucchero greggio": "non_equivalent",
    "الصيغة الكيميائية للسكر": "descriptive_or_non_equivalent",
    "الدارصيني على الحقيقة": "descriptive_or_non_equivalent",
    "دارصيني على الحقيقة": "descriptive_or_non_equivalent",
    "سكر خام": "non_equivalent",
    "árbol de la canela": "plant_or_dish_term",
    "té de canela": "prepared_dish",
}


@dataclass(frozen=True)
class RankedIngredient:
    rank: int
    ingredient_id: str
    occurrence_count: int
    occurrence_percent: float
    cumulative_coverage_percent: float


@dataclass
class AliasEnrichmentResult:
    dataset: ImportedDataset
    selected: list[RankedIngredient]
    aliases_before: int
    accepted: list[dict] = field(default_factory=list)
    duplicates: list[dict] = field(default_factory=list)
    collisions: list[dict] = field(default_factory=list)
    rejected: list[dict] = field(default_factory=list)
    mappings: list[dict] = field(default_factory=list)


def rank_ingredients(recipes: list[ImportedRecipe], limit: int = 250) -> list[RankedIngredient]:
    counts = Counter(
        item.ingredient_id
        for recipe in recipes
        for item in recipe.ingredients
    )
    total = sum(counts.values())
    ranked: list[RankedIngredient] = []
    cumulative = 0
    for rank, (ingredient_id, count) in enumerate(
        sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:limit],
        start=1,
    ):
        cumulative += count
        ranked.append(
            RankedIngredient(
                rank=rank,
                ingredient_id=ingredient_id,
                occurrence_count=count,
                occurrence_percent=round(100.0 * count / total, 6),
                cumulative_coverage_percent=round(100.0 * cumulative / total, 6),
            )
        )
    if len(ranked) != limit:
        raise ValueError(f"expected exactly {limit} ranked ingredients, found {len(ranked)}")
    return ranked


def _alias_rejection_reason(alias: str) -> str | None:
    stripped = alias.strip()
    normalized = normalize_ingredient_alias(stripped)
    if not normalized:
        return "empty"
    if normalized.replace(" ", "").isnumeric():
        return "numeric_only"
    rejected_term_reason = REJECTED_SOURCE_TERMS.get(normalized)
    if rejected_term_reason:
        return rejected_term_reason
    if SCIENTIFIC_NAME_TOKENS.intersection(normalized.split()):
        return "scientific_taxonomic_name"
    if len(stripped) > MAX_ALIAS_CHARACTERS or len(normalized.split()) > MAX_ALIAS_WORDS:
        return "descriptive_or_too_long"
    if any(character in stripped for character in ("\n", "\r", "\t")):
        return "descriptive_or_too_long"
    lowered = stripped.casefold()
    if lowered.startswith(("category:", "list of ", "template:", "portal:")):
        return "category_or_article_title"
    if re.search(r"\([^)]*(?:disambiguation|brand|company|restaurant)[^)]*\)", lowered):
        return "disambiguator_or_brand"
    return None


def _term_values(entity: dict, language: str) -> list[tuple[str, str]]:
    values: list[tuple[str, str]] = []
    label = entity.get("labels", {}).get(language)
    if label and label.get("value"):
        values.append((label["value"], "preferred_label"))
    values.extend(
        (item["value"], "alias")
        for item in entity.get("aliases", {}).get(language, [])
        if item.get("value")
    )
    return values


def _existing_claims(ingredients: dict[str, ImportedIngredient]) -> tuple[dict[str, set[str]], set[tuple[str, str, str, str]]]:
    claims: dict[str, set[str]] = defaultdict(set)
    exact: set[tuple[str, str, str, str]] = set()
    for ingredient in ingredients.values():
        canonical = normalize_name(ingredient.canonical_name)
        if canonical:
            claims[canonical].add(ingredient.id)
        for alias in ingredient.aliases:
            normalized = normalize_ingredient_alias(alias.alias)
            if not normalized:
                continue
            claims[normalized].add(ingredient.id)
            exact.add((ingredient.id, normalized, alias.language_code or "", alias.locale_identifier or ""))
    return claims, exact


def enrich(
    ingredients: dict[str, ImportedIngredient],
    recipes: list[ImportedRecipe],
    mapping_path: Path,
    entity_path: Path,
) -> AliasEnrichmentResult:
    selected = rank_ingredients(recipes)
    selected_ids = [item.ingredient_id for item in selected]
    selected_set = set(selected_ids)
    mapping_payload = json.loads(mapping_path.read_text(encoding="utf-8"))
    entity_payload = json.loads(entity_path.read_text(encoding="utf-8"))
    recorded_selection = [item["ingredient_id"] for item in mapping_payload["selection"]["ingredients"]]
    if recorded_selection != selected_ids:
        raise ValueError("ingredient alias mapping selection does not match the current top 250")

    dataset = ImportedDataset(source="wikidata_ingredient_aliases")
    mappings = mapping_payload.get("mappings", [])
    dataset.discovered = len(mappings)
    result = AliasEnrichmentResult(
        dataset=dataset,
        selected=selected,
        aliases_before=sum(len(ingredient.aliases) for ingredient in ingredients.values()),
        mappings=mappings,
    )
    if result.aliases_before != PRE_ENRICHMENT_ALIAS_COUNT:
        raise ValueError(
            "ingredient alias baseline changed; refresh and review the enrichment snapshot before rebuilding"
        )
    existing_claims, existing_exact = _existing_claims(ingredients)
    candidates: list[dict] = []

    for mapping in mappings:
        ingredient_id = mapping["ingredient_id"]
        if ingredient_id not in selected_set:
            raise ValueError(f"mapping is outside the selected top 250: {ingredient_id}")
        status = mapping["status"]
        if status not in ALLOWED_MAPPING_STATUSES:
            dataset.reject(f"mapping_{status}")
            continue
        entity_id = mapping["wikidata_id"]
        entity = entity_payload.get("entities", {}).get(entity_id)
        if entity is None:
            dataset.reject("missing_entity_snapshot")
            result.rejected.append({
                "ingredient_id": ingredient_id,
                "wikidata_id": entity_id,
                "reason": "missing_entity_snapshot",
            })
            continue
        provenance = SourceProvenance(
            source="Wikidata",
            record_id=entity_id,
            url=f"https://www.wikidata.org/wiki/{entity_id}",
            license="CC0-1.0",
            import_version=entity_payload.get("snapshot", "Wikidata API snapshot"),
            import_date=entity_payload.get("generated_on", "2026-09-27"),
            confidence="verified" if status == "verified" else "high",
            verification_status=status,
        )
        for language in TARGET_LANGUAGES:
            for alias, term_kind in _term_values(entity, language):
                reason = _alias_rejection_reason(alias)
                candidate = {
                    "ingredient_id": ingredient_id,
                    "alias": alias,
                    "normalized_alias": normalize_ingredient_alias(alias),
                    "language_code": language,
                    "locale_identifier": None,
                    "source": "Wikidata",
                    "source_entity_id": entity_id,
                    "source_license": "CC0-1.0",
                    "mapping_confidence": status,
                    "term_kind": term_kind,
                    "provenance": provenance,
                }
                if reason:
                    dataset.reject(reason)
                    result.rejected.append({key: value for key, value in candidate.items() if key != "provenance"} | {"reason": reason})
                    continue
                candidates.append(candidate)

    candidate_claims: dict[str, set[str]] = defaultdict(set)
    for candidate in candidates:
        candidate_claims[candidate["normalized_alias"]].add(candidate["ingredient_id"])

    seen: set[tuple[str, str, str, str]] = set(existing_exact)
    for candidate in sorted(
        candidates,
        key=lambda item: (
            item["ingredient_id"], item["language_code"], item["normalized_alias"],
            item["term_kind"], item["alias"],
        ),
    ):
        ingredient_id = candidate["ingredient_id"]
        normalized = candidate["normalized_alias"]
        conflicting_ids = (existing_claims.get(normalized, set()) | candidate_claims[normalized]) - {ingredient_id}
        public = {key: value for key, value in candidate.items() if key != "provenance"}
        if conflicting_ids:
            dataset.reject("cross_ingredient_collision")
            result.collisions.append(public | {
                "candidate_ingredient_ids": sorted({ingredient_id} | conflicting_ids),
                "reason": "normalized alias is claimed by multiple IngredientIDs",
            })
            continue
        key = (
            ingredient_id,
            normalized,
            candidate["language_code"] or "",
            candidate["locale_identifier"] or "",
        )
        if key in seen:
            dataset.reject("duplicate")
            result.duplicates.append(public | {"reason": "existing or repeated normalized alias"})
            continue
        seen.add(key)
        ingredient = ingredients[ingredient_id]
        ingredient.aliases.append(
            ImportedAlias(
                alias=candidate["alias"],
                language_code=candidate["language_code"],
                locale_identifier=candidate["locale_identifier"],
                provenance=candidate["provenance"],
            )
        )
        existing_claims[normalized].add(ingredient_id)
        dataset.accepted_aliases += 1
        result.accepted.append(public)

    return result


def coverage_metrics(
    recipes: list[ImportedRecipe],
    ingredients: dict[str, ImportedIngredient],
    selected: list[RankedIngredient],
    baseline_aliases: dict[str, list[ImportedAlias]],
) -> dict:
    occurrence_counts = {item.ingredient_id: item.occurrence_count for item in selected}
    all_occurrence_counts = Counter(
        item.ingredient_id
        for recipe in recipes
        for item in recipe.ingredients
    )

    def aliases_for(ingredient_id: str, before: bool) -> list[ImportedAlias]:
        return baseline_aliases.get(ingredient_id, []) if before else ingredients[ingredient_id].aliases

    def snapshot(before: bool) -> dict:
        output: dict[str, dict] = {}
        for limit in (50, 100, 250):
            subset = {item.ingredient_id for item in selected[:limit]}
            denominator = sum(occurrence_counts[ingredient_id] for ingredient_id in subset)
            covered = {
                ingredient_id
                for ingredient_id in subset
                if aliases_for(ingredient_id, before)
            }
            covered_occurrences = sum(occurrence_counts[ingredient_id] for ingredient_id in covered)
            fully_covered_recipes = sum(
                1
                for recipe in recipes
                if all(item.ingredient_id in covered for item in recipe.ingredients)
            )
            per_language = {}
            for language in TARGET_LANGUAGES:
                language_covered = {
                    ingredient_id
                    for ingredient_id in subset
                    if any(alias.language_code == language for alias in aliases_for(ingredient_id, before))
                }
                language_occurrences = sum(occurrence_counts[ingredient_id] for ingredient_id in language_covered)
                per_language[language] = {
                    "ingredients": len(language_covered),
                    "occurrence_coverage_percent": round(100.0 * language_occurrences / denominator, 4),
                    "occurrence_share_of_all_percent": round(
                        100.0 * language_occurrences / sum(all_occurrence_counts.values()),
                        4,
                    ),
                }
            output[f"top_{limit}"] = {
                "ingredient_count": limit,
                "occurrence_denominator": denominator,
                "subset_occurrence_share_of_all_percent": round(
                    100.0 * denominator / sum(all_occurrence_counts.values()),
                    4,
                ),
                "ingredients_with_any_alias": len(covered),
                "occurrence_coverage_percent": round(100.0 * covered_occurrences / denominator, 4),
                "aliased_occurrence_share_of_all_percent": round(
                    100.0 * covered_occurrences / sum(all_occurrence_counts.values()),
                    4,
                ),
                "fully_covered_recipes": fully_covered_recipes,
                "fully_covered_recipe_percent": round(100.0 * fully_covered_recipes / len(recipes), 4),
                "per_language": per_language,
            }
        all_aliased = {
            ingredient_id
            for ingredient_id in ingredients
            if aliases_for(ingredient_id, before)
        }
        all_occurrence_denominator = sum(all_occurrence_counts.values())
        all_covered_occurrences = sum(
            count
            for ingredient_id, count in all_occurrence_counts.items()
            if ingredient_id in all_aliased
        )
        fully_covered = sum(
            1
            for recipe in recipes
            if all(item.ingredient_id in all_aliased for item in recipe.ingredients)
        )
        all_language_coverage = {}
        for language in TARGET_LANGUAGES:
            language_covered = {
                ingredient_id
                for ingredient_id in ingredients
                if any(alias.language_code == language for alias in aliases_for(ingredient_id, before))
            }
            language_occurrences = sum(
                count
                for ingredient_id, count in all_occurrence_counts.items()
                if ingredient_id in language_covered
            )
            all_language_coverage[language] = {
                "ingredients": len(language_covered),
                "occurrence_coverage_percent": round(
                    100.0 * language_occurrences / all_occurrence_denominator,
                    4,
                ),
            }
        output["all_ingredients"] = {
            "ingredient_count": len(ingredients),
            "occurrence_denominator": all_occurrence_denominator,
            "ingredients_with_any_alias": len(all_aliased),
            "occurrence_coverage_percent": round(
                100.0 * all_covered_occurrences / all_occurrence_denominator,
                4,
            ),
            "fully_covered_recipes": fully_covered,
            "fully_covered_recipe_percent": round(100.0 * fully_covered / len(recipes), 4),
            "per_language": all_language_coverage,
        }
        return output

    return {
        "definitions": {
            "occurrence_coverage": "ingredient occurrences within the ranked subset whose IngredientID has at least one alias",
            "subset_occurrence_share_of_all": "all trusted-recipe ingredient occurrences contributed by the ranked subset",
            "aliased_occurrence_share_of_all": "all trusted-recipe ingredient occurrences contributed by aliased IngredientIDs in the ranked subset",
            "fully_covered_recipe": "trusted recipe for which every IngredientID has at least one alias; top-N rows additionally require every IngredientID to be covered within that ranked subset",
            "per_language": "ingredient-occurrence coverage within the ranked subset for aliases tagged with the language",
        },
        "before": snapshot(True),
        "after": snapshot(False),
    }
