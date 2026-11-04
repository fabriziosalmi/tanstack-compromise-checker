#!/usr/bin/env bash
# Regression test for the Docker image used the way the README documents it:
#
#   docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/scan <image> \
#     /scan true fail tanstack-findings.json '' GHSA-g7cv-rxg3-hmpx
#
# This is plain `docker run`, not the GitHub Actions container runtime, so
# GITHUB_WORKSPACE is not set inside the container (docker run never forwards
# the host environment). Asserts: clean fixture exits 0, compromised fixture
# exits 2, and the findings JSON lands in the mounted directory.
#
# Builds the image from the repo root unless TCC_IMAGE names an existing one.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
IMAGE="${TCC_IMAGE:-tcc-docker-run-test:local}"

if [[ -z "${TCC_IMAGE:-}" ]]; then
  echo "building $IMAGE from $ROOT"
  docker build -q -t "$IMAGE" "$ROOT" >/dev/null || { echo "docker build failed"; exit 1; }
fi

# Copy the fixtures to a path without 'tests/fixtures' or 'fixtures' in it:
# check.sh prunes those patterns by design (same reason as in smoke.sh).
TMPSCAN="$(mktemp -d -t tcc-docker-scan.XXXXXX)"
cp -R "$HERE/fixtures" "$TMPSCAN/scenarios"
trap 'rm -rf "$TMPSCAN"' EXIT

PASS=0
FAIL=0

json_failed() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.summary.failed // empty' "$file" 2>/dev/null
  else
    grep -oE '"failed"[[:space:]]*:[[:space:]]*[0-9]+' "$file" 2>/dev/null | head -1 | grep -oE '[0-9]+'
  fi
}

run_case() {
  local name="$1" dir="$2" want_exit="$3" want_failed="$4"
  local log="$TMPSCAN/$name.log"
  (
    cd "$dir" || exit 99
    docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/scan "$IMAGE" \
      /scan true fail tanstack-findings.json '' GHSA-g7cv-rxg3-hmpx
  ) >"$log" 2>&1
  local got_exit=$?
  local json="$dir/tanstack-findings.json"
  local got_failed="missing"
  [[ -f "$json" ]] && got_failed="$(json_failed "$json")"

  local ok=1
  [[ "$got_exit" == "$want_exit" ]] || ok=0
  case "$want_failed" in
    zero)    [[ "$got_failed" == "0" ]] || ok=0 ;;
    nonzero) [[ "$got_failed" =~ ^[0-9]+$ && "$got_failed" != "0" ]] || ok=0 ;;
  esac

  if [[ "$ok" -eq 1 ]]; then
    printf '  OK   %-28s exit=%s json.failed=%s\n' "$name" "$got_exit" "$got_failed"
    PASS=$((PASS+1))
  else
    printf '  FAIL %-28s exit=%s (expected %s) json.failed=%s (expected %s)\n' \
      "$name" "$got_exit" "$want_exit" "$got_failed" "$want_failed"
    sed 's/^/       | /' "$log" | tail -15
    FAIL=$((FAIL+1))
  fi
}

echo "docker run tests for $IMAGE"
echo ""

run_case "clean-project"       "$TMPSCAN/scenarios/clean-project"       0 zero
run_case "compromised-project" "$TMPSCAN/scenarios/compromised-project" 2 nonzero

echo ""
echo "  passed: $PASS"
echo "  failed: $FAIL"

[[ "$FAIL" -eq 0 ]] || exit 1
