# Wikidata adapter status

Wikidata structured data is CC0 and approved for identity, taxonomy, cuisine/region metadata, and multilingual aliases. It is not recipe-composition authority.

`entities.json` is a reproducible API snapshot for a deliberately small reviewed mapping. The importer currently enriches carbonara, falafel, generic sushi, borscht, bibimbap, hummus, and ratatouille in priority languages. Generic Wikidata entities such as “ramen”, “paella”, and “pad thai” are intentionally not mapped to narrower shoyu, seafood, or shrimp variants. Label similarity alone is never treated as identity.
