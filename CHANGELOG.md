# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/fabriziosalmi/tanstack-compromise-checker/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/tag/v1.0.0
