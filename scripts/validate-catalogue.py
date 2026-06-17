#!/usr/bin/env python3
"""Validate meta/catalogue.yml against meta/catalogue.schema.json and
check that every referenced playbook file exists.

Run from repo root.
"""
import json
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
CATALOGUE = ROOT / "meta" / "catalogue.yml"
SCHEMA = ROOT / "meta" / "catalogue.schema.json"


def main() -> int:
    catalogue = yaml.safe_load(CATALOGUE.read_text())
    schema = json.loads(SCHEMA.read_text())
    validator = Draft202012Validator(schema)

    errors = list(validator.iter_errors(catalogue))
    for err in errors:
        path = ".".join(str(p) for p in err.path)
        print(f"[schema] {path}: {err.message}", file=sys.stderr)

    seen_keys: set[str] = set()
    for entry in catalogue.get("entries", []):
        key = entry.get("key", "<missing>")
        if key in seen_keys:
            print(f"[dup-key] {key}", file=sys.stderr)
            errors.append(True)
        seen_keys.add(key)

        playbook = ROOT / entry.get("playbook", "")
        if not playbook.exists():
            print(f"[missing-playbook] {key} → {entry.get('playbook')}", file=sys.stderr)
            errors.append(True)

    if errors:
        print(f"FAIL: {len(errors)} issue(s)", file=sys.stderr)
        return 1
    print(f"OK: {len(catalogue.get('entries', []))} entries valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
