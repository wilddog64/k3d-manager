# hub-deploy runs the hub checkout's old copy of itself, so a promote that changes the deploy path needs a second promote, and the operator's command differs between promotes

**Status:** VERIFIED — 3b541f3b, 2026-11-19 (offline E1); live E2 pending
**Priority:** P2 — a promote applies, but new deploy-path behaviour (Part 1 launchd reinstall) waits for a second run; workaround: wait for repo-sync (up to 5 min) and run `make hub-deploy REF=<sha>` again
**Introduced by:** pre-existing (design of `bin/k3dm-hub-deploy`, which runs from `$REPO_ROOT`, the hub checkout)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-19
**Triage:** operator, 2026-11-19: "go ahead to file a P2 bug then dispatch to Luna if there is a free slot"
**Spec:** `docs/plans/hub-deploy-self-update-one-command.md`
**Prior art:** `docs/bugs/2026-11-06-hub-code-lag-invisible-and-no-catch-up-step.md` (not scored: `make find-similar-docs` vector store unavailable on the M4) — read, related: that fix made lag visible and added catch-up steps, not a self-update of hub-deploy; `docs/bugs/2026-11-12-hub-checkout-stops-following-deploy-hub-and-promote-guard-fails-open.md` — read, different root cause
**Filed:** 2026-11-19

## Symptom

Operator, M5, 2026-11-19 ~16:06 PST: `make hub-deploy REF=364dce31` moved deploy/hub `072bcb5..364dce3` and printed
`appsets-check ok; platform-ops ok; exporter rolled out`. The hub checkout stayed at `072bcb57` (130 behind), so the
script that ran was the 072bcb57 copy of `bin/k3dm-hub-deploy` (0 `launchd` references; the 364dce31 copy has 25). No
`~/.local/share/k3d-manager/hub-deploy/` state directory was created and no plist was rewritten (Part 1 E9 cannot pass).
repo-sync moved the checkout at its next 5-minute run (`updated (130 behind before, 0 after)`, ~16:11).

Operator: "when can we have one command to promote REF? seems this time, commands you provide are different than last
couple times". The commands differed across promotes because each time the hub checkout lagged a different change
(see `memory: reference_hub_checkout_lags_new_make_targets`: `make promote` missing on 2026-11-11).

## Proposed change (for operator decision)

`make hub-deploy REF=<sha>` becomes the only promote command, run on the M5:
1. After moving deploy/hub, run repo-sync once for the hub checkout (under its lock) so the checkout is at deploy/hub.
2. If `bin/k3dm-hub-deploy` (or anything it sources) differs between the running copy and the new checkout, re-exec the new
   copy once with a guard variable, so the rest of the deploy (appsets-check, platform-ops, launchd reinstall) runs the
   promoted code.
3. Fetch origin itself first, so no `git fetch` step is needed.
