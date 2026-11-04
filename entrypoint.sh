#!/usr/bin/env bash
# Entrypoint for the GitHub Action.
# Maps action.yml inputs (positional args) to check.sh flags,
# runs the check, writes outputs, and translates fail-on policy.

set -uo pipefail

SCAN_DIR="${1:-.}"
ONLINE="${2:-false}"
FAIL_ON="${3:-fail}"
JSON_OUTPUT="${4:-}"
BAD_VERSIONS_FILE="${5:-}"
GHSA_ID="${6:-GHSA-g7cv-rxg3-hmpx}"

# Workspace: the directory relative paths (scan-dir, json-output,
# bad-versions-file) are resolved against.
#   - Inside GitHub Actions the runner sets GITHUB_WORKSPACE: use it as is.
#   - Outside Actions (plain `docker run`, as documented in the README) it is
#     unset: use /github/workspace if something is mounted there, otherwise
#     the absolute scan dir (the bind mount, e.g. /scan), otherwise the
#     current directory (`docker run -w`).
if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
  WORKSPACE="$GITHUB_WORKSPACE"
elif [[ -d /github/workspace ]]; then
  WORKSPACE="/github/workspace"
elif [[ "$SCAN_DIR" = /* && -d "$SCAN_DIR" ]]; then
  WORKSPACE="$SCAN_DIR"
else
  WORKSPACE="$PWD"
fi

# Resolve scan dir relative to workspace
if [[ "$SCAN_DIR" = /* ]]; then
  RESOLVED_SCAN_DIR="$SCAN_DIR"
else
  RESOLVED_SCAN_DIR="$WORKSPACE/$SCAN_DIR"
fi

cd "$WORKSPACE" || { echo "::error::Cannot cd to workspace: $WORKSPACE"; exit 3; }

# Build check.sh argument list
ARGS=( --scan-dir "$RESOLVED_SCAN_DIR" --json --no-color )

if [[ "$ONLINE" == "true" || "$ONLINE" == "1" || "$ONLINE" == "yes" ]]; then
  ARGS+=( --online --ghsa "$GHSA_ID" )
fi

if [[ -n "$BAD_VERSIONS_FILE" ]]; then
  if [[ "$BAD_VERSIONS_FILE" = /* ]]; then
    ARGS+=( --bad-versions-file "$BAD_VERSIONS_FILE" )
  else
    ARGS+=( --bad-versions-file "$WORKSPACE/$BAD_VERSIONS_FILE" )
  fi
fi

# Run the checker, capture JSON
JSON_TMP="$(mktemp -t findings.XXXXXX.json)"
bash /action/check.sh "${ARGS[@]}" > "$JSON_TMP"
RAW_EXIT=$?

# Optionally place the JSON inside the workspace so subsequent steps can read it.
if [[ -n "$JSON_OUTPUT" ]]; then
  if [[ "$JSON_OUTPUT" = /* ]]; then
    DEST="$JSON_OUTPUT"
  else
    DEST="$WORKSPACE/$JSON_OUTPUT"
  fi
  if cp "$JSON_TMP" "$DEST"; then
    # The Docker action runs as root; subsequent steps (e.g. actions/upload-artifact)
    # run as the runner user and cannot read root-owned files in $GITHUB_WORKSPACE.
    chmod 0644 "$DEST" 2>/dev/null || true
    echo "::notice::Findings JSON written to $DEST"
  else
    # Do not claim a file that is not there. The usual cause outside Actions
    # is a bind mount not writable by the image user (UID 1001): run with
    # --user "$(id -u):$(id -g)" so the container writes as the mount owner.
    echo "::error::Could not write findings JSON to $DEST (is the mounted directory writable by UID $(id -u)?)"
  fi
fi

# Parse summary from JSON
if command -v jq >/dev/null 2>&1; then
  PASSED=$(jq -r '.summary.passed // 0'   "$JSON_TMP" 2>/dev/null || echo 0)
  WARNINGS=$(jq -r '.summary.warnings // 0' "$JSON_TMP" 2>/dev/null || echo 0)
  FAILED=$(jq -r '.summary.failed // 0'   "$JSON_TMP" 2>/dev/null || echo 0)
else
  PASSED=0; WARNINGS=0; FAILED=0
fi

# Emit GitHub Action outputs
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "passed=$PASSED"
    echo "warnings=$WARNINGS"
    echo "failed=$FAILED"
    echo "exit-code=$RAW_EXIT"
    echo "findings-path=${JSON_OUTPUT:-}"
  } >> "$GITHUB_OUTPUT"
fi

# Annotations for findings (max 10 to avoid spam)
if command -v jq >/dev/null 2>&1; then
  jq -r '.findings[]? | select(.severity=="fail" or .severity=="warn")
    | "::\(.severity=="fail" and "error" or "warning")::[\(.check)] \(.message)\((.path // "") | if . == "" then "" else " — \(.)" end)"' \
    "$JSON_TMP" 2>/dev/null | head -10
fi

# Print a human-readable summary to the step log
echo ""
echo "──────────────────────────────────────────────"
echo " tanstack-compromise-checker: ${PASSED} passed, ${WARNINGS} warnings, ${FAILED} failed"
echo " advisory: $GHSA_ID   online: $ONLINE"
echo " scan dir: $RESOLVED_SCAN_DIR"
echo "──────────────────────────────────────────────"

# Apply fail-on policy
case "$FAIL_ON" in
  never)  exit 0 ;;
  warn)   if [[ "$RAW_EXIT" -ge 1 ]]; then exit "$RAW_EXIT"; else exit 0; fi ;;
  fail|*) if [[ "$RAW_EXIT" -ge 2 ]]; then exit "$RAW_EXIT"; else exit 0; fi ;;
esac