#!/usr/bin/env bash
# Run all pure-Luau spec files under tests/ with lune.
# Usage: bash scripts/test.sh [pattern]
#   bash scripts/test.sh           # run every *.spec.luau
#   bash scripts/test.sh hex       # only specs matching "hex"
set -euo pipefail

# Make rokit-managed tool shims discoverable on PATH.
export PATH="$HOME/.rokit/bin:$PATH"

if ! command -v lune >/dev/null 2>&1; then
  echo "lune not found. Run 'rokit install' from the repo root first." >&2
  exit 1
fi

pattern="${1:-}"
fail=0
pass=0
failed_specs=()

shopt -s nullglob
for spec in tests/*.spec.luau; do
  if [ -n "$pattern" ] && [[ "$spec" != *"$pattern"* ]]; then
    continue
  fi
  printf '== %s ==\n' "$spec"
  if lune run "$spec"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed_specs+=("$spec")
  fi
done

printf '\n----\n%d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'Failed:\n'
  for s in "${failed_specs[@]}"; do printf '  %s\n' "$s"; done
  exit 1
fi
