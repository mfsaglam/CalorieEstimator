from __future__ import annotations

import re
import unicodedata


def normalize_name(value: str) -> str:
    canonical = unicodedata.normalize("NFC", value).lower()
    return " ".join("".join(character if character.isalnum() else " " for character in canonical).split())


def stable_slug(value: str, maximum: int = 56) -> str:
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "_", ascii_value.lower()).strip("_")
    return (slug[:maximum].rstrip("_") or "food")


def prepared_state(description: str) -> str:
    normalized = normalize_name(description)
    for state in ("raw", "boiled", "fried", "roasted", "grilled", "baked", "cooked", "drained", "smoked"):
        if state in normalized.split():
            return state
    return "as_listed"


def is_compact_script(value: str) -> bool:
    return " " not in value and any(ord(character) > 127 and character.isalpha() for character in value)
