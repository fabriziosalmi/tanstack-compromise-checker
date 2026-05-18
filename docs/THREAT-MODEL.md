# Threat Model

A defender publishing a public tool that detects an active supply-chain
campaign is themselves a target — once compromised, their tool can be
weaponised against every consumer who trusts it. This document is the
public part of the threat model for `tanstack-compromise-checker`. It
exists for two reasons: to make the project's own posture auditable, and
to give other defender-tool authors a template they can adapt.

A short companion section, kept out of this file, contains the
canary identifiers, the personal escalation contacts, and the rotation
schedule. Those bind to the maintainer's identity rather than the
project's code and have no reason to be public.

## Asset inventory

| Asset | What is protected | Who would attack it |
|---|---|---|
| `check.sh` source as published on `main` and on each tag | Integrity (no malicious rewrite, no Trojan-Source hide) | Mini Shai-Hulud campaign operators; copycat actors |
| The `v1` floating tag + each `v1.x.y` tag | Integrity (no fake tag pushed by a third party) | Account-takeover attackers |
| `ghcr.io/fabriziosalmi/tanstack-compromise-checker` image manifests | Integrity (no poisoned image at a known tag) | Anyone with the GHCR push token for this account |
| The Marketplace listing under this repository | Authenticity (no typosquat impersonation, no delisting via false report) | Reputation attackers; competitors |
| The maintainer's account credentials | Confidentiality + 2FA integrity | Phishing, SIM swap, OAuth abuse |
| The tool's reputation in the security ecosystem | No false-positive avalanche, no smear campaign | Petty actors; ecosystem competitors |

## Attacker profiles

- **A — Mini Shai-Hulud campaign core (TeamPCP).** Technically able,
  worm-class tooling, automation-first, ROI-driven. Re-uses the
  `pull_request_target` + cache-poisoning + OIDC-token-extraction pattern
  documented in [GHSA-g7cv-rxg3-hmpx](https://github.com/advisories/GHSA-g7cv-rxg3-hmpx).
  Will move against detection-tool authors only if cheap.
- **B — Copycat.** Re-uses the public payload. Email and DM are their
  primary channels because they are cheap. Most likely author of the
  social-engineering email observed against this project on 2026-05-18.
- **C — Petty competitor.** Reputational attacks: star-bomb, false CVE,
  forum smear. Does not run code on the maintainer.
- **D — Piggy-backer.** Uses the noise of an active campaign as cover for
  unrelated targeted activity. Out of scope for this document.

## Public attack surface (what an attacker can recon passively)

- The GitHub profile of the maintainer (repo list, contributions, social
  graph).
- Commit metadata, including any `Co-Authored-By:` lines that disclose
  tooling.
- The repository's own published security posture in `SECURITY.md`,
  `CONTRIBUTING.md`, this file, and the workflows under `.github/`.
- The Marketplace listing under this repository.
- The contact addresses in `CODE_OF_CONDUCT.md` and `SECURITY.md`.

## Threat vectors and the controls that exist for each

The vectors below are ordered by `probability × impact`. The two
right-hand columns are the live state of the defence: the **Control**
column points to a concrete artefact in this repository; the **Status**
column is one of `enforced`, `documented`, `audited`, or `manual`.

| # | Vector | Control | Status |
|---|---|---|---|
| 1 | A pull request to `check.sh` that loosens a regex, hides code via Trojan-Source bidi characters, or introduces an `eval`-shaped construct | `CODEOWNERS` requires maintainer review on every touched file; the `tests` workflow runs a Trojan-Source linter and a smoke suite; `CONTRIBUTING.md` requires a test for every regex change; the PR template enumerates the security checklist | enforced |
| 2 | An issue that points the maintainer at a third-party repository to "investigate as a reproducer" or "integrate as an extension" | `SECURITY.md` § "Recognising follow-on social-engineering attempts" forbids out-of-band trust; issue templates surface this rule at the top of every new report | documented |
| 3 | An unsolicited email or DM from a personal address recommending a third-party scanner / parameters / advisory | Same as #2; observed real-world example documented at [issues/1 of the lure repo](https://github.com/nkopylov/tanscript-exploit-check/issues/1) | documented |
| 4 | Tag rewrite on an upstream action this repository pins | Every `uses:` is pinned to a 40-character commit SHA, with the readable version in a trailing comment; Dependabot opens PRs against the pinned SHAs and each PR must pass the same gates as a hand-written one; `open-pull-requests-limit: 3` reduces review-fatigue risk | enforced |
| 5 | Typosquat of the Marketplace Action or the `ghcr.io` image | Release workflow signs the image with SLSA build provenance bound to this repository's OIDC identity; `check.sh` and its `.sha256` manifest are signed with Sigstore keyless cosign; `check.sh --verify-self` lets anyone confirm integrity against the official release | enforced |
| 6 | GitHub-account takeover of the maintainer (SIM swap, OAuth abuse, phished 2FA) | Out of this document's scope (binds to the maintainer's identity, not the project). The maintainer commits to FIDO2 + audit-log review weekly in the private companion document | manual |
| 7 | Issue spam, star-bomb, false CVE report, social smear | Public boundary in `SECURITY.md`; issue templates with required structured fields; this `THREAT-MODEL.md` itself is the calmly-stated public reply | documented |
| 8 | Compromise of the Docker base image upstream | Base pinned to a specific multi-arch manifest digest (`alpine:3.20.10@sha256:…`); Dependabot tracks base-image bumps; the Dockerfile declares a non-root `tcc` user (UID 1001) to reduce blast radius | enforced |
| 9 | Lateral via another repository under the same maintainer | Out of scope for this file (different repos, different posture); the maintainer applies analogous patterns elsewhere | manual |
| 10 | The "long game" — same actor returns at 60–90 days expecting reduced vigilance | This file's existence and the codified `CONTRIBUTING.md` rules are designed to survive context loss; the maintainer rereads them as a forcing function | documented |

## Trust boundary: how to communicate with this project

There are three channels. Anything outside them is treated as untrusted.

1. **Security vulnerabilities** —
   [GitHub private vulnerability reporting](https://github.com/fabriziosalmi/tanstack-compromise-checker/security/advisories/new).
   First-response target: 72 hours.
2. **Defects, IOC requests, feature requests** — public issues, using
   the structured templates under `.github/ISSUE_TEMPLATE/`.
3. **Usage questions, discussions, cross-tool coordination with other
   defender authors** —
   [Discussions](https://github.com/fabriziosalmi/tanstack-compromise-checker/discussions).

Out-of-band recommendations (email, DM, in-person at a conference) are
never acted on the same day. They are at most a prompt to open a
public issue or advisory in one of the three channels above. If a
recommendation cannot be made through one of those channels, it cannot
be acted on at all.

## Verifying everything from the outside

Anyone — including an auditor with no prior relationship to this
project — can verify the chain end-to-end:

```sh
TAG=v1.2.0   # or whichever release you are checking

# 1. Fetch the script + its manifest from the GitHub Release.
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh.sha256
sha256sum -c check.sh.sha256

# 2. Verify the Sigstore signature (bound to this exact workflow).
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh.sigstore.json
cosign verify-blob \
  --bundle check.sh.sigstore.json \
  --certificate-identity-regexp 'https://github.com/fabriziosalmi/tanstack-compromise-checker/\.github/workflows/release\.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  check.sh

# 3. Verify the Docker image provenance (SLSA, signed by the same workflow).
gh attestation verify \
  oci://ghcr.io/fabriziosalmi/tanstack-compromise-checker:$TAG \
  --repo fabriziosalmi/tanstack-compromise-checker

# 4. Have the script verify itself once it is on your machine.
bash check.sh --verify-self
```

A failure at any step is grounds to refuse the release. Open a
[private advisory](https://github.com/fabriziosalmi/tanstack-compromise-checker/security/advisories/new)
if you can reproduce it.

## What this document deliberately does not say

The companion private document covers: the maintainer's canary identifiers
(which email-address-per-channel goes where), the credential rotation
cadence, the cross-repository surface map across the maintainer's other
projects, and the specific hardware key model in use. These are
operational details whose disclosure would only ever help an attacker.
