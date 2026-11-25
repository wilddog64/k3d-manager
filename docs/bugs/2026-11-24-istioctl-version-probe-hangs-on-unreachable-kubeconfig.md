# Bug: the istioctl pin check hangs forever when KUBECONFIG names a missing or unreachable cluster (`make dr-drill` never ends)

**Status:** OPEN — spec rev 1, 2026-11-24
**Priority:** P1 (the v1.45.1 istioctl fix makes the DR drill hang instead of failing; E6/E7 of the istioctl bug cannot pass; blocks the v1.45.1 release PR)
**Triage:** patch → lib-foundation v0.5.10 + k3d-manager v1.45.1 subtree pull
**Branch:** lib-foundation `release/v0.5.10` (from main `083c249`); k3d-manager `k3d-manager-v1.45.1`
**Introduced by:** lib-foundation v0.5.8 (istioctl-a, `_istioctl_client_version` at `scripts/lib/core.sh:486`), carried by v0.5.9 and k3d-manager `7dc95697`
**Should have been caught by:** offline test (the `_write_existing` stub in `scripts/tests/lib/install_istioctl.bats:114-123` prints the version whatever its arguments, so a remote probe could never fail or hang)
**Introducing change reviewed:** yes (Fable)
**Waiting on:** fix running — since 2026-11-24
**Intent approved:** operator, 2026-11-24 ("go ahead to file a P1 bug and have Fable review then dispatch to Luna")
**Prior art:** `docs/bugs/2026-11-23-dr-drill-hub-up-istioctl-1-32-rejects-k3s-1-32.md` (exact topic; this is a defect in its fix) — appended as a follow-up of that bug, not a recurrence; `make find-similar-docs` not run (vector store not reachable from m4)
**Detected by:** operator + Claude, E6 run of `~/k3dm-e6e7.sh` on m2-air, 2026-11-24: the drill sat 1 h 47 min on `/opt/homebrew/bin/istioctl version --short` (process tree read by Claude over SSH)

## Evidence (m2-air, macOS, Homebrew istioctl 1.32.0, read-only, Claude, 2026-11-24)

- Hung process: `istioctl version --short`, parent `scripts/k3d-manager deploy_cluster --provider k3d dr-drill` (from `bin/hub-up`,
  from `bin/dr-drill`), elapsed 01:46:55, environment `KUBECONFIG=/Users/cliang/.k3dm/dr-drill/kubeconfig`. That file does not exist
  before the drill creates its cluster.
- `KUBECONFIG=~/.k3dm/dr-drill/kubeconfig timeout 25 istioctl version --short` → rc 124 after 25 s (still waiting).
- `KUBECONFIG=~/.k3dm/dr-drill/kubeconfig timeout 25 istioctl version --remote=false` → `client version: 1.32.0`, rc 0, 0 s.
- With m2's normal kubeconfig (reachable `k3d-k3d-cluster`) `istioctl version --short` answers in 0 s with three lines
  (`client version: 1.32.0`, `control plane version: 1.28.3`, `data plane version: …`), so the hang needs an unreachable cluster.
- `--remote=false` output on 1.31.4 (m4-air, m5-air) and 1.32.0 (m2-air), captured 2026-11-23/24: one line `client version: X.Y.Z`.

## Fix

lib-foundation `scripts/lib/core.sh` `_istioctl_client_version`: run `"$path" version --remote=false 2>/dev/null` once (no `--short`,
no fallback to a bare `version`, which is also a remote call). Parsing (first line, `^client version: X.Y.Z`) and every other
line of `core.sh` stay as they are. Then tag v0.5.10, and `git subtree pull` it into k3d-manager.

## Children

| Child | Repo / branch | Worker | Files | Depends on |
|---|---|---|---|---|
| A | lib-foundation `release/v0.5.10` | Luna | `scripts/lib/core.sh` (`_istioctl_client_version` only), `scripts/tests/lib/install_istioctl.bats`, `CHANGE.md` (v0.5.10 entry) | — |
| B | k3d-manager `k3d-manager-v1.45.1` | Claude | `scripts/lib/foundation/` via `git subtree pull --prefix scripts/lib/foundation <lib-foundation> v0.5.10 --squash`; `CHANGELOG.md` one line | A merged to lib-foundation main and tagged v0.5.10 (PR + Argon review, Copilot capped until 2026-12-01) |

Dispatch A: `bin/k3dm-codex-dispatch start --spec docs/bugs/2026-11-24-istioctl-version-probe-hangs-on-unreachable-kubeconfig.md --repo ~/src/gitrepo/personal/lib-foundation --branch release/v0.5.10 --agent codex --model gpt-6-luna --coordinator anthropic/claude-opus-5-5`

## Contract readers

`_istioctl_client_version` and `_ISTIOCTL_FOUND_VERSION` (grep `scripts/` in lib-foundation, 2026-11-24): writer
`core.sh:482-491`; readers `core.sh:569-570` (existing istioctl check) and `core.sh:589-590` (post-install check). No reader
outside `core.sh`; k3d-manager reaches it only through `_install_istioctl` (`scripts/lib/providers/k3d.sh:59,61,104`,
`scripts/lib/providers/k3s.sh:88`). The output contract (`unknown` or `X.Y.Z`) does not change.

## Acceptance

```yaml
must:
  - M1: _istioctl_client_version calls the istioctl at $path exactly once, with arguments exactly "version --remote=false".
  - M2: Parsing is unchanged: first stdout line "client version: 1.31.4" → 1.31.4; "client version: 1.32.0" → 1.32.0; the line only
        on stderr, or "1.32.0" alone → unknown.
  - M3: The existing install_istioctl.bats cases stay green.
must_not:
  - N1: Must not invoke istioctl version without --remote=false (no --short, no bare "version" fallback).
        Red today: the argument log shows "version --short" first.
  - N2: Must not block when the cluster is unreachable. A stub that sleeps 30 s unless its arguments include --remote=false
        (and prints the version only then) returns within 5 s with the right version.
        Red today: the current code waits the full sleep (the case fails its 5 s bound; run it under a 10 s timeout so the
        suite never hangs).
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "The pin check asks istioctl only for its own version, never the cluster's", command: "lib-foundation: bats scripts/tests/lib/install_istioctl.bats (new case: stub logs its argv to $BATS_TEST_TMPDIR/istioctl.args and prints the version only for --remote=false)", red_control: "fails on lib-foundation main@083c249: the log's first line is 'version --short'"}
  - {id: E2, proves: [N2, M2], kind: offline, intent: "The drill can no longer hang on the version check when its cluster does not exist yet", command: "same suite, new case: stub sleeps 30 unless --remote=false; the call runs under timeout 10 and must finish in under 5 s with version 1.32.0", red_control: "fails on main@083c249 (timeout reached, version not found in time); positive control: the same stub returns 1.32.0 at once when called by hand with --remote=false"}
  - {id: E3, proves: [M3], kind: offline, intent: "Nothing else about the pin check changes", command: "same suite, all existing cases", red_control: "not applicable (regression guard)"}
  - {id: E4, proves: [N2], kind: live, intent: "On the drill Mac, the drill gets past the istioctl check in seconds and refuses Homebrew's 1.32 (E6 of the istioctl bug)", command: "operator on m2-air after child B lands and m2 is at that commit: ~/k3dm-e6e7.sh; E6 PASS and E7 PASS", red_control: "the 2026-11-24 run above (hung 1 h 47 min)"}
interface:
  - "no interface change: _istioctl_client_version <path> still sets _ISTIOCTL_FOUND_VERSION to X.Y.Z or unknown"
```

## Test notes (child A)

- Extend `_write_existing` or add a sibling stub that logs `"$@"` to `$BATS_TEST_TMPDIR/istioctl.args`. Existing cases keep the
  version-printing behaviour for `version --remote=false`.
- Every stub output reproduces a capture above (host and date in a comment).
- The N2 case wraps the call in `timeout 10` (GNU coreutils on the Linux CI runner; on macOS use `gtimeout` when present, else
  `perl -e 'alarm 10; exec @ARGV'`) so a regression fails the case instead of hanging the suite.

## Worker definition of done

- Child A changes only its three files in lib-foundation. Offline only: no network, no real istioctl, scratch HOME.
- Show E1 and E2 red against `main@083c249` first, then green; the whole `install_istioctl.bats` stays green.
- Leave changes uncommitted; do not push.
