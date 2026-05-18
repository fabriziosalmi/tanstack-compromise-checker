<!--
  Thanks for the contribution. To keep this repository's supply-chain
  posture intact, please fill every checkbox below honestly. PRs that
  leave the security checklist unfilled will not be merged.
-->

## What this PR changes

<!-- Single-paragraph description. What and why. Skip the “how” — that’s in the diff. -->

## Security checklist

- [ ] **No new runtime dependencies** in `check.sh` (bash + `jq` + `python3` + `curl` only).
- [ ] **Every changed/added regex or pattern array** is exercised by a test in `tests/smoke.sh`. If you cannot write a deterministic fixture, explain why in the PR body.
- [ ] **No non-ASCII characters** in `check.sh`, `entrypoint.sh`, `action.yml`, `Dockerfile`, or any workflow file (the `tests` workflow enforces this via the Trojan-Source linter).
- [ ] **All `uses:` references in any workflow change** are pinned to a 40-character commit SHA, with the human-readable version in a trailing `# v…` comment.
- [ ] **No new files outside the existing tree shape**: `check.sh`, `entrypoint.sh`, `action.yml`, `Dockerfile`, `tests/**`, `docs/**`, `.github/**`, top-level `*.md`.
- [ ] **No automation / curl/wget / network access** is added inside the script that runs outside the existing `--online` flag.
- [ ] If the PR adds a new IOC: the source is **public** (advisory, postmortem, vendor blog, peer detector with MIT/Apache license) and a `# attribution: <source>` comment is included on or above the new line(s).

## How I validated this locally

<!-- Run these before opening the PR. Paste the output. -->

```sh
bash tests/smoke.sh
shellcheck --severity=warning -x check.sh entrypoint.sh tests/smoke.sh
HOME=$(mktemp -d) bash check.sh --scan-dir . --json --no-color > /tmp/scan.json
jq .summary /tmp/scan.json
```

## Out-of-scope reminders

- PRs offering to “integrate” a third-party repository’s logic in bulk are not accepted — port specific IOCs with public attribution instead. See `SECURITY.md` § "Recognising follow-on social-engineering attempts".
- Refactors that touch >100 LOC in `check.sh` need a prior issue discussing the rationale.
