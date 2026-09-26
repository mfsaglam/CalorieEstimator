# Food knowledge data sources

Runtime behavior remains fully offline. Network access is used only by the optional build-time fetch scripts.

## Included

- **USDA FoodData Central, FNDDS 2021–2023 (2024-10-31)**: prepared-food identity, gram-based component composition, portions, and prepared-food metadata. FoodData Central data is U.S. public-domain data released under CC0 1.0. Source: <https://fdc.nal.usda.gov/download-datasets/>.
- **USDA FoodData Central, SR Legacy (2018-04)**: canonical component descriptions, prepared state, kcal/100 g, and optional macro fields. Same public-domain/CC0 terms.
- **CalorieEstimator manually curated seed**: the original proof-of-concept recipes and aliases, retained without ID changes. These records are Tier B until their legacy nutrition values are individually remapped to USDA records.

The USDA ZIP archives are retained verbatim so the checked-in database can be reproduced without thousands of API calls. Source record IDs, URLs, release names, license, confidence, and verification state are written to `recipe_provenance` and `ingredient_nutrition`.

## Investigated but not imported

- **Wikidata**: a small reviewed CC0 entity snapshot enriches seven unambiguous RecipeIDs with source-backed labels and aliases in priority languages. It is not used as recipe-composition authority. Generic entities are not mapped onto narrower recipe variants. <https://www.wikidata.org/wiki/Wikidata:Licensing>
- **TheMealDB**: the adapter boundary remains intentionally disabled. Current terms allow API copying but prohibit app-store publication under free API usage and direct production users to a paid supporter key. Enabling it requires a paid account, attribution review, and source-by-source ingredient normalization. <https://themealdb.com/terms_of_use.php>
- **Open Food Facts**: excluded from the combined core database because its ODbL share-alike terms require a separate legal/architecture decision; it is also principally a packaged-product source. <https://world.openfoodfacts.org/terms-of-use>
- **Wikibooks and aggregated recipe datasets**: excluded because CC-BY-SA or unclear upstream licensing is not compatible with this core CC0/project-authored bundle without additional obligations and per-source review.

## Prepared-state policy

FNDDS component weights are final source gram weights. Each component is linked to the exact SR Legacy food record used by USDA, and the nutrition lookup key is the stable SR code rather than a generic English substring. `raw`, `cooked`, `boiled`, `fried`, `roasted`, `grilled`, `baked`, `drained`, and `smoked` states are preserved when explicitly present in the SR description; otherwise the record is marked `as_listed`. The build never substitutes dry grain nutrition for a cooked record or silently rescales a partially mapped recipe.

## Rebuild

```sh
Scripts/fetch/fetch_usda.sh  # only when refreshing the verbatim source archives
Scripts/build_recipe_database.sh
swift test
```

Rejected records and their exact reasons are written to `Data/Reports/food_database_build.json`.
