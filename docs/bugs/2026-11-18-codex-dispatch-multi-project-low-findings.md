# codex-dispatch multi-project: low-severity hygiene findings (open, prune, metrics, docs)

**Status:** OPEN — captured 2026-11-18 from Fable's blind diff review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — hygiene
**Triage:** patch → v1.46.1 — triage 2026-11-25, operator ("go with your recommendation"); was: backlog — pull into a release that already touches `bin/k3dm-codex-dispatch` (operator, 2026-11-25); Argon blind classification, Claude verified
**Branch:** `k3d-manager-v1.46.1`
**Introduced by:** 6972d10a (codex-dispatch multi-project M1, k3d-manager-v1.44.2)
**Should have been caught by:** review
**Introducing change reviewed:** yes (Argon, missed)
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Collection of low-severity CLI, pruning, metrics, test, and documentation hygiene findings in multi-project dispatch.)
**Waiting on:** dispatch — since 2026-11-25
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-18

## Items (Fable, PR #163)

1. `open` (`bin/k3dm-codex-dispatch:1601`) hard-codes `/3`; `--project typo --count` prints `all 0/6` with rc 0 (name
   not checked against the registry); `K3DM_DISPATCH_WIP_GLOBAL=x` gives a Python `ValueError` traceback.
2. `:931` `paste -sd ' ,'` alternates delimiters, so the known-project list prints as `a b,c d`.
3. `prune` (`:1808`) checks `origin/k3d-manager-$version`, so project worktrees are always kept and accumulate.
4. `bin/k3dm-dispatch-metrics:1617` `_releases` counts `v0.0.x` as a k3d-manager release window; `:1307` builds a dead
   `k3d-manager-v0.0.x` spec URL.
5. `docs/howto/codex-dispatch.md:262` says the version comes "from the ledger"; it comes from `.run/project` files.
6. `_dispatch_intervention` (`:756`): `event_project` is not declared `local`.
7. Tests: no coverage of `verify`/`handoff` resolution for project tasks; P2 cannot fail on multi-digit sort or a
   non-semver tag.

Not a finding: `$((10#"${BASH_REMATCH[3]}" + 1))` fails under bash 3.2, but the script already needs bash 4+
(`local -A` on `main`).
