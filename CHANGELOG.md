# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] — 2026-05-18

### Added
- **`check.sh --verify-self`** — the script now fetches its own SHA-256
  manifest from the matching GitHub Release and compares it against the
  hash of the local copy. Exits 0 on match, 4 on mismatch, 5 on
  network/parse error. Lets users verify the script hasn't been tampered
  with locally without having to re-download.
- **Sigstore keyless signing** of `check.sh` and `check.sh.sha256` on
  every release. Each release ships an additional `.sigstore.json`
  bundle that anyone can verify with
  `cosign verify-blob --bundle … --certificate-identity-regexp 'https://github.com/.../\.github/workflows/release\.yml@.*' --certificate-oidc-issuer https://token.actions.githubusercontent.com`.
  Bound to this workflow path via OIDC; no key management on either side.
- **Trojan-Source linter** in the `tests` workflow. Refuses to land
  bidi-override / zero-width / BOM characters in `check.sh`, `entrypoint.sh`,
  `action.yml`, `Dockerfile`, `tests/smoke.sh`, or any `.github/workflows/*.yml`.
  Defends against CVE-2021-42574-style invisible-malware PRs.
- **Structured issue templates** under `.github/ISSUE_TEMPLATE/`: bug
  reports require version + entrypoint + reproducer + confirmations; new
  IOC requests require a public source URL + false-positive-risk
  assessment. Blank issues disabled.
- **PR template** with a mandatory security checklist (no new runtime
  deps, every regex change tested, no non-ASCII in security-critical
  files, pinned SHAs, attribution for new IOCs).
- **`docs/THREAT-MODEL.md`** — public threat model with attacker profiles,
  vector × control matrix, trust-boundary statement, and end-to-end
  verification recipe for outside auditors.

### Changed
- `CONTRIBUTING.md` codifies six mandatory PR rules (test required for
  regex/IOC changes, no non-ASCII, ≤100 LOC for `check.sh` changes
  without a prior issue, public attribution for IOCs, no third-party
  bundling, no new runtime deps).
- `dependabot.yml`: `open-pull-requests-limit` lowered from 5 to 3 to
  reduce review-fatigue risk on Dependabot PRs (the load-bearing
  defence against tag-rewrite attacks upstream).

## [1.1.2] — 2026-05-18

### Added
- Additional Mini Shai-Hulud IOCs cross-checked with
  [`nkopylov/tanscript-exploit-check`](https://github.com/nkopylov/tanscript-exploit-check):
  - 3 known payload SHA-256 hashes — computed when a payload-shaped file is
    found in `node_modules` and reported alongside the filename match.
  - `opensearch_init.js` and `vite_setup.mjs` added to `PAYLOAD_FILES`.
  - `opensearch_init` added to the active-payload-process pgrep regex.
  - Known malicious commit SHA `79ac49ee…cfe5885c` flagged when referenced
    in any `package.json` under `node_modules`.
  - C2 IP literal `83.142.209.194` added to `C2_DOMAINS_RE`.
  - Dune-themed Mini Shai-Hulud branch pattern (`dependabot/github_actions/format/<atreides|fremen|harkonnen|…>`) — 22 codewords.
  - Additional pinned bad versions: `@tanstack/react-start@1.167.68`,
    `@1.167.71`, `@tanstack/router-plugin@1.167.38`, `@1.167.41`.
  - GitHub Actions Check 7 now flags `codeql_analysis.yml` workflows that
    contain `toJSON(secrets)` — the signature exfiltration pattern.
- `SECURITY.md`: new section "Recognising follow-on social-engineering
  attempts" documenting a phishing pattern observed against detector authors
  in this niche.

## [1.1.1] — 2026-05-16

### Fixed
- Check 8 C2-domain and disposable-host grep now excludes documentation
  files (`*.md`, `*.markdown`, `*.rst`, `*.txt`), the project's own root
  docs (`CHANGELOG*`, `README*`, `SECURITY*`, `FAQ*`, `CONTRIBUTING*`),
  and `check.sh` itself. The v1.1.0 self-test failed because the checker
  was flagging the IOC list inside its own CHANGELOG as a C2 reference.

## [1.1.0] — 2026-05-16

### Added
- New Check 8 — **Mini Shai-Hulud payload + auxiliary IOCs**. Covers payload
  files in `node_modules` (`router_init.js`, `tanstack_runner.js`,
  `router_runtime.js`), the `@tanstack/setup` optionalDependency infection
  vector, payload artefacts on host and in repo (`~/.claude/router_runtime.js`,
  `.claude/setup.mjs`, `.vscode/setup.mjs`), AI-tool config tampering
  (Claude Code `settings.json`, `mcp.json`, Kiro `mcp.json`, VSCode
  `tasks.json`), C2 / exfiltration domain references in source
  (`api.masscan.cloud`, `git-tanstack.com`, `getsession.org`,
  `litter.catbox.moe`), attacker commit author
  (`claude@users.noreply.github.com`), suspicious branch patterns
  (`dependabout/*/setup-formatter` — the typo is the attacker fingerprint),
  ransom-marked npm tokens, and active payload processes.
- Worm-propagated secondary victim packages added to the known-bad list and
  detected by family-name in `node_modules`: `@mistralai/mistralai`,
  `@mistralai/mistralai-azure`, `@mistralai/mistralai-gcp`,
  `@opensearch-project/opensearch`, `@draftlab/auth`,
  `@draftlab/auth-router`, `@draftlab/db`, `safe-action`.
- **Heuristic / zero-day-style flagging** (info severity, never fails the
  build): suspicious payload-shaped filenames in `node_modules` outside the
  exact known list, disposable-endpoint hosts (`webhook.site`, `ngrok`,
  `requestbin.net`, etc.) referenced in source, coercion-language in npm
  token descriptions, non-empty global git `core.hooksPath`.
- Tests now ship in `tests/`: a smoke suite with `clean-project` and
  `compromised-project` fixtures, exercised by a new `tests` CI workflow
  that also runs `shellcheck` on `check.sh` / `entrypoint.sh` / `smoke.sh`.

### Fixed
- `scorecard.yml` pins of `ossf/scorecard-action` and
  `github/codeql-action` resolved through their annotated-tag SHAs to the
  underlying commit SHAs (the tag-object SHA was being rejected by
  Scorecard's webapp verification as an imposter commit).
- `check.sh` `add_finding`: split `local`+assignment to stop masking
  command-substitution exit codes (shellcheck SC2155).

### Changed
- `Dockerfile` declares a non-root `tcc` user (UID 1001, matching the
  GitHub Actions runner UID) so the container no longer runs as root.

### Hygiene
- Added LICENSE (MIT), `.gitignore`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
  (Contributor Covenant 2.1, official text), `CHANGELOG.md`.

## [1.0.0] — 2026-05-16

### Added
- Seven-stage detection script (`check.sh`) for the TanStack npm supply-chain
  attack (CVE-2026-45321 / GHSA-g7cv-rxg3-hmpx): dead-man's switch artefacts,
  persistence vectors, credential exposure, network IOCs, `package.json` +
  lockfile scanning, installed `node_modules` verification, and GitHub
  Actions hardening hints.
- `--online` mode: fetches the GHSA advisory and confirms compromise via
  the npm registry's `time[<version>]` field instead of relying solely on a
  hard-coded version list.
- `--json` output for SIEM and CI integration.
- Multi-arch Docker image published to `ghcr.io` on every tagged release,
  with signed [SLSA build provenance](https://slsa.dev/spec/v1.0/provenance)
  verifiable via `gh attestation verify`.
- GitHub Action wrapper with explicit inputs, outputs, and a hardened
  self-test workflow that runs the action against its own repository.
- Release workflow that ships `check.sh` + `check.sh.sha256` on every tag,
  letting users verify the script before running it.
- Repo-level hardening: every `uses:` pinned to a 40-character commit SHA,
  `permissions: {}` at workflow root, `persist-credentials: false` on every
  checkout, `step-security/harden-runner` as the first step, OpenSSF
  Scorecard analysis weekly, Dependabot for github-actions and Docker pins.

[Unreleased]: https://github.com/fabriziosalmi/tanstack-compromise-checker/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/fabriziosalmi/tanstack-compromise-checker/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/fabriziosalmi/tanstack-compromise-checker/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/fabriziosalmi/tanstack-compromise-checker/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/fabriziosalmi/tanstack-compromise-checker/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/tag/v1.0.0
