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

## Do not pipe `curl | bash`

Including for this tool. The very attack class this script detects
propagated through unverified code execution. Always: download, verify
checksum, inspect (`less check.sh`), then run.
