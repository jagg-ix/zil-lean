#!/usr/bin/env python3
"""Audit the module-safe native engine and governance import closure.

This is the executable form of the checks in zil-engine-modularization-plan.md:
recompute the closure from the real imports, require every reachable ZIL source to
be a Lean module, and reject module-to-non-module edges.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

SEEDS = (
    "Zil.Engine.Query",
    "Zil.Engine.Provenance",
    "Zil.Impact",
    "Zil.ProofObligation",
    "Zil.TheoremAudit",
    "Zil.QueryGovernance",
)

REQUIRED_ENGINE = {
    "Zil.Core.Term",
    "Zil.Core.Attribute",
    "Zil.Core.Relation",
    "Zil.Core.Rule",
    "Zil.Core.Macro",
    "Zil.Core.Declaration",
    "Zil.Core.DeclarationSet",
    "Zil.Core.Program",
    "Zil.Core.Query",
    "Zil.Core.Userset",
    "Zil.Codec.Attribute",
    "Zil.Codec.Canonical",
    "Zil.Environment.Knowledge",
    "Zil.Profile.Core",
    "Zil.Engine.Query",
    "Zil.Engine.Provenance",
}

REQUIRED_GOVERNANCE = {
    "Zil.Impact",
    "Zil.ProofObligation",
    "Zil.TheoremAudit",
    "Zil.QueryGovernance",
}

IMPORT_RE = re.compile(
    r"^(?P<prefix>(?:public\s+meta\s+|public\s+|meta\s+)?)import\s+"
    r"(?P<module>Zil\.[A-Za-z0-9_.]+)\s*$",
    re.MULTILINE,
)


def module_path(module: str) -> Path:
    return REPO_ROOT / (module.replace(".", "/") + ".lean")


def read_source(module: str) -> str:
    path = module_path(module)
    if not path.is_file():
        raise FileNotFoundError(f"missing source for {module}: {path.relative_to(REPO_ROOT)}")
    return path.read_text(encoding="utf-8")


def first_nonempty_line(source: str) -> str:
    for line in source.splitlines():
        stripped = line.strip()
        if stripped:
            return stripped
    return ""


def imports(source: str) -> list[tuple[str, str]]:
    return [(match.group("prefix"), match.group("module")) for match in IMPORT_RE.finditer(source)]


def main() -> int:
    failures: list[str] = []
    seen: set[str] = set()
    pending = list(SEEDS)
    edges: list[tuple[str, str]] = []
    total_loc = 0

    while pending:
        module = pending.pop()
        if module in seen:
            continue
        seen.add(module)

        try:
            source = read_source(module)
        except FileNotFoundError as error:
            failures.append(str(error))
            continue

        total_loc += len(source.splitlines())
        if first_nonempty_line(source) != "module":
            failures.append(f"{module_path(module).relative_to(REPO_ROOT)} is not a module")

        for prefix, dependency in imports(source):
            edges.append((module, dependency))
            if not prefix.startswith("public"):
                failures.append(
                    f"{module} imports {dependency} without public import visibility"
                )
            try:
                dependency_source = read_source(dependency)
            except FileNotFoundError as error:
                failures.append(str(error))
                continue
            if first_nonempty_line(dependency_source) != "module":
                failures.append(
                    f"module-to-non-module edge: {module} -> {dependency}"
                )
            if dependency not in seen:
                pending.append(dependency)

    missing_engine = sorted(REQUIRED_ENGINE - seen)
    missing_governance = sorted(REQUIRED_GOVERNANCE - seen)
    if missing_engine:
        failures.append("engine closure omitted: " + ", ".join(missing_engine))
    if missing_governance:
        failures.append("governance closure omitted: " + ", ".join(missing_governance))

    if failures:
        print("module closure audit failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"module closure audit passed: {len(seen)} modules, {len(edges)} ZIL import edges, {total_loc} LOC")
    for module in sorted(seen):
        print(f"  {module}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
