#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from fooddb.pipeline import build


if __name__ == "__main__":
    repository = SCRIPT_DIR.parent
    print(json.dumps(build(repository)["result"], indent=2, ensure_ascii=False))
