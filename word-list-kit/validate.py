#!/usr/bin/env python3
"""Validate Kotoba v1 JSON with Python's standard library (no network or pip)."""
import argparse
import json
import math
from pathlib import Path
import re
import sys

SCHEMA_PATH = Path(__file__).with_name("word-list.schema.json")
MAX_BYTES = 20 * 1024 * 1024


class Invalid(ValueError):
    pass


def child(path, key):
    return path + "[" + json.dumps(key, ensure_ascii=False) + "]"


def fail(path, message):
    raise Invalid(f"{path}: {message}")


def check(value, rule, schema, path="$"):
    """Walk the exact assertion vocabulary used by the bundled 2020-12 schema."""
    if "$ref" in rule:
        check(value, schema["$defs"][rule["$ref"].split("/")[-1]], schema, path)
    for sub in rule.get("allOf", []):
        check(value, sub, schema, path)
    if "not" in rule:
        try:
            check(value, rule["not"], schema, path)
        except Invalid:
            pass
        else:
            fail(path, "reserved value is not allowed")
    kind = rule.get("type")
    valid = {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "boolean": isinstance(value, bool),
        "integer": (isinstance(value, int) and not isinstance(value, bool))
        or (isinstance(value, float) and math.isfinite(value) and value.is_integer()),
    }
    if kind and not valid[kind]:
        fail(path, f"expected {kind}")
    if "const" in rule and (value != rule["const"] or isinstance(value, bool) != isinstance(rule["const"], bool)):
        fail(path, f"expected {rule['const']!r}")
    if "enum" in rule and value not in rule["enum"]:
        fail(path, f"expected one of {rule['enum']!r}")
    if isinstance(value, dict):
        props = rule.get("properties", {})
        for key in rule.get("required", []):
            if key not in value:
                fail(child(path, key), "required field is missing")
        for key, item in value.items():
            if key in props:
                check(item, props[key], schema, child(path, key))
            elif rule.get("additionalProperties") is False:
                fail(child(path, key), "unknown field")
    if isinstance(value, list):
        if len(value) < rule.get("minItems", 0):
            fail(path, f"requires at least {rule['minItems']} item(s)")
        if "maxItems" in rule and len(value) > rule["maxItems"]:
            fail(path, f"exceeds {rule['maxItems']} items")
        for index, item in enumerate(value):
            if "items" in rule:
                check(item, rule["items"], schema, f"{path}[{index}]")
    if isinstance(value, str):
        if len(value) < rule.get("minLength", 0):
            fail(path, "must not be empty")
        if len(value) > rule.get("maxLength", 10000):
            fail(path, f"exceeds {rule.get('maxLength', 10000)} characters")
        if "pattern" in rule and re.search(rule["pattern"], value) is None:
            fail(path, "does not match required pattern (check ID, language tag or safe HTTPS URL)")


def reject_constant(value):
    fail("$", f"non-JSON numeric constant {value}")


def validate(path, allow_builtin=False):
    # Bounded read also handles a file growing after stat, and special files.
    with path.open("rb") as stream:
        raw = stream.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        fail("$", f"file exceeds {MAX_BYTES} bytes (20 MiB)")
    pairs = []

    def remember_pairs(items):
        result = dict(items)
        pairs.append((result, items))
        return result

    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=remember_pairs,
                           parse_constant=reject_constant)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail("$", f"invalid UTF-8 JSON: {exc}")
    # Preserve object paths while rejecting ambiguous duplicate JSON members.
    originals = {id(obj): items for obj, items in pairs}

    def check_members(item, field="$", depth=0):
        if depth > 100:
            fail(field, "JSON nesting exceeds 100 levels")
        if isinstance(item, dict):
            seen = set()
            for key, val in originals[id(item)]:
                if key in seen:
                    fail(child(field, key), "duplicate JSON object member")
                seen.add(key)
                check_members(val, child(field, key), depth + 1)
        elif isinstance(item, list):
            for index, val in enumerate(item):
                check_members(val, f"{field}[{index}]", depth + 1)

    check_members(value)
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    check(value, schema, schema)
    if not allow_builtin and value["id"] == "ielts":
        fail('$["id"]', "reserved builtin ID ielts cannot be imported (use --allow-builtin only to audit shipped data)")
    seen = set()
    for index, entry in enumerate(value["entries"]):
        if entry["id"] in seen:
            fail(f'$["entries"][{index}]["id"]', "duplicate entry ID")
        seen.add(entry["id"])
    return len(value["entries"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-builtin", action="store_true",
                        help="allow reserved ielts only when auditing shipped builtin data; not for imports")
    parser.add_argument("files", nargs="+", type=Path, help="UTF-8 .json word list(s)")
    args = parser.parse_args()
    failed = False
    for path in args.files:
        try:
            count = validate(path, allow_builtin=args.allow_builtin)
            print(f"OK {path}: {count} entries")
        except (Invalid, OSError, RecursionError, ValueError, OverflowError) as exc:
            failed = True
            message = str(exc) if isinstance(exc, Invalid) else f"$: {exc}"
            print(f"ERROR {path}: {message}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
