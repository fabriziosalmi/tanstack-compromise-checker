# Contributing

Thanks for considering a contribution. This project is small on purpose —
a single bash script, a Dockerfile, and a GitHub Action — but the
maintenance bar is high because it's a security tool.

## Getting set up

```sh
git clone https://github.com/fabriziosalmi/tanstack-compromise-checker
cd tanstack-compromise-checker
# Optional: shellcheck and bats for local testing
brew install shellcheck bats-core   # macOS
# apt install shellcheck bats        # Debian/Ubuntu
```

The script itself has no runtime dependency you don't already have. `jq`
is recommended for stricter JSON parsing; `python3` is the fallback.

## Running locally

```sh
# Run against your home directory (default scope)
bash check.sh

# Run against a synthetic fixture with a compromised pin
bash check.sh --scan-dir tests/fixtures/compromised-project
```

The self-test fixtures under `tests/fixtures/` exist precisely to give you
something that should make the checker exit non-zero. If you change a
detection rule, add a fixture that exercises it.

## Running the tests

```sh
# Quick smoke test (POSIX sh, exits non-zero on a regression)
bash tests/smoke.sh

# Optional: full bats suite (if installed)
bats tests/
```

Add a test for any new detection rule or any bug fix. The test should
fail on `main` before your change and pass after.

## Style guidelines

- **No new dependencies in `check.sh`.** Stay in the POSIX-bash + `jq` +
  optional Python lane.
- **Read-only by default.** A detection step must never write to the
  scanned filesystem unless `--apply` is explicitly passed and the script
  refuses blind destructive operations.
- **Severity discipline.** `warn` is for "might be a real problem,
  needs eyes"; `fail` is for "we are confident this is compromise".
  Reach for `warn` more often than `fail`.
- **Run `shellcheck check.sh`** before committing. The CI does it too.
- **Tag pins.** Any `uses:` in a workflow must be pinned to a 40-character
  commit SHA, with the human-readable version in a trailing comment
  (e.g. `# v2.19.3`). Dependabot keeps these current.

## Commit messages

Conventional Commits, optional. The maintainer squashes most PRs into a
single commit at merge time, so a clear PR title matters more than
individual commit titles.

## PR flow

1. Open an issue first for anything larger than a one-file change.
2. Fork, branch from `main`.
3. Run the self-test fixtures locally; make sure your change still works
   on the clean fixture *and* triggers on a compromised one.
4. Open the PR. The hardened CI workflow will run automatically.
5. The maintainer reviews. CODEOWNERS requires a review on critical
   files (`check.sh`, `Dockerfile`, `action.yml`, `entrypoint.sh`,
   `.github/`).

## Security issues

Do **not** open a public issue or PR for a security vulnerability. Use
the [private vulnerability reporting](https://github.com/fabriziosalmi/tanstack-compromise-checker/security/advisories/new)
or email the maintainer. See [SECURITY.md](SECURITY.md) for the policy.

## Code of conduct

This project follows the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md).
By participating, you agree to abide by it.

## License

All contributions land under [MIT](LICENSE) — same as the rest of the
project.
