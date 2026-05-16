#!/usr/bin/env bash
# check.sh — TanStack npm supply chain attack checker (v1.0.0)
# CVE-2026-45321 / GHSA-g7cv-rxg3-hmpx
# https://github.com/fabriziosalmi/tanstack-compromise-checker
#
# Usage:
#   bash check.sh [--scan-dir DIR] [--fix [--apply --yes]] [--json]
#                 [--online [--ghsa GHSA-ID]
#                  [--attack-window-start ISO --attack-window-end ISO]]
#                 [--bad-versions-file F] [--no-color] [--quiet] [-h]
#
# Exit codes: 0 clean | 1 warnings | 2 failures | 3 tool/usage error

set -uo pipefail

VERSION="1.0.0"

# ── Defaults ──────────────────────────────────────────────────────────────────
SCAN_DIR="${HOME}"
FIX=false
APPLY=false
YES=false
JSON_OUT=false
QUIET=false
NO_COLOR=false
EXTRA_BAD_FILE=""

# Online verification (registry + GHSA). Off by default — opt-in.
ONLINE_CHECK=false
GHSA_ID="GHSA-g7cv-rxg3-hmpx"
# Attack window in UTC, ISO 8601. Defaults set to the known TanStack incident window.
ATTACK_WINDOW_START="2026-05-11T19:00:00Z"
ATTACK_WINDOW_END="2026-05-11T20:00:00Z"

# ── Args ──────────────────────────────────────────────────────────────────────
print_help() {
  cat <<'EOF'
check.sh — TanStack npm supply chain attack checker
CVE-2026-45321 / GHSA-g7cv-rxg3-hmpx

Usage:
  bash check.sh [OPTIONS]

Options:
  --scan-dir DIR          Root directory to scan (default: $HOME)
  --fix                   Print recommended pin commands (dry-run by default)
  --apply                 With --fix: actually execute the suggested commands
  --yes, -y               Skip confirmation when --apply is used
  --json                  Emit findings as JSON to stdout (implies --quiet)
  --bad-versions-file F   Append entries (pkg@ver, one per line) to known-bad list
  --no-color              Disable ANSI colors
  --quiet, -q             Suppress per-check output, print only summary
  -h, --help              Show this help

Online verification (opt-in; requires curl + network):
  --online                Enable advisory fetch + registry publish-time check.
                          For each installed compromised package, query
                          registry.npmjs.org and FAIL if its publishTime falls
                          inside the attack window.
  --ghsa GHSA-ID          GHSA advisory ID to fetch (default: the TanStack one)
  --attack-window-start ISO   UTC ISO 8601 start (default: 2026-05-11T19:00:00Z)
  --attack-window-end ISO     UTC ISO 8601 end   (default: 2026-05-11T20:00:00Z)

Exit codes:
  0  Clean
  1  Warnings only
  2  Failures (compromise indicators present)
  3  Tool/usage error

Security note:
  Verify the SHA-256 of this script before piping to bash. See README.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-dir)
      [[ $# -lt 2 ]] && { echo "Error: --scan-dir requires an argument" >&2; exit 3; }
      SCAN_DIR="$2"; shift 2 ;;
    --fix)               FIX=true; shift ;;
    --apply)             APPLY=true; shift ;;
    --yes|-y)            YES=true; shift ;;
    --json)              JSON_OUT=true; QUIET=true; shift ;;
    --no-color)          NO_COLOR=true; shift ;;
    --quiet|-q)          QUIET=true; shift ;;
    --bad-versions-file)
      [[ $# -lt 2 ]] && { echo "Error: --bad-versions-file requires an argument" >&2; exit 3; }
      EXTRA_BAD_FILE="$2"; shift 2 ;;
    --online)            ONLINE_CHECK=true; shift ;;
    --ghsa)
      [[ $# -lt 2 ]] && { echo "Error: --ghsa requires an argument" >&2; exit 3; }
      GHSA_ID="$2"; shift 2 ;;
    --attack-window-start)
      [[ $# -lt 2 ]] && { echo "Error: --attack-window-start requires an argument" >&2; exit 3; }
      ATTACK_WINDOW_START="$2"; shift 2 ;;
    --attack-window-end)
      [[ $# -lt 2 ]] && { echo "Error: --attack-window-end requires an argument" >&2; exit 3; }
      ATTACK_WINDOW_END="$2"; shift 2 ;;
    -h|--help)           print_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; echo "Run with -h for help." >&2; exit 3 ;;
  esac
done

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ "$NO_COLOR" == false ]] && [[ "$JSON_OUT" == false ]]; then
  RED=$'\033[0;31m'; YEL=$'\033[0;33m'; GRN=$'\033[0;32m'
  CYN=$'\033[0;36m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
  RED=''; YEL=''; GRN=''; CYN=''; BLD=''; RST=''
fi

# ── SCAN_DIR validation ───────────────────────────────────────────────────────
if [[ ! -d "$SCAN_DIR" ]]; then
  echo "Error: scan dir does not exist: $SCAN_DIR" >&2
  exit 3
fi
SCAN_DIR_ABS="$(cd "$SCAN_DIR" 2>/dev/null && pwd -P)" || {
  echo "Error: cannot resolve scan dir: $SCAN_DIR" >&2; exit 3; }
case "$SCAN_DIR_ABS" in
  /|/bin|/sbin|/usr|/etc|/var|/lib|/lib64|/boot|/dev|/proc|/sys|/run)
    echo "Error: refusing to scan system directory: $SCAN_DIR_ABS" >&2
    exit 3 ;;
esac
SCAN_DIR="$SCAN_DIR_ABS"

# ── Compromised families ──────────────────────────────────────────────────────
COMPROMISED_PKGS=(
  "@tanstack/router" "@tanstack/react-router" "@tanstack/solid-router" "@tanstack/vue-router"
  "@tanstack/router-core" "@tanstack/router-cli" "@tanstack/router-vite-plugin"
  "@tanstack/router-plugin" "@tanstack/router-devtools" "@tanstack/router-generator"
  "@tanstack/router-server" "@tanstack/history" "@tanstack/start" "@tanstack/react-start"
  "@tanstack/solid-start" "@tanstack/vue-start" "@tanstack/react-start-server"
  "@tanstack/start-server-functions-fetcher" "@tanstack/start-server-functions-handler"
  "@tanstack/start-vite-plugin" "@tanstack/eslint-plugin-router" "@tanstack/zod-adapter"
  "@tanstack/valibot-adapter" "@tanstack/arktype-adapter" "@tanstack/react-router-ssr-query"
)

# Known malicious versions (partial list — extend via --bad-versions-file).
KNOWN_BAD_VERSIONS=(
  "@tanstack/react-router@1.169.5" "@tanstack/react-router@1.169.8"
  "@tanstack/history@1.161.9" "@tanstack/history@1.161.12"
  "@tanstack/eslint-plugin-router@1.161.9" "@tanstack/eslint-plugin-router@1.161.12"
  "@tanstack/router-cli@1.166.46" "@tanstack/router-cli@1.166.49"
  "@tanstack/router-vite-plugin@1.169.5" "@tanstack/router-vite-plugin@1.169.8"
  "@tanstack/router-core@1.169.5" "@tanstack/router-core@1.169.8"
  "@tanstack/router-plugin@1.169.5" "@tanstack/router-plugin@1.169.8"
  "@tanstack/router-devtools@1.169.5" "@tanstack/router-devtools@1.169.8"
  "@tanstack/router-generator@1.169.5" "@tanstack/router-generator@1.169.8"
  "@tanstack/start@1.169.5" "@tanstack/start@1.169.8"
  "@tanstack/react-start@1.169.5" "@tanstack/react-start@1.169.8"
  "@tanstack/solid-start@1.169.5" "@tanstack/solid-start@1.169.8"
)

if [[ -n "$EXTRA_BAD_FILE" ]]; then
  if [[ ! -r "$EXTRA_BAD_FILE" ]]; then
    echo "Error: cannot read --bad-versions-file: $EXTRA_BAD_FILE" >&2
    exit 3
  fi
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '[:space:]')"
    [[ -z "$line" ]] && continue
    KNOWN_BAD_VERSIONS+=("$line")
  done < "$EXTRA_BAD_FILE"
fi

# ── State ─────────────────────────────────────────────────────────────────────
PASS=0; WARN=0; FAIL=0
AFFECTED_REPOS=()
INSTALLED_BAD=()
FINDINGS_JSON=()

PLATFORM="$(uname -s 2>/dev/null || echo unknown)"
HOSTNAME_VAL="$(hostname 2>/dev/null || echo unknown)"
SELF_PID=$$
STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ── Output helpers ────────────────────────────────────────────────────────────
say()  { $JSON_OUT && return 0; $QUIET && return 0; echo -e "$@"; }
ok()   { say "  ${GRN}✔${RST}  $*"; PASS=$((PASS+1)); }
warn() { say "  ${YEL}⚠${RST}  $*"; WARN=$((WARN+1)); }
fail() { say "  ${RED}✖${RST}  $*"; FAIL=$((FAIL+1)); }
info() { $JSON_OUT && return 0; $QUIET && return 0; echo -e "  ${CYN}ℹ${RST}  $*"; }
hdr()  { $JSON_OUT && return 0; $QUIET && return 0; echo; echo -e "${BLD}${CYN}━━  $* ${RST}"; }

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

add_finding() {
  # add_finding <check> <severity> <message> [path] [extra_kv_json_fragment]
  local check="$1" sev="$2" msg="$3" path="${4:-}" extra="${5:-}"
  local obj="{\"check\":\"$(json_escape "$check")\",\"severity\":\"$sev\",\"message\":\"$(json_escape "$msg")\""
  [[ -n "$path" ]] && obj+=",\"path\":\"$(json_escape "$path")\""
  [[ -n "$extra" ]] && obj+=",${extra}"
  obj+="}"
  FINDINGS_JSON+=("$obj")
}

# ── Utility ───────────────────────────────────────────────────────────────────
has() { command -v "$1" >/dev/null 2>&1; }

# ── Online verification helpers ───────────────────────────────────────────────
# Compare two ISO 8601 UTC timestamps. Returns 0 if A <= B, 1 otherwise.
iso_le() {
  # Strip non-numeric chars for lexicographic compare on UTC strings.
  local a="${1//[^0-9]/}" b="${2//[^0-9]/}"
  [[ "$a" -le "$b" ]]
}

# Fetch GHSA advisory and refresh COMPROMISED_PKGS in-place.
# Quietly degrades if curl/jq missing or network unavailable.
fetch_advisory() {
  has curl || { info "curl missing — skipping advisory fetch"; return 0; }
  has jq   || { info "jq missing — skipping advisory fetch (install jq for online mode)"; return 0; }

  local url="https://api.github.com/advisories/${GHSA_ID}"
  local tmp; tmp="$(mktemp -t advisory.XXXXXX.json)"
  if ! curl -fsSL -H "Accept: application/vnd.github+json" \
        --max-time 15 "$url" -o "$tmp" 2>/dev/null; then
    info "Advisory fetch failed (${url}) — proceeding with built-in list"
    rm -f "$tmp"
    return 0
  fi

  local fetched
  fetched=$(jq -r '.vulnerabilities[]?.package.name // empty' "$tmp" 2>/dev/null | sort -u)
  if [[ -z "$fetched" ]]; then
    info "Advisory returned no package list — proceeding with built-in"
    rm -f "$tmp"
    return 0
  fi

  # Merge into COMPROMISED_PKGS (dedup).
  local merged=()
  local seen=" "
  for p in "${COMPROMISED_PKGS[@]}"; do
    merged+=("$p"); seen+="$p "
  done
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    case "$seen" in *" $p "*) ;; *) merged+=("$p"); seen+="$p " ;; esac
  done <<< "$fetched"
  COMPROMISED_PKGS=("${merged[@]}")

  local added=$(($(echo "$fetched" | wc -l) ))
  info "Advisory fetched: ${added} package names from ${GHSA_ID} merged (total: ${#COMPROMISED_PKGS[@]})"
  add_finding "advisory" "info" "Advisory fetched and merged" "" \
    "\"ghsa\":\"$(json_escape "$GHSA_ID")\",\"package_count\":${#COMPROMISED_PKGS[@]}"
  rm -f "$tmp"
}

# Query npm registry for a package, return the publishTime of <version>.
# Echoes ISO timestamp on stdout; empty if not found / network error.
registry_publish_time() {
  local pkg="$1" ver="$2"
  has curl || return 0
  has jq   || return 0
  local enc="${pkg//\//%2f}"
  local url="https://registry.npmjs.org/${enc}"
  curl -fsSL --max-time 10 "$url" 2>/dev/null \
    | jq -r --arg v "$ver" '.time[$v] // empty' 2>/dev/null
}

# Check if a publish time is inside the attack window. Returns:
#   0 = inside window (malicious by publishTime)
#   1 = outside window (clean)
#   2 = unknown / error
in_attack_window() {
  local ts="$1"
  [[ -z "$ts" ]] && return 2
  if iso_le "$ATTACK_WINDOW_START" "$ts" && iso_le "$ts" "$ATTACK_WINDOW_END"; then
    return 0
  fi
  return 1
}

is_compromised_family() {
  local needle="$1" p
  for p in "${COMPROMISED_PKGS[@]}"; do
    [[ "$p" == "$needle" ]] && return 0
  done
  return 1
}

is_known_bad() {
  local needle="$1@$2" entry
  for entry in "${KNOWN_BAD_VERSIONS[@]}"; do
    [[ "$entry" == "$needle" ]] && return 0
  done
  return 1
}

# Safe JSON value extraction via argv (no injection).
# Usage: json_get <file> <dot.path>   — supports top-level + one nested level
json_get() {
  local file="$1" expr="$2"
  if has jq; then
    jq -r "${expr} // empty" "$file" 2>/dev/null || true
    return 0
  fi
  if has python3; then
    python3 - "$file" "$expr" <<'PY' 2>/dev/null || true
import json, sys
path, expr = sys.argv[1], sys.argv[2].strip()
try:
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        d = json.load(f)
except Exception:
    sys.exit(0)
if not expr.startswith('.'):
    sys.exit(0)
cur = d
for part in [p for p in expr[1:].split('.') if p]:
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(0)
if isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print(cur)
PY
    return 0
  fi
  # No parser available — give up gracefully.
  return 0
}

# Excludes self + parent PID from pgrep -f matches.
safe_pgrep_f() {
  local pat="$1" out=() p
  for p in $(pgrep -f "$pat" 2>/dev/null || true); do
    [[ "$p" == "$SELF_PID" ]] && continue
    [[ "$p" == "$PPID" ]] && continue
    out+=("$p")
  done
  [[ ${#out[@]} -gt 0 ]] && printf '%s\n' "${out[@]}" || true
}

# ── Banner ────────────────────────────────────────────────────────────────────
if ! $JSON_OUT && ! $QUIET; then
  echo
  echo -e "${BLD}${RED}╔══════════════════════════════════════════════════════════════╗"
  echo -e "║   TanStack npm Supply Chain Attack — Compromise Checker      ║"
  echo -e "║   CVE-2026-45321 / GHSA-g7cv-rxg3-hmpx           v${VERSION}        ║"
  echo -e "╚══════════════════════════════════════════════════════════════╝${RST}"
  echo -e "  Scan root : ${BLD}${SCAN_DIR}${RST}"
  echo -e "  Platform  : ${BLD}${PLATFORM}${RST}"
  if $FIX && $APPLY; then
    echo -e "  Fix mode  : ${BLD}${RED}APPLY${RST}"
  elif $FIX; then
    echo -e "  Fix mode  : ${BLD}dry-run${RST}"
  else
    echo -e "  Fix mode  : off"
  fi
  if $ONLINE_CHECK; then
    echo -e "  Online    : ${BLD}${GRN}enabled${RST} (advisory: ${GHSA_ID}, window: ${ATTACK_WINDOW_START} → ${ATTACK_WINDOW_END})"
  else
    echo -e "  Online    : off (use --online to enable registry + advisory verification)"
  fi
  echo -e "  Date      : ${STARTED_AT}"
fi

# Fetch advisory early so the rest of the script benefits from the refreshed list.
if $ONLINE_CHECK; then
  fetch_advisory
fi

# ══════════════════════════════════════════════════════════════════════════════
hdr "1 / 7  DEAD-MAN'S SWITCH ARTEFACTS"
# ══════════════════════════════════════════════════════════════════════════════

DMS_FILES=(
  "$HOME/.local/bin/gh-token-monitor.sh"
  "$HOME/.local/bin/gh-token-monitor"
  "/usr/local/bin/gh-token-monitor.sh"
  "/usr/local/bin/gh-token-monitor"
  "$HOME/.config/gh-token-monitor"
)
DMS_FOUND=false

for f in "${DMS_FILES[@]}"; do
  if [[ -e "$f" ]]; then
    fail "Dead-man's switch artefact: ${BLD}$f${RST}"
    add_finding "dead_mans_switch" "fail" "Dead-man's switch artefact present" "$f"
    DMS_FOUND=true
  fi
done

if [[ "$PLATFORM" == "Darwin" ]]; then
  for d in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r plist; do
      [[ -z "$plist" ]] && continue
      fail "Suspicious launchd plist: ${BLD}$plist${RST}"
      add_finding "dead_mans_switch" "fail" "Suspicious launchd plist" "$plist"
      DMS_FOUND=true
    done < <(find "$d" -maxdepth 1 -type f \( -name '*gh-token-monitor*' -o -name '*token-monitor*' \) 2>/dev/null || true)
  done
fi

if has systemctl; then
  if systemctl --user list-unit-files 2>/dev/null | grep -qiE 'gh-token-monitor|token-monitor'; then
    fail "systemd user unit matches token-monitor"
    add_finding "dead_mans_switch" "fail" "systemd user unit present" ""
    DMS_FOUND=true
  fi
  if systemctl list-unit-files 2>/dev/null | grep -qiE 'gh-token-monitor|token-monitor'; then
    fail "systemd system unit matches token-monitor"
    add_finding "dead_mans_switch" "fail" "systemd system unit present" ""
    DMS_FOUND=true
  fi
fi

DMS_PIDS="$(safe_pgrep_f 'gh-token-monitor' || true)"
if [[ -n "$DMS_PIDS" ]]; then
  pids_csv="$(echo "$DMS_PIDS" | tr '\n' ',' | sed 's/,$//')"
  fail "Process matching 'gh-token-monitor' running (pids: ${pids_csv})"
  add_finding "dead_mans_switch" "fail" "Suspicious process running" "" "\"pids\":\"${pids_csv}\""
  DMS_FOUND=true
fi

if ! $DMS_FOUND; then
  ok "No dead-man's switch artefacts found"
  add_finding "dead_mans_switch" "pass" "Clean" ""
fi

# ══════════════════════════════════════════════════════════════════════════════
hdr "2 / 7  PERSISTENCE VECTORS"
# ══════════════════════════════════════════════════════════════════════════════

PERSIST_FOUND=false
PERSIST_TARGETS=(
  "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"
  "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zlogin"
  "$HOME/.config/fish/config.fish"
)
PERSIST_PATTERN='gh-token-monitor|token-monitor\.sh'

for f in "${PERSIST_TARGETS[@]}"; do
  if [[ -f "$f" ]] && grep -E -q "$PERSIST_PATTERN" "$f" 2>/dev/null; then
    fail "Shell rc references token-monitor: ${BLD}$f${RST}"
    add_finding "persistence" "fail" "Shell rc references token-monitor" "$f"
    PERSIST_FOUND=true
  fi
done

if has crontab; then
  if crontab -l 2>/dev/null | grep -E -q "$PERSIST_PATTERN"; then
    fail "User crontab references token-monitor"
    add_finding "persistence" "fail" "Crontab entry" ""
    PERSIST_FOUND=true
  fi
fi

for d in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly /var/spool/cron; do
  [[ -d "$d" && -r "$d" ]] || continue
  if grep -rE -l "$PERSIST_PATTERN" "$d" 2>/dev/null | head -1 | grep -q .; then
    fail "System cron references token-monitor (search root: $d)"
    add_finding "persistence" "fail" "System cron reference" "$d"
    PERSIST_FOUND=true
  fi
done

if [[ -d "$HOME/.config/autostart" ]]; then
  if grep -rE -l "$PERSIST_PATTERN" "$HOME/.config/autostart" 2>/dev/null | head -1 | grep -q .; then
    fail "XDG autostart references token-monitor"
    add_finding "persistence" "fail" "XDG autostart entry" "$HOME/.config/autostart"
    PERSIST_FOUND=true
  fi
fi

if has git; then
  HP="$(git config --global --get core.hooksPath 2>/dev/null || true)"
  if [[ -n "$HP" && -d "$HP" ]]; then
    if grep -rE -l "$PERSIST_PATTERN" "$HP" 2>/dev/null | head -1 | grep -q .; then
      fail "Global git hooksPath ($HP) contains suspicious hook"
      add_finding "persistence" "fail" "Global git hook" "$HP"
      PERSIST_FOUND=true
    fi
  fi
fi

if ! $PERSIST_FOUND; then
  ok "No persistence vectors detected"
  add_finding "persistence" "pass" "Clean" ""
fi

# ══════════════════════════════════════════════════════════════════════════════
hdr "3 / 7  TOKEN / CREDENTIAL EXPOSURE"
# ══════════════════════════════════════════════════════════════════════════════

CRED_EXPOSED=false

SUSPICIOUS_VARS=(GITHUB_TOKEN GH_TOKEN GITHUB_PAT NPM_TOKEN AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
                 VAULT_TOKEN KUBECONFIG GOOGLE_APPLICATION_CREDENTIALS DOCKER_AUTH_CONFIG
                 CLOUDFLARE_API_TOKEN CF_API_TOKEN HUGGINGFACE_TOKEN HF_TOKEN
                 OPENAI_API_KEY ANTHROPIC_API_KEY)
for v in "${SUSPICIOUS_VARS[@]}"; do
  if [[ -n "${!v:-}" ]]; then
    warn "Env var present in shell: ${BLD}$v${RST} (may be inherited by npm postinstall)"
    add_finding "credentials" "warn" "Sensitive env var set" "" "\"var\":\"$v\""
    CRED_EXPOSED=true
  fi
done

# Static credential files (presence only — never read content)
CRED_FILES=(
  "$HOME/.npmrc:_authToken"
  "$HOME/.yarnrc.yml:npmAuthToken"
  "$HOME/.aws/credentials:aws_secret_access_key"
  "$HOME/.config/gh/hosts.yml:oauth_token"
  "$HOME/.netrc:password"
  "$HOME/.docker/config.json:auth"
  "$HOME/.kube/config:client-key-data"
)
for entry in "${CRED_FILES[@]}"; do
  f="${entry%%:*}"
  pat="${entry#*:}"
  if [[ -f "$f" ]] && grep -E -q -- "$pat" "$f" 2>/dev/null; then
    warn "Credential file present: ${BLD}$f${RST}"
    add_finding "credentials" "warn" "Static credential file" "$f"
    CRED_EXPOSED=true
  fi
done

# .env enumeration (filename only)
ENV_FILES_COUNT=0
while IFS= read -r envf; do
  [[ -z "$envf" ]] && continue
  ENV_FILES_COUNT=$((ENV_FILES_COUNT+1))
  if [[ $ENV_FILES_COUNT -le 5 ]]; then
    warn ".env file (review): ${BLD}$envf${RST}"
    add_finding "credentials" "warn" ".env file present" "$envf"
  fi
done < <(find "$SCAN_DIR" \
  \( -name node_modules -o -name .git -o -name dist -o -name build -o -name .next \) -prune \
  -o -type f \( -name ".env" -o -name ".env.local" -o -name ".env.production" -o -name ".env.development" \) -print 2>/dev/null \
  | grep -Ev '\.(example|sample|template)$' || true)
if [[ $ENV_FILES_COUNT -gt 5 ]]; then
  warn "... and $((ENV_FILES_COUNT - 5)) more .env files (use --json for full list)"
fi
[[ $ENV_FILES_COUNT -gt 0 ]] && CRED_EXPOSED=true

if ! $CRED_EXPOSED; then
  ok "No credential exposure detected"
  add_finding "credentials" "pass" "Clean" ""
fi

# ══════════════════════════════════════════════════════════════════════════════
hdr "4 / 7  NETWORK INDICATORS"
# ══════════════════════════════════════════════════════════════════════════════

NET_INFO=false
if has lsof; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    info "Node TCP connection (manual review): $line"
    add_finding "network" "info" "Node TCP connection" "" "\"detail\":\"$(json_escape "$line")\""
    NET_INFO=true
  done < <(lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | awk 'tolower($1) ~ /^node/ {print $1" pid="$2" "$9}' | head -20 || true)
elif has ss; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    info "Node TCP connection (ss): $line"
    add_finding "network" "info" "Node TCP connection" "" "\"detail\":\"$(json_escape "$line")\""
    NET_INFO=true
  done < <(ss -tnp 2>/dev/null | grep -i node | head -20 || true)
else
  info "Neither lsof nor ss available — network IOC heuristic skipped"
fi

$NET_INFO || ok "No node TCP connections currently established (or none observable)"

# ══════════════════════════════════════════════════════════════════════════════
hdr "5 / 7  REPO SCAN — package.json + lockfiles"
# ══════════════════════════════════════════════════════════════════════════════

info "Indexing manifests under ${SCAN_DIR} (pruning node_modules, .git, dist, etc.)…"

MANIFEST_LIST="$(mktemp -t tscheck.XXXXXX)"
trap 'rm -f "$MANIFEST_LIST"' EXIT

find "$SCAN_DIR" \
  \( -name node_modules -o -name .git -o -name dist -o -name build -o -name .next -o -name .nuxt \
     -o -name .cache -o -name .turbo -o -name .yarn -o -name .pnpm-store -o -name coverage \
     -o -name out -o -name target -o -name __pycache__ \
     -o -path '*/templates/*' -o -path '*/template/*' -o -path '*/fixtures/*' -o -path '*/__tests__/*' \) -prune \
  -o -type f \( -name "package.json" -o -name "package-lock.json" -o -name "yarn.lock" -o -name "pnpm-lock.yaml" \) \
  -print > "$MANIFEST_LIST" 2>/dev/null || true

PKGJSON_COUNT=$(grep -c '/package\.json$' "$MANIFEST_LIST" 2>/dev/null || echo 0)
LOCKFILE_COUNT=$(grep -cE '/(package-lock\.json|yarn\.lock|pnpm-lock\.yaml)$' "$MANIFEST_LIST" 2>/dev/null || echo 0)
info "Found ${PKGJSON_COUNT} package.json + ${LOCKFILE_COUNT} lockfile(s)"

# Scan a package.json for compromised dependencies.
# Emits TSV: <pkg>\t<range>\t<field-or-"unknown">
scan_pkgjson_for_compromised() {
  local pkgjson="$1"
  if has jq; then
    local field p v
    for field in dependencies devDependencies peerDependencies optionalDependencies resolutions overrides; do
      for p in "${COMPROMISED_PKGS[@]}"; do
        v=$(jq -r --arg p "$p" --arg f "$field" '(.[$f] // {}) | (.[$p] // empty)' "$pkgjson" 2>/dev/null)
        [[ -z "$v" || "$v" == "null" ]] && continue
        printf '%s\t%s\t%s\n' "$p" "$v" "$field"
      done
    done
  elif has python3; then
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], "r", encoding="utf-8", errors="replace"))
except Exception:
    sys.exit(0)
pkgs = sys.argv[2:]
fields = ["dependencies","devDependencies","peerDependencies","optionalDependencies","resolutions","overrides"]
for f in fields:
    sect = d.get(f)
    if not isinstance(sect, dict):
        continue
    for p in pkgs:
        v = sect.get(p)
        if v:
            print(f"{p}\t{v}\t{f}")
' "$pkgjson" "${COMPROMISED_PKGS[@]}" 2>/dev/null
  else
    # No JSON parser: single grep pass, field marked "unknown"
    local p esc v
    for p in "${COMPROMISED_PKGS[@]}"; do
      esc="$(printf '%s' "$p" | sed 's/[][\\/.^$*+?(){}|]/\\&/g')"
      v=$(grep -E "\"${esc}\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$pkgjson" 2>/dev/null | head -1 \
          | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/' || true)
      [[ -n "$v" ]] && printf '%s\t%s\tunknown\n' "$p" "$v"
    done
  fi
}

# 5a. package.json: declared dependencies on compromised families
PKG_HITS=false
while IFS= read -r pkgjson; do
  [[ -z "$pkgjson" ]] && continue
  case "$pkgjson" in *"/package.json") ;; *) continue ;; esac

  hits="$(scan_pkgjson_for_compromised "$pkgjson")"
  [[ -z "$hits" ]] && continue

  warn "Compromised family declared in: ${BLD}${pkgjson}${RST}"
  AFFECTED_REPOS+=("$(dirname "$pkgjson")")
  PKG_HITS=true
  while IFS=$'\t' read -r p v field; do
    [[ -z "$p" ]] && continue
    say "       ${YEL}↳${RST} $p @ $v  (${field})"
    add_finding "package_json" "warn" "Compromised family in manifest" "$pkgjson" \
      "\"package\":\"$p\",\"range\":\"$(json_escape "$v")\",\"field\":\"$field\""
  done <<< "$hits"
done < "$MANIFEST_LIST"

$PKG_HITS || ok "No compromised family declared in any package.json"

# 5b. Lockfile analysis — the strong signal
LOCK_HITS=false

analyze_npm_lock() {
  local lock="$1"
  has jq || return 0
  while IFS=$'\t' read -r path ver; do
    [[ -z "$path" || -z "$ver" ]] && continue
    local pkg="${path##*node_modules/}"
    if is_compromised_family "$pkg"; then
      if is_known_bad "$pkg" "$ver"; then
        fail "Lockfile pins KNOWN MALICIOUS: ${BLD}${pkg}@${ver}${RST} in $lock"
        add_finding "lockfile" "fail" "Known malicious version pinned" "$lock" \
          "\"package\":\"$pkg\",\"version\":\"$ver\""
        INSTALLED_BAD+=("$pkg@$ver")
      else
        warn "Lockfile pins compromised family: ${BLD}${pkg}@${ver}${RST} in $lock"
        add_finding "lockfile" "warn" "Compromised family pinned (verify against advisory)" "$lock" \
          "\"package\":\"$pkg\",\"version\":\"$ver\""
      fi
      LOCK_HITS=true
    fi
  done < <(jq -r '
    (.packages // {}) | to_entries[]
    | select(.key | startswith("node_modules/@tanstack/"))
    | "\(.key)\t\(.value.version // "")"' "$lock" 2>/dev/null)
}

analyze_pnpm_lock() {
  local lock="$1" line pkg ver
  # pnpm v6+ keys: /@tanstack/react-router@1.169.5:  or '/@tanstack/router-core@1.169.5':
  while IFS= read -r line; do
    if [[ "$line" =~ \'?/?(@tanstack/[a-zA-Z0-9_.-]+)@([0-9][^\'\":[:space:]]*) ]]; then
      pkg="${BASH_REMATCH[1]}"
      ver="${BASH_REMATCH[2]}"
      ver="${ver%%[\'\":(]*}"
      if is_compromised_family "$pkg"; then
        if is_known_bad "$pkg" "$ver"; then
          fail "pnpm-lock pins KNOWN MALICIOUS: ${BLD}${pkg}@${ver}${RST} in $lock"
          add_finding "lockfile" "fail" "Known malicious version in pnpm-lock" "$lock" \
            "\"package\":\"$pkg\",\"version\":\"$ver\""
          INSTALLED_BAD+=("$pkg@$ver")
        else
          warn "pnpm-lock pins compromised family: ${BLD}${pkg}@${ver}${RST}"
          add_finding "lockfile" "warn" "Compromised family in pnpm-lock" "$lock" \
            "\"package\":\"$pkg\",\"version\":\"$ver\""
        fi
        LOCK_HITS=true
      fi
    fi
  done < "$lock"
}

analyze_yarn_lock() {
  local lock="$1"
  # yarn.lock v1: header line starting with @tanstack/...@..., then `  version "x.y.z"`
  local cur_pkg="" cur_ver="" line
  while IFS= read -r line; do
    if [[ "$line" =~ ^\"?(@tanstack/[a-zA-Z0-9_.-]+)@ ]]; then
      cur_pkg="${BASH_REMATCH[1]}"
      cur_ver=""
    elif [[ -n "$cur_pkg" && "$line" =~ ^[[:space:]]+version[[:space:]]+\"([^\"]+)\" ]]; then
      cur_ver="${BASH_REMATCH[1]}"
      if is_compromised_family "$cur_pkg"; then
        if is_known_bad "$cur_pkg" "$cur_ver"; then
          fail "yarn.lock pins KNOWN MALICIOUS: ${BLD}${cur_pkg}@${cur_ver}${RST} in $lock"
          add_finding "lockfile" "fail" "Known malicious version in yarn.lock" "$lock" \
            "\"package\":\"$cur_pkg\",\"version\":\"$cur_ver\""
          INSTALLED_BAD+=("$cur_pkg@$cur_ver")
        else
          warn "yarn.lock pins compromised family: ${BLD}${cur_pkg}@${cur_ver}${RST}"
          add_finding "lockfile" "warn" "Compromised family in yarn.lock" "$lock" \
            "\"package\":\"$cur_pkg\",\"version\":\"$cur_ver\""
        fi
        LOCK_HITS=true
      fi
      cur_pkg=""; cur_ver=""
    fi
  done < "$lock"
}

while IFS= read -r lock; do
  [[ -z "$lock" ]] && continue
  case "$lock" in
    */package-lock.json)  analyze_npm_lock  "$lock" ;;
    */pnpm-lock.yaml)     analyze_pnpm_lock "$lock" ;;
    */yarn.lock)          analyze_yarn_lock "$lock" ;;
  esac
done < <(grep -E '/(package-lock\.json|yarn\.lock|pnpm-lock\.yaml)$' "$MANIFEST_LIST" || true)

$LOCK_HITS || ok "No compromised pins found in any lockfile"

# ══════════════════════════════════════════════════════════════════════════════
hdr "6 / 7  INSTALLED node_modules — direct version check"
# ══════════════════════════════════════════════════════════════════════════════

INSTALLED_HITS=false
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  # only direct children of node_modules/@tanstack/<pkg>/package.json
  case "$p" in *"/node_modules/@tanstack/"*"/package.json") ;; *) continue ;; esac
  rel="${p#*node_modules/@tanstack/}"
  # skip nested node_modules
  case "$rel" in *"/node_modules/"*) continue ;; esac

  name=""; ver=""
  if has jq; then
    name=$(jq -r '.name // empty' "$p" 2>/dev/null || true)
    ver=$(jq -r '.version // empty' "$p" 2>/dev/null || true)
  elif has python3; then
    nv=$(python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1],"r",encoding="utf-8",errors="replace"))
    print(d.get("name",""), d.get("version",""))
except Exception:
    pass' "$p" 2>/dev/null || true)
    name="${nv% *}"
    ver="${nv#* }"
    [[ "$name" == "$ver" ]] && { name=""; ver=""; }
  fi
  if [[ -z "$name" ]]; then
    name=$(grep -m1 '"name"[[:space:]]*:' "$p" 2>/dev/null | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)
    ver=$(grep -m1 '"version"[[:space:]]*:' "$p" 2>/dev/null  | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)
  fi
  [[ -z "$name" || -z "$ver" ]] && continue

  if is_compromised_family "$name"; then
    # Online check: query registry publish-time and compare to attack window.
    # This catches versions the static list does not know about, and also
    # *demotes* false warnings on legitimately-published versions.
    online_verdict=""   # "" = not checked | "malicious" | "clean" | "unknown"
    online_ts=""
    if $ONLINE_CHECK; then
      online_ts="$(registry_publish_time "$name" "$ver")"
      if [[ -n "$online_ts" ]]; then
        if in_attack_window "$online_ts"; then
          online_verdict="malicious"
        else
          online_verdict="clean"
        fi
      else
        online_verdict="unknown"
      fi
    fi

    if is_known_bad "$name" "$ver" || [[ "$online_verdict" == "malicious" ]]; then
      reason="known-bad list"
      [[ "$online_verdict" == "malicious" ]] && reason="publishTime ${online_ts} inside attack window"
      fail "INSTALLED MALICIOUS: ${BLD}${name}@${ver}${RST} at ${p%/package.json}  (${reason})"
      add_finding "installed" "fail" "Malicious version installed (${reason})" "${p%/package.json}" \
        "\"package\":\"$name\",\"version\":\"$ver\",\"detection\":\"$(json_escape "$reason")\",\"publish_time\":\"$(json_escape "$online_ts")\""
      INSTALLED_BAD+=("$name@$ver")
    elif [[ "$online_verdict" == "clean" ]]; then
      ok "Compromised family but registry-confirmed CLEAN: ${name}@${ver} (published ${online_ts})"
      add_finding "installed" "pass" "Compromised family, registry-confirmed clean by publishTime" "${p%/package.json}" \
        "\"package\":\"$name\",\"version\":\"$ver\",\"publish_time\":\"$(json_escape "$online_ts")\""
    else
      warn "Compromised family installed: ${BLD}${name}@${ver}${RST} at ${p%/package.json}"
      add_finding "installed" "warn" "Compromised family installed (verify against advisory)" "${p%/package.json}" \
        "\"package\":\"$name\",\"version\":\"$ver\""
    fi
    INSTALLED_HITS=true
  fi
done < <(find "$SCAN_DIR" -path '*/node_modules/@tanstack/*/package.json' -type f 2>/dev/null || true)

$INSTALLED_HITS || ok "No compromised packages in installed node_modules"

# ══════════════════════════════════════════════════════════════════════════════
hdr "7 / 7  GITHUB ACTIONS HARDENING HINTS"
# ══════════════════════════════════════════════════════════════════════════════

WF_FOUND=false
while IFS= read -r wf; do
  [[ -z "$wf" ]] && continue
  # Flag uncached workflows that install on PR-from-fork (pull_request_target is the dangerous one)
  if grep -E -q 'pull_request_target' "$wf" 2>/dev/null; then
    warn "Workflow uses pull_request_target: ${BLD}$wf${RST} (review checkout + token scope)"
    add_finding "actions" "warn" "pull_request_target trigger" "$wf"
    WF_FOUND=true
  fi
  if grep -E -q '(npm|pnpm|yarn) (i|install|ci)\b' "$wf" 2>/dev/null \
     && ! grep -E -q 'ignore-scripts|--ignore-scripts' "$wf" 2>/dev/null; then
    info "Workflow installs deps without --ignore-scripts: ${wf}"
    add_finding "actions" "info" "Install without --ignore-scripts" "$wf"
    WF_FOUND=true
  fi
  if grep -E -q 'actions/cache@v[0-9]' "$wf" 2>/dev/null; then
    info "Workflow uses actions/cache — verify cache keys are not attacker-controllable: ${wf}"
    add_finding "actions" "info" "actions/cache usage" "$wf"
    WF_FOUND=true
  fi
done < <(find "$SCAN_DIR" -path '*/.github/workflows/*' -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null || true)

$WF_FOUND || ok "No risky GitHub Actions patterns detected (in scanned scope)"

# ══════════════════════════════════════════════════════════════════════════════
# FIX MODE — print recommendations (and optionally apply with --apply --yes)
# ══════════════════════════════════════════════════════════════════════════════
if $FIX && [[ ${#AFFECTED_REPOS[@]} -gt 0 ]]; then
  hdr "FIX — recommended actions"
  say "  ${RED}WARNING:${RST} running 'npm/yarn/pnpm update' WITHOUT pinning can install another"
  say "  compromised version (the malicious releases bumped the patch number). Pin explicitly."
  say ""
  # Dedup
  uniq_repos=()
  while IFS= read -r r; do uniq_repos+=("$r"); done < <(printf '%s\n' "${AFFECTED_REPOS[@]}" | sort -u)

  for repo in "${uniq_repos[@]}"; do
    say "  ${BLD}Repo:${RST} $repo"
    if   [[ -f "$repo/pnpm-lock.yaml" ]];     then say "    pnpm install <pkg>@<safe-version>  # update package.json range first"
    elif [[ -f "$repo/yarn.lock" ]];          then say "    yarn add <pkg>@<safe-version>"
    elif [[ -f "$repo/package-lock.json" ]];  then say "    npm install <pkg>@<safe-version> --save-exact"
    else                                            say "    (no lockfile — pin manually in package.json then install)"
    fi
    say "    Then re-run: bash check.sh --scan-dir \"$repo\""
  done

  if $APPLY; then
    say ""
    if ! $YES; then
      say "  ${RED}--apply specified but --yes not given. Refusing to execute without explicit confirmation.${RST}"
      say "  Re-run with --apply --yes to proceed (you accept the risk of further breakage)."
    else
      say "  ${RED}--apply --yes: not executing automated update — explicit pin required.${RST}"
      say "  This tool intentionally refuses to run blind 'update' commands. Pin manually."
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

# Determine exit code
EXIT_CODE=0
if   [[ $FAIL -gt 0 ]]; then EXIT_CODE=2
elif [[ $WARN -gt 0 ]]; then EXIT_CODE=1
fi

if $JSON_OUT; then
  # Emit JSON
  printf '{'
  printf '"tool":"tanstack-compromise-checker","version":"%s",' "$VERSION"
  printf '"started_at":"%s",' "$STARTED_AT"
  printf '"scan_dir":"%s",' "$(json_escape "$SCAN_DIR")"
  printf '"platform":"%s",' "$(json_escape "$PLATFORM")"
  printf '"hostname":"%s",' "$(json_escape "$HOSTNAME_VAL")"
  printf '"summary":{"passed":%d,"warnings":%d,"failed":%d,"exit_code":%d},' "$PASS" "$WARN" "$FAIL" "$EXIT_CODE"
  printf '"findings":['
  first=true
  for f in "${FINDINGS_JSON[@]}"; do
    $first && first=false || printf ','
    printf '%s' "$f"
  done
  printf ']}'
  printf '\n'
else
  hdr "SUMMARY"
  echo
  echo -e "  ${GRN}Passed${RST}: $PASS    ${YEL}Warnings${RST}: $WARN    ${RED}Failed${RST}: $FAIL"
  echo -e "  Scope : ${BLD}${SCAN_DIR}${RST}"
  echo

  if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}${BLD}  ⚠  COMPROMISE INDICATORS PRESENT — take action:${RST}"
    echo -e "  1. ${BLD}DO NOT${RST} revoke tokens before killing the dead-man's switch process."
    echo -e "     macOS:  launchctl bootout gui/\$UID ~/Library/LaunchAgents/com.user.gh-token-monitor.plist 2>/dev/null"
    echo -e "             (legacy: launchctl unload ~/Library/LaunchAgents/com.user.gh-token-monitor.plist)"
    echo -e "     Linux:  systemctl --user stop gh-token-monitor && systemctl --user disable gh-token-monitor"
    echo -e "  2. Remove daemon: rm -f ~/.local/bin/gh-token-monitor.sh"
    echo -e "  3. THEN revoke + rotate: GitHub, npm, AWS, GCP, Azure, SSH keys, SSH agent."
    echo -e "  4. Audit: ~/.aws/credentials, ~/.kube/config, ~/.config/gh/hosts.yml, ~/.npmrc"
    echo -e "  5. GitHub audit log: https://github.com/settings/security-log"
    echo -e "  6. Advisory: https://github.com/advisories/GHSA-g7cv-rxg3-hmpx"
  elif [[ $WARN -gt 0 ]]; then
    echo -e "${YEL}${BLD}  ℹ  Warnings present — review above.${RST}"
    echo -e "  Scope was: ${SCAN_DIR}  (system-wide checks limited to this scope)"
    echo -e "  Advisory:  https://github.com/advisories/GHSA-g7cv-rxg3-hmpx"
  else
    echo -e "${GRN}${BLD}  ✔  No indicators of compromise within scope: ${SCAN_DIR}${RST}"
    echo -e "  Note: a clean result for ${SCAN_DIR} does not certify the rest of the system."
  fi
  echo
fi

exit "$EXIT_CODE"