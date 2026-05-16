# Tests

Smoke tests for `check.sh`. The fixtures are minimal `package.json` trees that
exercise the two main outcomes:

- `fixtures/clean-project/` — declares only unaffected TanStack family members;
  the checker should return exit `0`.
- `fixtures/compromised-project/` — declares `@tanstack/react-router@1.169.5`
  (a known-malicious pin) and has a matching `node_modules/` entry; the
  checker should return exit `2`.

## Running

```sh
bash tests/smoke.sh
```

## Adding a test

1. Create a new directory under `fixtures/` with a `package.json` (and an
   optional `node_modules/` tree) that triggers the rule you're testing.
2. Add a `run "name" <expected-exit> "$HERE/fixtures/<your-dir>"` line in
   `smoke.sh`.
3. Verify the smoke suite fails on `main` before your `check.sh` change and
   passes after.
