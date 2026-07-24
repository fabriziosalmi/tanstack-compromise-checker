#!/usr/bin/env bash
# Smoke tests for check.sh.
# Each case asserts on `.summary.failed` from the JSON output, so warnings that
# come from the host (e.g. an existing ~/.npmrc) don't poison the test result.
# HOME is isolated to a temp dir so the host-level probes have nothing to see.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/check.sh"
TMPHOME="$(mktemp -d -t tcc-smoke-home.XXXXXX)"
# Copy the fixtures out of tests/fixtures/ so the path the script sees does
# not contain 'tests/fixtures/' — check.sh prunes that pattern by design so
# the self-test workflow does not flag the deliberately-compromised fixture.
TMPSCAN="$(mktemp -d -t tcc-smoke-scan.XXXXXX)"
# Copy fixtures into a path that does NOT contain any of check.sh's prune
# patterns (tests/fixtures, fixtures, templates, __tests__, __fixtures__).
cp -R "$HERE/fixtures" "$TMPSCAN/scenarios"
trap 'rm -rf "$TMPHOME" "$TMPSCAN"' EXIT

PASS=0
FAIL=0

failed_count() {
  local out="$1"
  if command -v jq >/dev/null 2>&1; then
    local val
    val="$(jq -r '.summary.failed // 0' <<<"$out" 2>/dev/null)"
    if [[ "$val" =~ ^[0-9]+$ ]]; then
      echo "$val"
    else
      echo "0"
    fi
  else
    local match
    match="$(grep -oE '"failed"[[:space:]]*:[[:space:]]*[0-9]+' <<<"$out" 2>/dev/null | head -1)"
    if [[ -n "$match" ]]; then
      echo "$match" | grep -oE '[0-9]+'
    else
      echo "0"
    fi
  fi
}

run_no_failures() {
  local name="$1" scan_dir="$2"
  local out
  out="$(HOME="$TMPHOME" bash "$SCRIPT" --scan-dir "$scan_dir" --json --no-color 2>/dev/null)"
  local fc
  fc="$(failed_count "$out")"
  if [[ "$fc" == "0" ]]; then
    printf '  OK   %-40s failed=0\n' "$name"
    PASS=$((PASS+1))
  else
    printf '  FAIL %-40s failed=%s (expected 0)\n' "$name" "$fc"
    FAIL=$((FAIL+1))
  fi
}

run_some_failures() {
  local name="$1" scan_dir="$2"
  local out
  out="$(HOME="$TMPHOME" bash "$SCRIPT" --scan-dir "$scan_dir" --json --no-color 2>/dev/null)"
  local fc
  fc="$(failed_count "$out")"
  if [[ -n "$fc" && "$fc" != "0" ]]; then
    printf '  OK   %-40s failed=%s\n' "$name" "$fc"
    PASS=$((PASS+1))
  else
    printf '  FAIL %-40s failed=%s (expected >=1)\n' "$name" "$fc"
    FAIL=$((FAIL+1))
  fi
}

run_exit_code() {
  local name="$1" expected="$2"
  shift 2
  HOME="$TMPHOME" bash "$SCRIPT" "$@" >/dev/null 2>&1
  local actual=$?
  if [[ "$actual" == "$expected" ]]; then
    printf '  OK   %-40s exit=%s\n' "$name" "$actual"
    PASS=$((PASS+1))
  else
    printf '  FAIL %-40s exit=%s (expected %s)\n' "$name" "$actual" "$expected"
    FAIL=$((FAIL+1))
  fi
}

echo "smoke tests for check.sh"
echo ""

run_no_failures   "clean fixture: no failures"        "$TMPSCAN/scenarios/clean-project"
run_some_failures "compromised fixture: >=1 failure"  "$TMPSCAN/scenarios/compromised-project"
run_exit_code     "unknown flag exits 3"              3 --nope
run_exit_code     "--help exits 0"                    0 --help
run_exit_code     "compromised fixture exits 2"       2 --scan-dir "$TMPSCAN/scenarios/compromised-project" --no-color --quiet

echo ""
echo "  passed: $PASS"
echo "  failed: $FAIL"

[[ "$FAIL" -eq 0 ]] || exit 1
