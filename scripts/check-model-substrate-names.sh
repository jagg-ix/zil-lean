#!/usr/bin/env bash
# The model substrate owns the macro prefixes MODEL_ and SCENARIO_ and the relation prefixes
# model_ and scenario_. Fail when another library, example or libset defines or emits one.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
substrate="libsets/model-substrate"
failed=0

# Every other .zc file that ships with the engine (substrate files, its example and its fixtures excluded).
others() {
  find lib libsets examples -name '*.zc' \
    -not -path "$substrate/*" -not -path 'examples/model-substrate/*' | sort
}

foreign_macros="$(others | xargs grep -n -i -E '^[[:space:]]*MACRO[[:space:]]+(MODEL|SCENARIO)_' || true)"
if [[ -n "$foreign_macros" ]]; then
  echo "FAIL: a library other than the substrate defines a MODEL_ or SCENARIO_ macro:" >&2
  echo "$foreign_macros" >&2
  failed=1
fi

foreign_relations="$(others | xargs grep -n -E '#(model|scenario)_[a-z_]+[@ ]' || true)"
if [[ -n "$foreign_relations" ]]; then
  echo "FAIL: a library other than the substrate uses a model_ or scenario_ relation:" >&2
  echo "$foreign_relations" >&2
  failed=1
fi

# The substrate keeps to its own prefixes.
bad_macros="$(grep -h -i -E '^[[:space:]]*MACRO[[:space:]]+' "$substrate"/*.zc \
  | awk '{print $2}' | sed 's/(.*//' | grep -v -E '^(MODEL|SCENARIO)_' || true)"
if [[ -n "$bad_macros" ]]; then
  echo "FAIL: the substrate defines a macro outside MODEL_ and SCENARIO_: $bad_macros" >&2
  failed=1
fi

bad_relations="$(grep -h -v -E '^[[:space:]]*//' "$substrate"/*.zc | grep -o -E '#[a-z_]+@' | sort -u \
  | grep -v -E '^#(model|scenario)_' || true)"
if [[ -n "$bad_relations" ]]; then
  echo "FAIL: the substrate emits a relation outside model_ and scenario_: $bad_relations" >&2
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
count="$(grep -h -i -E '^[[:space:]]*MACRO[[:space:]]+' "$substrate"/*.zc | wc -l | tr -d ' ')"
echo "model substrate names OK: $count macros, no collision with $(others | wc -l | tr -d ' ') other library files"
