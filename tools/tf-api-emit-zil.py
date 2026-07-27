#!/usr/bin/env python3
"""
Emit a ZIL model file from the Transfer Family API schema JSON.

Reads tf_api_schema.json (produced by tf-api-extract.py) and emits
ZIL USE statements that populate the TF_OPERATION / TF_FIELD /
TF_VALID_VALUE / TF_DATA_TYPE / TF_DATA_TYPE_FIELD macros defined in
libsets/aws-transfer-family/tf-macros.zc.

The output is a self-contained .zc file that, when run through the ZIL
engine with the tf-macros libset, gives you a queryable model of the
entire Transfer Family API surface.

Usage:
    python3 tools/tf-api-emit-zil.py
    python3 tools/tf-api-emit-zil.py --schema examples/generated/tf_api_schema.json
                                      --out    examples/generated/tf_api_model.zc
                                      --module aws.transfer.family.api.model
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Dict, List, Optional


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _token(raw: str) -> str:
    """Convert a raw string to a valid ZIL identifier token."""
    t = re.sub(r"[^A-Za-z0-9_]+", "_", raw.strip().lower())
    t = re.sub(r"_+", "_", t).strip("_")
    if not t:
        return "x"
    if t[0].isdigit():
        t = f"n_{t}"
    return t


def _action_verb(op_name: str) -> str:
    """Extract the CRUD verb prefix from an operation name."""
    for verb in ("Create", "Delete", "Describe", "Update", "List",
                 "Import", "Start", "Stop", "Test", "Tag", "Untag",
                 "Send", "TagResource", "UntagResource"):
        if op_name.startswith(verb):
            return _token(verb)
    return "other"


def _resource_type(op_name: str) -> str:
    """Extract the resource type suffix from an operation name."""
    for verb in ("Create", "Delete", "Describe", "Update", "List",
                 "Import", "Start", "Stop", "Test", "Tag", "Untag",
                 "Send"):
        if op_name.startswith(verb):
            suffix = op_name[len(verb):]
            if suffix:
                return _token(suffix)
    return _token(op_name)


def _zc_string(value: str) -> str:
    """Wrap a value in ZIL string quotes if it contains spaces or special chars."""
    if re.search(r"[\s\(\)\[\]#@{}]", value):
        # Escape internal double quotes
        escaped = value.replace('"', '\\"')
        return f'"{escaped}"'
    return value


# ---------------------------------------------------------------------------
# Emitter
# ---------------------------------------------------------------------------

class ZilEmitter:
    def __init__(self, module: str):
        self._lines: List[str] = [
            f"MODULE {module}.",
            "",
            "// Generated from tf_api_schema.json by tf-api-emit-zil.py.",
            "// Do not edit by hand — re-run the extractor + emitter instead.",
            "",
        ]

    def blank(self) -> None:
        self._lines.append("")

    def comment(self, text: str) -> None:
        self._lines.append(f"// {text}")

    def use(self, macro: str, *args) -> None:
        rendered_args = ", ".join(_zc_string(str(a)) for a in args)
        self._lines.append(f"USE {macro}({rendered_args}).")

    def render(self) -> str:
        return "\n".join(self._lines) + "\n"


# ---------------------------------------------------------------------------
# Main emission logic
# ---------------------------------------------------------------------------

def emit_operations(emitter: ZilEmitter, operations: List[Dict]) -> None:
    emitter.comment("=" * 68)
    emitter.comment("API Operations")
    emitter.comment("=" * 68)
    emitter.blank()

    for op in operations:
        name = op["name"]
        op_id = _token(name)
        resource = _resource_type(name)
        action = _action_verb(name)

        emitter.comment(f"--- {name} ---")
        emitter.use("TF_OPERATION", op_id, resource, action)

        for field in op.get("request_fields", []):
            fname = field["name"]
            ftype = field.get("type", "") or "string"
            required = field.get("required", "no")
            field_id = _token(fname)
            resource_type_tok = _token(name)

            emitter.use("TF_FIELD", resource_type_tok, field_id, _token(ftype), required)

            for val in field.get("valid_values", []):
                emitter.use("TF_VALID_VALUE", resource_type_tok, field_id, _token(val))

        emitter.blank()


def emit_data_types(emitter: ZilEmitter, data_types: List[Dict]) -> None:
    emitter.comment("=" * 68)
    emitter.comment("Data Types")
    emitter.comment("=" * 68)
    emitter.blank()

    for dt in data_types:
        name = dt["name"]
        dt_id = _token(name)

        # Use first ~6 words of description as a description token
        desc_words = re.sub(r"\s+", " ", dt.get("description", "")).strip().split()
        desc_tok = _token(" ".join(desc_words[:6])) if desc_words else dt_id

        emitter.comment(f"--- {name} ---")
        emitter.use("TF_DATA_TYPE", dt_id, desc_tok)

        for field in dt.get("fields", []):
            fname = field["name"]
            ftype = field.get("type", "") or "string"
            required = field.get("required", "no")
            field_id = _token(fname)

            emitter.use("TF_DATA_TYPE_FIELD", dt_id, field_id, _token(ftype), required)

            for val in field.get("valid_values", []):
                emitter.use("TF_VALID_VALUE", dt_id, field_id, _token(val))

        emitter.blank()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--schema",
        default=str(repo_root / "examples/generated/tf_api_schema.json"),
        help="Path to tf_api_schema.json (output of tf-api-extract.py)",
    )
    parser.add_argument(
        "--out",
        default=str(repo_root / "examples/generated/tf_api_model.zc"),
        help="Output .zc file path",
    )
    parser.add_argument(
        "--module",
        default="aws.transfer.family.api.model",
        help="ZIL MODULE name for the generated file",
    )
    args = parser.parse_args()

    schema_path = Path(args.schema).resolve()
    if not schema_path.exists():
        raise SystemExit(f"Schema not found: {schema_path}\nRun tf-api-extract.py first.")

    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    operations = schema.get("operations", [])
    data_types = schema.get("data_types", [])

    emitter = ZilEmitter(args.module)

    emitter.comment(f"Source: {schema.get('source_pdf', 'unknown')}")
    emitter.comment(f"Stats:  {schema.get('stats', {})}")
    emitter.blank()

    emit_operations(emitter, operations)
    emit_data_types(emitter, data_types)

    out_path = Path(args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(emitter.render(), encoding="utf-8")

    print(f"[tf-emit] operations={len(operations)}  data_types={len(data_types)}")
    print(f"[tf-emit] → {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
