#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
destination="$repository_root/DataSources/usda"
mkdir -p "$destination"

curl -L --fail --retry 2 \
  -o "$destination/FoodData_Central_survey_food_json_2024-10-31.zip" \
  "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip"
curl -L --fail --retry 2 \
  -o "$destination/FoodData_Central_sr_legacy_food_json_2018-04.zip" \
  "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip"

(
  cd "$destination"
  shasum -a 256 -c SHA256SUMS
)
