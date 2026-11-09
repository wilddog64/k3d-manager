# `find-similar-docs` rc-36 hint sends the operator to item access when the keychain is locked for the session

**Status:** OPEN — filed 2026-11-08
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-08
**Introduced by:** 3a254484
**Should have been caught by:** spec
**Severity:** low — no data or service impact; the misleading hint cost one session a needless item change, a new
Keychain item and a GUI detour
**Approval:** operator, 2026-11-08 ("yes", file the hint P3; direction revised after the root cause was found)
**Intent approved:** operator, 2026-11-08
**Prior art:** `docs/bugs/2026-10-03-hub-restore-has-no-single-make-target.md`, `docs/bugs/2026-09-30-vectordb-index-never-refreshes-automatically.md`
(found by grep, not scored) — read, different root cause: both record rc 36 on the Gemini item as an item-access
limit; neither covers a keychain locked for the session. `find-similar-docs` not run: the store is reached through kube
context `k3d-k3d-cluster`, which m4-air does not have.
**Filed:** 2026-11-08
**Detected by:** Claude and the operator, troubleshooting `make find-similar-docs` over SSH on m4-air, 2026-11-08
**Affected:** `scripts/lib/hermes/prior_art.py` (`api_key`), `docs/guides/vector-store.md`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

When `security find-generic-password` returns rc 36, `api_key()` tells the operator the item's access control will not
serve this process and to run `set-generic-password-partition-list`. rc 36 also comes back for every item when the
login keychain is locked for the session, and then the suggested command is the wrong fix.

## Evidence (m4-air, macOS 26.5.2, 2026-11-08, Claude session over SSH)

| Check | Before `security unlock-keychain` | After |
|---|---|---|
| `security show-keychain-info ~/Library/Keychains/login.keychain-db` | rc 36 | rc 0, `no-timeout` |
| Read of `k3dm-stripe-sk-test` and `k3dm-embeddings-api-key` with `-w` | rc 36 | `k3dm-embeddings-api-key` reads, 40 bytes |

`show-keychain-info` reads no item, so it separates the two causes.

## Root cause

`scripts/lib/hermes/prior_art.py:426` maps rc 36 to one cause. `docs/guides/vector-store.md:151` says the same, including
"This is not a locked keychain", which was true of the case it recorded on 2026-09-27 but is not true of every rc 36.
The docstring at `prior_art.py:397` repeats it.

## Fix

1. Reword the rc-36 hint in `api_key()`, text only, in this order: first run
   `security show-keychain-info ~/Library/Keychains/login.keychain-db`, and if that is also refused run
   `security unlock-keychain` in that session; only if it answers, widen the item with the existing
   `set-generic-password-partition-list` text, or export `$K3DM_EMBEDDINGS_API_KEY`.
2. Update the `api_key()` docstring to name both causes.
3. In `docs/guides/vector-store.md`, under "Why item 3 denies a read", add the `show-keychain-info` check as the first
   step and scope the "not a locked keychain" sentence to the case where that check answers. Keep the advice against
   copying the key into a second item.

## Contract readers

| Reader | Changes? |
|---|---|
| `scripts/tests/bin/test_prior_art.py:687` asserts `errSecInteractionNotAllowed` in the message | no: the token stays |
| `scripts/tests/bin/test_prior_art.py:710` asserts the partition-list text, item name, and no `add-generic-password` | no: all stay; a new test covers the order |
| `docs/guides/vector-store.md:151`, `:160`, `:165`, `:182` | `:151` yes; the rest stay |

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/prior_art.py` | hint text and docstring |
| `scripts/tests/bin/test_prior_art.py` | tests for the Acceptance block |
| `docs/guides/vector-store.md` | lock check first |

## Do not

- Do not run `security` from production code to diagnose the lock. This is a text change.
- Do not read or print a real keychain value. Tests stub `subprocess.run`, as the existing rc-36 tests do.
- Do not change the key lookup order or `KEYCHAIN_ITEMS`.

## Acceptance

```yaml
must:
  - id: M1
    text: On rc 36 from the keychain read, the EmbeddingsUnavailable message contains "show-keychain-info" and "unlock-keychain".
  - id: M2
    text: In that message, "show-keychain-info" appears before "set-generic-password-partition-list".
  - id: M3
    text: The message still names errSecInteractionNotAllowed, the item, and the partition-list command.
  - id: M4
    text: docs/guides/vector-store.md mentions show-keychain-info before the first set-generic-password-partition-list in the section "Why item 3 denies a read".
must_not:
  - id: N1
    text: The lock-check text does not appear for a non-36 failure (rc 44 reports no show-keychain-info or unlock-keychain).
  - id: N2
    text: The rc-36 message does not suggest add-generic-password.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    how: pytest in scripts/tests/bin/test_prior_art.py with subprocess.run stubbed for rc 36 and rc 44; N1 is paired with M1 as its positive control; each must_not test shown red against a mutated hint.
    intent: "Proves that when the keychain refuses a read, the message tells you to check whether it is locked before touching the item, and that a simply missing item does not get that advice."
  - id: E2
    proves: [M4]
    kind: offline
    how: A check of the guide section's text order.
    intent: "Proves the guide gives the same order as the error message, so the two cannot send you different ways."
interface:
  - scripts/lib/hermes/prior_art.py api_key() raising EmbeddingsUnavailable
  - docs/guides/vector-store.md section "Why item 3 denies a read, and what to do about it"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it, run its test, show it red, then restore the guard and
   show it green. List any `must_not` whose test stayed green with the guard broken.
3. Say "no read-only real-data run possible" and why: this spec forbids reading the real keychain.
4. List every place where you chose something the spec did not decide.

## Notes

- Intent approval words, operator, 2026-11-08: "approve both E1 and E2".
- `find-similar-docs` also needs the hub kube context, a separate limit this spec does not change.
