#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

python3 "$repository_root/Scripts/generate_food_database.py"
python3 "$repository_root/Scripts/validate_food_database.py"
