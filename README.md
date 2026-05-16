# tanstack-compromise-checker

Detect indicators of the TanStack npm supply-chain attack on a developer
machine, a repository, or a CI runner. Bash script, Docker image, and GitHub
Action — same engine, three entry points.

**CVE-2026-45321 / [GHSA-g7cv-rxg3-hmpx](https://github.com/advisories/GHSA-g7cv-rxg3-hmpx)**

On May 11 2026, attackers published 84 malicious versions across 42
`@tanstack/*` packages via GitHub Actions cache poisoning. The payload steals
GitHub tokens, npm tokens, AWS/GCP/Azure credentials, and installs a
**dead-man's switch** daemon that wipes `~/` the moment the stolen token is
revoked.

## Quick start

Pick the entry point that matches where you are.

### macOS / Linux / WSL2 / Git Bash

```sh
TAG=v1.0.0
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh.sha256
sha256sum -c check.sh.sha256
bash check.sh --online
```

### Docker — works on every OS that runs Docker (incl. Windows)

```sh
docker run --rm -v "$PWD":/scan \
  ghcr.io/fabriziosalmi/tanstack-compromise-checker:v1.0.0 \
  /scan true fail tanstack-findings.json '' GHSA-g7cv-rxg3-hmpx
```

The image is multi-arch (`linux/amd64`, `linux/arm64`) and ships with build
provenance signed via GitHub OIDC. Verify before running:

```sh
gh attestation verify \
  oci://ghcr.io/fabriziosalmi/tanstack-compromise-checker:v1.0.0 \
  --repo fabriziosalmi/tanstack-compromise-checker
```

### GitHub Action — block compromised dependencies in CI

```yaml
permissions: {}

jobs:
  check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - uses: fabriziosalmi/tanstack-compromise-checker@v1
        with:
          scan-dir: .
          online: 'true'
          fail-on: fail
```

A complete hardened workflow lives at
[`.github/workflows/tanstack-check.yml`](.github/workflows/tanstack-check.yml)
and is the same workflow this repository runs against itself.

## What the script checks

| # | Check | Description |
|---|-------|-------------|
| 1 | Dead-man's switch | `~/.local/bin/gh-token-monitor.sh`, LaunchAgents + LaunchDaemons (macOS), systemd user + system units (Linux), running processes |
| 2 | Persistence | shell rc files, user/system crontab, `/etc/cron.*`, XDG autostart, global git `core.hooksPath` |
| 3 | Credentials | sensitive env vars, `~/.npmrc`, `~/.yarnrc.yml`, `~/.aws/credentials`, `~/.config/gh/hosts.yml`, `~/.netrc`, `~/.docker/config.json`, `~/.kube/config`, `.env*` file enumeration |
| 4 | Network IOC | running `node` processes with established outbound TCP connections (heuristic, manual review) |
| 5 | Repo scan | `package.json` declared deps + lockfile pinned versions (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`) |
| 6 | Installed | `node_modules/@tanstack/*/package.json` checked against the known-malicious version list, then against the npm registry `time[<version>]` when `--online` |
| 7 | Actions hints | `.github/workflows/*` scanned for `pull_request_target`, missing `--ignore-scripts`, `actions/cache` usage |

With `--online`, the script also fetches the GHSA advisory at runtime so that
detection coverage tracks the advisory's live state instead of a hard-coded
list of versions.

**Affected family**: `@tanstack/router`, `@tanstack/react-router`,
`@tanstack/history`, `@tanstack/start`, `@tanstack/eslint-plugin-router`, and
related packages.

**Clean families** (not affected): `@tanstack/react-query`,
`@tanstack/react-table`, `@tanstack/react-virtual`, `@tanstack/form`,
`@tanstack/store`.

## Usage

```sh
# Quick check (current user's home)
bash check.sh

# Online mode: query the GHSA advisory and npm registry publish-time
bash check.sh --online

# Scan a specific directory
bash check.sh --scan-dir /path/to/your/repos

# JSON output for CI/SIEM integration
bash check.sh --json > findings.json

# Suggest pin commands for affected repos (dry-run)
bash check.sh --scan-dir /path/to/repos --fix

# Provide an extended known-bad list
bash check.sh --bad-versions-file ./extra-bad-versions.txt
```

### All options

| Flag | Description |
|------|-------------|
| `--scan-dir DIR` | Root directory to scan (default: `$HOME`). Refuses to scan system directories like `/`, `/etc`, `/usr`. |
| `--online` | Query the GHSA advisory and the npm registry's `time[<version>]` to confirm compromise. Off by default — opt-in. |
| `--ghsa GHSA-ID` | Override the advisory ID used in `--online` (default `GHSA-g7cv-rxg3-hmpx`). |
| `--attack-window-start ISO`, `--attack-window-end ISO` | Override the publish-time window used in `--online`. |
| `--fix` | Print recommended pin commands for affected repos (dry-run by default). |
| `--apply` | With `--fix`: opt-in to execution. Currently still refuses blind `update`; manual pinning is required. |
| `--yes`, `-y` | Skip confirmation prompt for `--apply`. |
| `--json` | Emit findings as JSON to stdout (implies `--quiet`). |
| `--bad-versions-file F` | Append entries (`pkg@version`, one per line) to the known-bad list. |
| `--no-color` | Disable ANSI colors. |
| `--quiet`, `-q` | Suppress per-check output, print only summary. |
| `-h`, `--help` | Show help. |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Clean — no indicators within scanned scope |
| 1 | Warnings only — review recommended |
| 2 | Failures — compromise indicators present |
| 3 | Tool/usage error |

## Security posture

This repository defends itself against the same attack class it detects.
Concretely:

- Every GitHub Action `uses:` is pinned to a 40-character commit SHA, not a
  floating tag.
- The Docker base image is pinned to an immutable multi-arch manifest digest.
- Every workflow declares `permissions: {}` at the top level; jobs grant only
  what they need.
- `actions/checkout` is invoked with `persist-credentials: false` so no
  authenticated git remote is left in `$GITHUB_WORKSPACE`.
- [`step-security/harden-runner`](https://github.com/step-security/harden-runner)
  is the first step of every workflow and monitors runner egress.
- [OpenSSF Scorecard](https://github.com/ossf/scorecard) runs weekly and on
  every push to `main`; results are uploaded as SARIF.
- Each release publishes a [SLSA build provenance attestation](https://slsa.dev/spec/v1.0/provenance)
  for the Docker image. Anyone can verify it offline with `gh attestation`.
- Each release ships a `check.sh.sha256` covering all installable artefacts.

The full policy is in [`SECURITY.md`](SECURITY.md).

**Do not** pipe `curl | bash` for any security tool, including this one. Always
download, verify checksum, inspect, then run.

## Sample output

```
━━  1 / 7  DEAD-MAN'S SWITCH ARTEFACTS
  ✔  No dead-man's switch artefacts found

━━  2 / 7  PERSISTENCE VECTORS
  ✔  No persistence vectors detected

━━  3 / 7  TOKEN / CREDENTIAL EXPOSURE
  ✔  No credential exposure detected

━━  4 / 7  NETWORK INDICATORS
  ✔  No node TCP connections currently established (or none observable)

━━  5 / 7  REPO SCAN — package.json + lockfiles
  ℹ  Found 12 package.json + 8 lockfile(s)
  ✔  No compromised family declared in any package.json
  ✔  No compromised pins found in any lockfile

━━  6 / 7  INSTALLED node_modules — direct version check
  ✔  No compromised packages in installed node_modules

━━  7 / 7  GITHUB ACTIONS HARDENING HINTS
  ✔  No risky GitHub Actions patterns detected (in scanned scope)

━━  SUMMARY
  Passed: 7    Warnings: 0    Failed: 0
  Scope : /Users/alice/dev
  ✔  No indicators of compromise within scope: /Users/alice/dev
  Note: a clean result for /Users/alice/dev does not certify the rest of the system.
```

## If you are compromised

> **Do NOT revoke your GitHub token before stopping the daemon** — the
> dead-man's switch will `rm -rf ~/` the moment the token is revoked.

1. Stop the daemon first:
   - macOS 14+: `launchctl bootout gui/$UID ~/Library/LaunchAgents/com.user.gh-token-monitor.plist`
   - macOS legacy: `launchctl unload ~/Library/LaunchAgents/com.user.gh-token-monitor.plist`
   - Linux: `systemctl --user stop gh-token-monitor && systemctl --user disable gh-token-monitor`
2. Remove the script: `rm -f ~/.local/bin/gh-token-monitor.sh`
3. **Then** revoke and rotate: GitHub token, npm token, AWS/GCP/Azure
   credentials, SSH keys, SSH agent.
4. Review the GitHub audit log:
   <https://github.com/settings/security-log>
5. Inspect `~/.aws/credentials`, `~/.kube/config`, `~/.config/gh/hosts.yml`,
   `~/.npmrc`.

## Dependencies

The bash script needs:

- `bash` 4+
- `jq` (recommended) — `package-lock.json` parsing
- `python3` (optional fallback) — used when `jq` is absent
- `curl` — required for `--online`
- `lsof` or `ss` (optional) — network IOC heuristic

The Docker image bundles all of the above. Use it on systems where you can't
or don't want to install these tools.

## Contributing

Issues and pull requests welcome. Note that this repository uses CODEOWNERS:
all PRs require a maintainer review.

## References

- [TanStack official postmortem](https://tanstack.com/blog/npm-supply-chain-compromise-postmortem)
- [GitHub Advisory GHSA-g7cv-rxg3-hmpx](https://github.com/advisories/GHSA-g7cv-rxg3-hmpx)
- [Snyk analysis](https://snyk.io/blog/tanstack-npm-packages-compromised/)
- [Wiz Blog — Mini Shai-Hulud](https://www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised)
- [StepSecurity writeup](https://www.stepsecurity.io/blog/mini-shai-hulud-is-back-a-self-spreading-supply-chain-attack-hits-the-npm-ecosystem)
- [Orca Security — 160+ packages](https://orca.security/resources/blog/tanstack-npm-supply-chain-worm/)

## License

MIT.
