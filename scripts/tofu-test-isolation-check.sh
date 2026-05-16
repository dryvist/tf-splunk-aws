#!/usr/bin/env bash
# CI gate enforcing docs/terraform-testing-standards.md §7.
#
# Three checks, all blocking:
#   1. Full suite passes.
#   2. Every test file passes in isolation. Detects override_module leakage
#      across files.
#   3. mock_provider name+alias set is consistent across every test file.
#      Detects mock drift.
#
# Run from the repo root or any subdirectory; the script resolves modules/.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
tests_dir="${repo_root}/modules/tests"

if [ ! -d "$tests_dir" ]; then
  echo "no tests dir at $tests_dir" >&2
  exit 1
fi

shopt -s nullglob
test_files=("$tests_dir"/*.tftest.hcl)
shopt -u nullglob

if [ "${#test_files[@]}" -eq 0 ]; then
  echo "no .tftest.hcl files under $tests_dir" >&2
  exit 1
fi

cd "${repo_root}/modules"

echo ">>> Check 1: full suite"
tofu test -no-color

echo ">>> Check 2: per-file isolation"
# Pre-existing isolation failures are tracked as repo issues and excluded here
# rather than via bypassing the check. Add new entries only with a linked issue
# in the comment.
exclude_files=(
  # tests/security.tftest.hcl: nat/splunk SG output equality assertion collides
  # under mock_provider random ID generation.
  # Tracked: https://github.com/JacobPEvans/tf-splunk-aws/issues/183
  "tests/security.tftest.hcl"
)
isolation_failures=()
for f in "${test_files[@]}"; do
  rel="${f#${repo_root}/modules/}"
  skip=0
  for x in "${exclude_files[@]}"; do
    [ "$rel" = "$x" ] && skip=1 && break
  done
  if [ "$skip" -eq 1 ]; then
    echo "  -- $rel (excluded; see script comments)"
    continue
  fi
  echo "  -> $rel"
  if ! tofu test -filter="$rel" -no-color >/dev/null 2>&1; then
    isolation_failures+=("$rel")
  fi
done
if [ "${#isolation_failures[@]}" -gt 0 ]; then
  echo "isolation failures (run tofu test -filter=<file> to debug):" >&2
  printf '  %s\n' "${isolation_failures[@]}" >&2
  exit 1
fi

echo ">>> Check 3: mock_provider drift"
# Extract (provider_name, alias_or_default) pairs by walking each mock_provider
# block. `grep` on the directive line alone misses aliases on subsequent lines
# and `sort -u` collapses two aliased blocks for the same provider into one,
# making alias drift invisible.
extract_pairs() {
  awk '
    /^[[:space:]]*mock_provider[[:space:]]+"[^"]+"/ {
      match($0, /"[^"]+"/); name=substr($0, RSTART+1, RLENGTH-2);
      if (match($0, /\{[[:space:]]*\}/)) { print name " <default>"; next }
      in_block=1; alias=""; next
    }
    in_block && /^[[:space:]]*alias[[:space:]]*=[[:space:]]*"[^"]+"/ {
      match($0, /"[^"]+"[[:space:]]*$/); alias=substr($0, RSTART+1, RLENGTH-2);
      gsub(/[[:space:]]+$/, "", alias); next
    }
    in_block && /^[[:space:]]*}[[:space:]]*$/ {
      if (alias == "") alias = "<default>";
      print name " " alias;
      in_block=0; name=""; alias=""; next
    }
  ' "$1" | sort -u
}
canon=$(extract_pairs "${test_files[0]}")
for f in "${test_files[@]}"; do
  this=$(extract_pairs "$f")
  if [ "$this" != "$canon" ]; then
    echo "mock_provider drift in $f vs ${test_files[0]}:" >&2
    diff <(echo "$canon") <(echo "$this") >&2 || true
    exit 1
  fi
done

echo "All three checks passed."
