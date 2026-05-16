# FAQ — tanstack-compromise-checker

Short, technical answers to questions developers and security teams keep
asking about the TanStack npm supply-chain attack and this detection tool.

- [About the attack](#about-the-attack)
- [Using the checker](#using-the-checker)
- [Detection details](#detection-details)
- [False positives and false negatives](#false-positives-and-false-negatives)
- [Security and verification](#security-and-verification)
- [CI/CD and Docker](#cicd-and-docker)

## About the attack

### What is CVE-2026-45321?

A coordinated supply-chain compromise of the [TanStack](https://tanstack.com)
ecosystem published on **May 11 2026**. The attacker pushed 84 malicious
versions across 42 `@tanstack/*` packages by poisoning the cache of the
TanStack release GitHub Actions workflow. Full advisory:
[GHSA-g7cv-rxg3-hmpx](https://github.com/advisories/GHSA-g7cv-rxg3-hmpx).

### What does the malicious payload do?

Three things, in order:

1. Exfiltrates GitHub, npm, AWS, GCP, and Azure tokens it finds on the host
   to an attacker-controlled C2.
2. Installs a "dead-man's switch" daemon (`~/.local/bin/gh-token-monitor.sh`)
   registered as a LaunchAgent on macOS or a systemd user unit on Linux.
3. The daemon polls GitHub for the stolen token; if the token is revoked, it
   executes `rm -rf ~/` before the operator can finish remediation.

This is why the [incident response](#what-do-i-do-if-the-checker-finds-something)
order matters: stop the daemon *before* revoking the token.

### Which packages are affected?

The TanStack Router family and adjacent packages: `@tanstack/router`,
`@tanstack/react-router`, `@tanstack/history`, `@tanstack/start`,
`@tanstack/eslint-plugin-router`, and others.

Confirmed *not* compromised: `@tanstack/react-query`,
`@tanstack/react-table`, `@tanstack/react-virtual`, `@tanstack/form`,
`@tanstack/store`. These come from a different release pipeline.

### Is this related to Shai-Hulud?

The payload is a variant of the Shai-Hulud worm pattern that hit npm a few
months earlier. The Mini-Shai-Hulud designation refers specifically to the
TanStack incident; see the [Wiz writeup](https://www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised)
and the [Orca analysis covering ~160 packages](https://orca.security/resources/blog/tanstack-npm-supply-chain-worm/).

## Using the checker

### How do I check whether I am affected?

The fast path on macOS, Linux, or WSL2 is:

```sh
TAG=v1.0.0
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh.sha256
sha256sum -c check.sh.sha256
bash check.sh --online
```

On Windows, or anywhere you'd rather not install bash, use the Docker image
or the GitHub Action. See the [Quick start in the README](README.md#quick-start).

### Does it work on Windows?

Three supported paths:

- **WSL2** — install once, then run the bash script directly.
- **Git Bash** — ships with Git for Windows. The script runs but some
  POSIX-only system probes (LaunchAgents, systemd) silently skip.
- **Docker Desktop** — works without any other dependency. Recommended for
  Windows developers and Windows CI runners that allow Docker.

There is no PowerShell port. The script is intentionally a single bash file
to keep its attack surface small.

### What does `--online` actually do?

Two things:

1. Fetches the live GHSA advisory and uses its `vulnerable_version_range`
   list, so detection tracks the advisory state instead of a frozen list.
2. For every `@tanstack/*` package found installed, queries the npm
   registry's `time[<version>]` and confirms whether that version was
   published inside the attack window. This catches malicious versions that
   were *not* hard-coded in the script.

`--online` adds two HTTPS round-trips per affected package. Off by default
because some CI environments restrict outbound networking and would fail.

### Can I scan only one project?

Yes, with `--scan-dir`:

```sh
bash check.sh --scan-dir /path/to/your/project
```

The script refuses `--scan-dir /`, `--scan-dir /etc`, and similar system
directories to avoid wasted IO and accidental privilege escalation.

### What's the difference between `--fix` and `--apply`?

`--fix` prints `npm pin` / `pnpm update` suggestions for affected
dependencies — purely informational. `--apply` would execute them, but the
script currently refuses blind execution because `npm update` respects the
range in `package.json` and could re-pin to *another* compromised version
inside the same family. Manual pinning to a known-clean version is required.

## Detection details

### What exactly does each check do?

| # | Check | Concrete probe |
|---|-------|---|
| 1 | Dead-man's switch | `~/.local/bin/gh-token-monitor.sh`, `~/Library/LaunchAgents/com.user.gh-token-monitor.plist`, `/Library/LaunchDaemons/*gh-token*`, `systemctl --user list-units 'gh-token*'`, `pgrep -f gh-token-monitor` |
| 2 | Persistence | shell rc files (`~/.bashrc`, `~/.zshrc`, `~/.profile`), user and system crontab, `/etc/cron.{d,daily,hourly}`, `~/.config/autostart/*.desktop`, `git config --global core.hooksPath` |
| 3 | Credentials | env-var probe, `~/.npmrc`, `~/.yarnrc.yml`, `~/.aws/credentials`, `~/.config/gh/hosts.yml`, `~/.netrc`, `~/.docker/config.json`, `~/.kube/config`, enumeration (not contents) of `.env*` |
| 4 | Network IOC | `lsof -i -P -n` (or `ss -tnp`) on `node` PIDs with ESTABLISHED outbound TCP. Heuristic — manual triage required |
| 5 | Repo scan | parse every `package.json` and every lockfile (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`) under scan dir; report any `@tanstack/*` declared at a compromised pin |
| 6 | Installed | `find … -path '*/node_modules/@tanstack/*/package.json'`, parse, compare against known-bad list. With `--online`: also confirm via npm registry `time[<version>]` |
| 7 | Actions hints | grep `.github/workflows/*.{yml,yaml}` for `pull_request_target`, missing `--ignore-scripts`, `actions/cache@*` patterns that helped propagate the attack |

### Why do I need both check 5 and check 6?

They cover different states of the same project. Check 5 sees the *intent*
of the project (declared deps + lockfile pins) — it works on a freshly
cloned repo before `npm install`. Check 6 sees the *reality* on disk —
`node_modules` after install, even when the lockfile was uncommitted.

A clean lockfile with a poisoned `node_modules` is a real scenario when the
attacker poisoned a registry-mirror or a local cache.

### How does `--online` decide a version is malicious?

Two signals:

- The GHSA advisory explicitly lists `<package>` with a vulnerable range
  that contains `<version>`. Authoritative.
- The npm registry says `<version>` was published within the attack window
  (`2026-05-11T19:00Z` to `2026-05-11T22:00Z`, configurable with
  `--attack-window-start` / `--attack-window-end`). Heuristic but catches
  versions absent from the advisory.

Either signal is sufficient to escalate from warn to fail.

## False positives and false negatives

### I have `@tanstack/router` installed but the version is clean — why am I warned?

In **offline mode** (no `--online`), the script issues a warning whenever a
package is in the affected *family* even if the version is not on the
hard-coded bad list. It cannot tell a freshly-pinned safe version apart
from an unknown-but-possibly-bad one without registry access.

In `--online` mode the script downgrades that warning to a pass when the
npm registry confirms the version was published outside the attack window.

### The script flags a path in `node_modules/.../template/`. Is it real?

Usually a false positive from scaffolding/template files (CLI generators
ship example `package.json` files inside their published artefacts). The
v1.0.0 release prunes `*/template/*`, `*/templates/*`, `*/fixtures/*`,
`*/__tests__/*` from check 5, but `node_modules` can still contain them via
nested transitive packages. Treat as informational unless the path is in a
non-template location.

### Why doesn't the script detect every variant in the wild?

It is a fast, dependency-light first-line tool. Two boundaries:

- It identifies the TanStack family by name, not by hash. An attacker who
  renames the malicious package can defeat the name-match. The `--online`
  mode adds a publish-time signal that is harder to spoof but not
  impossible.
- It does not perform deep payload analysis (no JS AST walking, no
  signature scan). For that, layer it with `socket-cli`, `npm audit`, or
  the per-vendor scanners linked in the README references.

### What if the host is already wiped by the dead-man's switch?

Boot a forensic image, `tar` the surviving filesystem to read-only media,
then run the script against the mounted image with `--scan-dir
/mnt/forensic`. The script refuses obviously-system paths but a non-system
mount point is fine.

## Security and verification

### Is it safe to run on a compromised machine?

The script does not execute, modify, or upload any payload. It reads files
and runs `find`, `grep`, `curl` (only when `--online`). It does not need
sudo. That said: if your host is compromised, your shell, your `curl`, and
your `find` may also be untrusted. The conservative path is to verify the
script on a clean host, copy it over, and run it inside a forensic shell.

### How do I verify the script before running it?

```sh
TAG=v1.0.0
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh
curl -fsSLO https://github.com/fabriziosalmi/tanstack-compromise-checker/releases/download/$TAG/check.sh.sha256
sha256sum -c check.sh.sha256
```

`check.sh.sha256` covers `check.sh`, `action.yml`, `entrypoint.sh`, and
`Dockerfile` together so they cannot drift independently.

### How do I verify the Docker image?

```sh
TAG=v1.0.0
gh attestation verify \
  oci://ghcr.io/fabriziosalmi/tanstack-compromise-checker:$TAG \
  --repo fabriziosalmi/tanstack-compromise-checker
```

The release workflow signs a [SLSA build provenance](https://slsa.dev/spec/v1.0/provenance)
statement with a workflow-bound OIDC identity. `gh attestation verify`
checks that the image you just pulled was actually built from this
repository at the tagged commit.

### Can the script itself be tampered with?

In transit, no — TLS-pinned and integrity-checked via `sha256sum`. At rest
on this repo, it would require pushing to `main`. The repo enforces
maintainer review through CODEOWNERS and runs an end-to-end self-test on
every push. A drift would be visible in the [Actions tab](https://github.com/fabriziosalmi/tanstack-compromise-checker/actions).

## CI/CD and Docker

### How do I block compromised dependencies in a PR?

Drop this step into your existing workflow:

```yaml
- uses: fabriziosalmi/tanstack-compromise-checker@v1
  with:
    scan-dir: .
    online: 'true'
    fail-on: fail
```

`fail-on: fail` makes the workflow exit non-zero only on confirmed
compromise (exit code 2). Use `fail-on: warn` if you want warnings to
break the build as well.

### Does the GitHub Action need any secrets?

No. The action only needs `contents: read` on the checkout step and no
write tokens. The published Docker image needs the runner to be able to
reach `ghcr.io`, `api.github.com`, `registry.npmjs.org`.

### Can I run it in a private network without outbound access?

Yes, in offline mode (drop `--online`). The hard-coded list of compromised
versions ships with the script and is enough to catch the immediate attack
window. The advisory fetch and publish-time verification are skipped.

### How do I integrate findings into Wazuh, Splunk, or another SIEM?

Use `--json` (or the action's `json-output` input) and pipe the JSON into
your forwarder. Structure:

```json
{
  "version": "1.0.0",
  "summary": { "passed": 6, "warnings": 0, "failed": 1 },
  "findings": [
    {
      "check": "installed-modules",
      "severity": "fail",
      "package": "@tanstack/router",
      "version": "1.169.5",
      "path": "/path/to/node_modules/@tanstack/router/package.json",
      "message": "registry-confirmed malicious by publishTime"
    }
  ]
}
```

`severity` is one of `pass`, `warn`, `fail`; one finding per indicator.

### How is this different from `npm audit`?

`npm audit` consumes the GHSA database too, but it only inspects the
declared dependencies of *one* project. This tool also looks at the
machine-wide state (dead-man's switch, persistence, credential exposure)
that an `npm audit` cannot see — and it scans multiple repositories in one
invocation. They are complements, not substitutes.

## Still stuck?

Open a [Discussion](https://github.com/fabriziosalmi/tanstack-compromise-checker/discussions)
for usage questions, or a private security report via
[GitHub's vulnerability reporting](https://github.com/fabriziosalmi/tanstack-compromise-checker/security/advisories/new)
for sensitive findings. See [`SECURITY.md`](SECURITY.md) for the disclosure
policy.
