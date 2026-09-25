#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_sql="$repository_root/Data/recipes.sql"
output_database="$repository_root/Sources/CalorieEstimator/Resources/Recipes.sqlite3"
temporary_database=$(mktemp "${TMPDIR:-/tmp}/calorie-estimator-recipes.XXXXXX")
trap 'rm -f "$temporary_database"' EXIT

sqlite3 "$temporary_database" < "$source_sql"
foreign_key_errors=$(sqlite3 "$temporary_database" 'PRAGMA foreign_key_check;')
ratio_errors=$(sqlite3 "$temporary_database" 'SELECT recipe_id FROM recipe_ingredients GROUP BY recipe_id HAVING abs(sum(ratio) - 1.0) > 0.001;')

if [ -n "$foreign_key_errors" ] || [ -n "$ratio_errors" ]; then
    echo "Recipe database validation failed" >&2
    exit 1
fi

mkdir -p "$(dirname -- "$output_database")"
mv "$temporary_database" "$output_database"
