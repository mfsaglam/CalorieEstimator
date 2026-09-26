from __future__ import annotations

import json
from pathlib import Path

from fooddb.models import ImportedAlias, ImportedDataset, SourceProvenance


ENTITY_TO_RECIPE = {
    "Q876624": "it.spaghetti_carbonara.roman",
    "Q188788": "global.falafel.fndds_41209000",
    "Q46383": "global.sushi_nfs.fndds_58151100",
    "Q4551": "ru.borscht.default",
    "Q648352": "kr.bibimbap.default",
    "Q241987": "me.hummus.default",
    "Q183095": "fr.ratatouille.default",
}

PRIORITY_LANGUAGES = {
    "ar", "bn", "cs", "da", "de", "el", "en", "es", "fa", "fi", "fr", "he", "hi",
    "hr", "hu", "id", "it", "ja", "ko", "ms", "nl", "no", "pl", "pt", "ro", "ru",
    "sr", "sv", "sw", "th", "tl", "tr", "uk", "vi", "zh",
}


def load_aliases(path: Path) -> tuple[ImportedDataset, dict[str, list[ImportedAlias]]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    dataset = ImportedDataset(source="wikidata_cc0_aliases")
    result: dict[str, list[ImportedAlias]] = {}
    dataset.discovered = len(ENTITY_TO_RECIPE)

    for entity_id, recipe_id in ENTITY_TO_RECIPE.items():
        entity = payload["entities"].get(entity_id)
        if not entity:
            dataset.reject("missing_reviewed_entity")
            continue
        provenance = SourceProvenance(
            source="Wikidata",
            record_id=entity_id,
            url=f"https://www.wikidata.org/wiki/{entity_id}",
            license="CC0-1.0",
            import_version="API snapshot 2026-09-26",
            import_date="2026-09-26",
            confidence="high",
            verification_status="reviewed_entity_mapping",
        )
        aliases: list[ImportedAlias] = []
        for language, label in entity.get("labels", {}).items():
            if language in PRIORITY_LANGUAGES:
                aliases.append(ImportedAlias(label["value"], language, None, provenance))
        for language, values in entity.get("aliases", {}).items():
            if language in PRIORITY_LANGUAGES:
                aliases.extend(ImportedAlias(value["value"], language, None, provenance) for value in values)
        result[recipe_id] = aliases
        dataset.accepted_aliases += len(aliases)
    return dataset, result
