# PR #162 (v1.44.1) — blind Argon review findings

Copilot's monthly allowance is exhausted, so a blind Argon (`gemini-4-argon-medium`, read-only) review of the full code diff (`main...k3d-manager-v1.44.1`, docs and memory-bank excluded) stood in for the Copilot gate. Claude verified every finding against the code on 2026-11-17.

| # | Finding (Argon severity) | Verdict | Record |
|---|---|---|---|
| F1 | `bin/k3dm-hub-deploy` sub-makes inherit `REF`/`MAKEFLAGS` (medium) | Refuted: file unchanged in this PR; `appsets-check`, `appsets-reapply` and `platform-ops` neither read `REF` nor push | — |
| F2 | stall DB fallback uses the newest agy log on a resumed run (low) | Confirmed, P3 | `docs/bugs/2026-11-17-dispatch-stall-db-fallback-misses-resumed-agy-run.md` |
| F3a | doubled `''` in single-quoted flow values breaks parsing (low) | Refuted: parsed correctly | — |
| F3b | `intent: []` passes the spec-intent gate (low) | Confirmed, P3 | `docs/bugs/2026-11-17-spec-intent-accepts-empty-flow-collection-intent.md` |
| F4 | `VAULT_TOKEN` visible under xtrace in `bin/get-ldap-password` (medium) | Partly confirmed, pre-existing, P3: the assignment leaks, the here-string does not | `docs/bugs/2026-11-17-get-ldap-password-vault-token-assignment-visible-under-xtrace.md` |
| F5 | empty shard file makes the unseal filter hide all errors (low) | Confirmed, P3; the in-pod argv part is pre-existing | `docs/bugs/2026-11-17-unseal-watchdog-empty-shard-filter-hides-errors.md` |
| F6 | `hub_deploy.bats` outage pass-through test cannot fail (medium) | Refuted: by design the E10 pass-through guard of the containment spec, which says `k3dm-hub-deploy` needs no change | — |
| F7 | stall-watch E4 test does not assert which capture failed (low) | Confirmed, P3 (test strength) | `docs/bugs/2026-11-17-stall-watch-e4-test-does-not-assert-git-failure.md` |

**Gate result:** no P0/P1 finding; nothing blocks the merge. The five P3s are captured for triage.

**Process note:** three of seven findings were refuted on reading the code (one was a designed positive guard). Argon reviewed blind, without the specs, which explains F6.
