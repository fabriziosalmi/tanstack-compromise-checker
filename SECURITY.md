# Security policy

## Reporting a vulnerability

Please **do not** open public GitHub issues for security vulnerabilities in
this repository, in `check.sh`, in the published Docker image, or in the
GitHub Action.

Two channels are accepted:

- GitHub [private vulnerability reporting](https://github.com/fabriziosalmi/tanstack-compromise-checker/security/advisories/new) (preferred).
- Email <fabrizio.salmi@gmail.com> with subject `[security] tanstack-compromise-checker`.

You should receive an acknowledgement within 72 hours. Coordinated disclosure
is typically 90 days from acknowledgement, faster for actively-exploited
issues.

## Supply-chain posture of this repository

This repository defends itself against the same class of attack it is built
to detect:

- **Pinned GitHub Actions.** Every `uses:` references a 40-character commit
  SHA, not a floating tag. A tag-rewrite attack on an upstream action does
  not affect this repo until a Dependabot PR is reviewed and merged.
- **Pinned Docker base.** The `Dockerfile` pins `alpine` to a specific
  multi-arch manifest index digest. The base layer cannot be re-pointed.
- **Minimum-privilege workflows.** Every workflow declares `permissions: {}`
  at the top level and grants per-job tokens only where needed
  (`contents: read`, `packages: write` on release, etc.).
- **No persistent credentials in workspace.** `actions/checkout` is invoked
  with `persist-credentials: false`, so no authenticated git remote is left
  behind for any subsequent step (including the Docker action itself) to
  read.
- **Runner egress monitored.** [`step-security/harden-runner`](https://github.com/step-security/harden-runner)
  is the first step of every workflow. It logs and (when allow-list is
  stable) blocks unexpected outbound network traffic from the runner.
- **OpenSSF Scorecard.** Runs weekly and on every push to `main`. Results
  are published to the public OpenSSF dataset and uploaded as SARIF.
- **Dependabot.** Weekly updates for both GitHub Actions and Docker pins.
  Every update is reviewed and the proposed SHA is verified against the
  upstream release tag before merging.
- **Signed build provenance.** Each release publishes a Docker image to
  `ghcr.io` together with a [SLSA build provenance attestation](https://slsa.dev/spec/v1.0/provenance)
  signed with a workflow-bound OIDC identity. Anyone can verify it with
  `gh attestation verify oci://ghcr.io/fabriziosalmi/tanstack-compromise-checker:<tag> --repo fabriziosalmi/tanstack-compromise-checker`.
- **SHA-256 release manifest.** Every release has a `check.sh.sha256` asset
  covering `check.sh`, `action.yml`, `entrypoint.sh`, and `Dockerfile`. Run
  `sha256sum -c check.sh.sha256` before executing anything.

## Verifying a release

```sh
TAG=v1.0.0   # replace with the release you want
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh.sha256
sha256sum -c check.sh.sha256
bash check.sh
```

## Verifying the Docker image

```sh
TAG=v1.0.0
IMAGE=ghcr.io/fabriziosalmi/tanstack-compromise-checker:$TAG
gh attestation verify oci://$IMAGE --repo fabriziosalmi/tanstack-compromise-checker
```

## Recognising follow-on social-engineering attempts

Authors of detection tools for active campaigns are themselves a high-value
target — once compromised, their tool can be used to distribute payloads to
the defenders who trust them. The pattern observed on 2026-05-18 against this
project, documented here so other defenders can recognise it:

- **Email from a personal Gmail / Outlook address**, not an organisational
  one, claiming to represent an unspecified "Security Team" or "internal
  scanning tools".
- **Recommends a third-party repository** ("we are sharing our local scan
  parameters") that has either a typosquat name (e.g. *tanscript* vs
  *tanstack*) or is unrelated to the sender's identity.
- **Suggests integration / bundling** of that repository's logic into the
  recipient's project, often framed as helping the upstream postmortem.
- Sent within hours or days of a public release of the recipient's tool.
- The cited repository may itself be benign at the time of writing —
  the trust is the asset, not the current code.

The correct response is the same regardless of intent:

1. Do not clone, do not pipe, do not integrate the recommended code based
   on the email.
2. Do not reply — a reply confirms the address is monitored.
3. If you want to evaluate the referenced repository on its merits, read it
   passively (web UI or `gh api … --jq .content | base64 -d`), never on a
   developer machine with execution privileges.
4. Flag the email as phishing in your provider. Notify the repository owner
   you were directed to — they may be a co-victim, not the attacker.

This project's collaboration boundary is: incoming security input via
[GitHub private advisory](https://github.com/fabriziosalmi/tanstack-compromise-checker/security/advisories/new),
PRs against the public repo, or the [Discussions](https://github.com/fabriziosalmi/tanstack-compromise-checker/discussions)
tab. Out-of-band recommendations to install or integrate something are
never acted on.

## Do not pipe `curl | bash`

Including for this tool. The very attack class this script detects
propagated through unverified code execution. Always: download, verify
checksum, inspect (`less check.sh`), then run.
