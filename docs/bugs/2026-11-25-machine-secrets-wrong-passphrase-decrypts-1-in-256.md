# machine-secrets: a wrong passphrase "decrypts" about 1 time in 256 (flaky BATS test 18)

**Status:** OPEN — captured 2026-11-25
**Priority:** P3 (test-only flake about 0.4% per run; the import still fails safe)
**Classified:** P2 by gemini-4-argon-medium, 2026-11-25 — Unauthenticated CBC decryption causes 1-in-256 flaky test failures and relies on payload format rejection rather than cryptographic integrity to catch wrong keys or tampering
**Triage:** carry → v1.47.0 — triage 2026-11-25, operator ("go with your recommendation")
**Branch:** `k3d-manager-v1.47.0`
**Introduced by:** pre-existing (`bin/k3dm-machine-secrets` import, unauthenticated `openssl enc -aes-256-cbc`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-25
**Prior art:** none above threshold (grep of docs/bugs for "wrong passphrase", "could not decrypt", "padding": no match on this symptom; vector store unreachable)

## Symptom

CI run 45690716068 (`88d86c23`, docs-only commit), shard 4: `not ok 18 machine secrets: wrong passphrase does not modify keychain or
delete file`, at `scripts/tests/bin/machine_secrets.bats:318`: `[[ "$output" == *'could not decrypt'* ]]` failed. The same test passed
3/3 locally on M4 the same day and on CI for `f04e5a41`; neither the script nor the test changed since v1.44.0 (`46ec5b36`).

## Cause

The import decrypts with `openssl enc -d -aes-256-cbc -pbkdf2` (`bin/k3dm-machine-secrets:184`). CBC has no integrity check: with a
wrong key, openssl rejects the output only when the final block's PKCS#7 padding is invalid, and a random block has valid padding about
1 time in 256. The salt is random per encryption, so the test hits that case nondeterministically: openssl exits 0, `could not decrypt`
is never printed, and the garbage plaintext goes to the record loop.

## Why it stays safe today

The garbage almost never forms a line of three tab-separated fields matching the name and hex patterns (`:189-194`), so it is
`rejected (bad name)`, the import exits 1, the file is kept, and nothing is added to the Keychain — which is what the rest of test 18
asserts. The weakness is broader than the test: a tampered or truncated transfer file is likewise not detected as such.

## Proposed fix (for triage)

Make a wrong key fail deterministically: `export` writes a fixed first plaintext line (e.g. `# k3dm machine-secrets v1`) inside the
encryption; `import` treats a missing or different first line as `could not decrypt`. Optionally add an HMAC over the ciphertext for
tamper detection. Then test 18 is deterministic; add a test that a file encrypted without the header is refused with `could not
decrypt`, and decide whether older header-less transfer files (transient by design) need a one-release fallback.
