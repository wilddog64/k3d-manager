# Bug: `dispatch land` cannot land a third round of the same spec

**Status:** VERIFIED — `6d2dc472` (Luna; Claude reviewed), 2026-11-10. E1 red on pre-fix, green after; E2 unchanged; E3 live: `control-linux-vagrant-m4-r3` landed (`01985706`) naming both earlier rounds, rc 0 `landed:`
**Priority:** P2
**Introduced by:** `61256041` (v1.43.6, per-agent dispatch data)
**Should have been caught by:** offline test
**Prior art:** exact-slug glob: none. `make find-similar-docs` unavailable (vector store: context `k3d-k3d-cluster` does not exist on the M4, 2026-11-10)
**Severity:** a spec that needs two correction rounds cannot be landed through the ledger at all. It blocks
`control-linux-vagrant-m4-r3` (and with it control-node E2, E3 and the Hostinger E4). Workaround (costly, so P2 not P1): land
the commit by hand, which skips the ledger's land event that the metrics and the verification ladder read.
**Approval:** operator, 2026-11-10: "Dispatch tool fix first (Recommended)"
**Intent approved:** operator, 2026-11-10
**Intent approval words:** "Dispatch tool fix first (Recommended)" (option text: "You approve the P2's intents (E1-E3)")
**Filed:** 2026-11-10
**Detected by:** Claude, landing `control-linux-vagrant-m4-r3`, 2026-11-10
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, 2026-11-10, M4, `k3d-manager-v1.43.15` at `a21352d7`)

- `bin/k3dm-codex-dispatch:1039`: `--superseding` keeps one value (`superseding="$2"`; a second flag overwrites it).
- `:1094-1101`: for **every** prior landed run whose spec equals this one, `[[ "$superseding" == "$prior_slug" ]] ||
  _dispatch_error`. With two prior landed rounds, one value can never match both.
- Observed: `land --slug control-linux-vagrant-m4-r3 --superseding control-linux-vagrant-m4-r2` →
  `spec already landed by control-linux-vagrant-m4; use --superseding control-linux-vagrant-m4`; with
  `--superseding control-linux-vagrant-m4` → `spec already landed by control-linux-vagrant-m4-r2; use --superseding
  control-linux-vagrant-m4-r2`.
- The `landed` marker of r2 is empty: nothing records which slug a landing superseded, so the check cannot follow a
  chain.
- Tests: `scripts/tests/bin/codex_dispatch.bats:675` covers one prior round only.

## Fix

Accept `--superseding` more than once (collect into a list) and require every prior landed same-spec slug to be named
in it. Keep the refusal for any prior slug not named, so landing over a landed spec stays explicit. Update the error to
list every unnamed prior slug at once, and `docs/howto/codex-dispatch.md:259`.

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | repeatable `--superseding`; refusal lists every unnamed prior slug |
| `scripts/tests/bin/codex_dispatch.bats` | E1 and E2 tests |
| `docs/howto/codex-dispatch.md` | one sentence on repeats |

## Contract readers

- `--superseding` (CLI flag): writer the operator or Claude on `land`; reader only `bin/k3dm-codex-dispatch:1039,1099`.
  Not written to the ledger or the `landed` marker (`grep -n superseding bin/ scripts/lib/`, 2026-11-10), so no metric
  or dashboard reads it. Changes: accepts repeats; one value keeps working for a second round.
- `docs/howto/codex-dispatch.md:259`: documents the flag; gains one sentence on repeats.

## Acceptance

```yaml
must:
  - id: M1
    text: "A third same-spec round lands when --superseding names both earlier landed slugs."
  - id: M2
    text: "A second round still lands with a single --superseding naming the first (today's behaviour)."
must_not:
  - id: N1
    text: "A round never lands over a landed same-spec slug that no --superseding names; the refusal names every unnamed slug."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "You will see a bats test land a first and second round of one spec, then refuse a third round naming only one of them (listing the missing slug) and land it when both are named; against today's code the both-named case is refused."}
  - {id: E2, proves: [M2], kind: offline, intent: "You will see the existing single-superseding test pass unchanged."}
  - {id: E3, proves: [M1], kind: live, intent: "Claude lands control-linux-vagrant-m4-r3 naming both earlier rounds and sees 'landed:'."}
interface:
  - "bin/k3dm-codex-dispatch land --slug S --superseding P [--superseding P2 ...] (--test CMD|--no-test)"
```

## Worker definition of done

- Change only `bin/k3dm-codex-dispatch`, `scripts/tests/bin/codex_dispatch.bats` and `docs/howto/codex-dispatch.md`.
  Show E1's both-named case red against today's code, then green. Paste command, rc and proving lines. Leave changes
  uncommitted; Claude reviews and lands.
