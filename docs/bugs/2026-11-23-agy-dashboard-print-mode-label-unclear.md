# Bug: agent dashboard mode labels are unclear and differ per agent ("print" for agy, "exec" for codex)

**Status:** LIVE-VERIFIED — operator screenshot 2026-11-24 (hub deploy/hub 5162281): "agy untracked by repo" legends read `<repo> headless` (dirused, k3d-manager, lib-foundation, other, shopping-cart-order, hoverfocus), no "print"; the other three panels carry the identical transform (live ConfigMap check, Claude, 2026-11-24). was: LANDED — `9f953c0b` on k3d-manager-v1.45.1 (2026-11-23), Sonnet acceptance verify pass; L1 config half PASS on deploy/hub 5162281 (live ConfigMap `monitoring/grafana-dashboard-agent-activity` equals the repo at 5162281e, four renameByRegex transforms present, old titles gone; Claude, kubectl read-only, 2026-11-24); was: OPEN
**Fix commit:** 9f953c0b
**Live evidence:** 2026-11-24 · run operator-screenshot-138 · env hub-deploy-hub · scenario agy-untracked-legend · commit 5162281e · proves fix
**Priority:** P3 — cosmetic; the operator had to ask what "print" meant
**Introduced by:** unknown (the agy mode split in `bin/k3dm-dispatch-metrics`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Triage:** patch → v1.45.1 (operator, 2026-11-23: "change print to headless session", then "or make them look the same", "consistency across vendor model")
**Intent approved:** operator, 2026-11-23
**Approval note:** "approve your intents", given after the E1, E2 and L1 intents for the cross-vendor version were shown
**Prior art:** Pass 1 `ls docs/bugs/*-agy-dashboard-print-mode-label-unclear.md`: none; `make find-similar-docs` not run; [`2026-11-21-agy-transcript-sessions-always-unknown-repo-and-mode.md`](2026-11-21-agy-transcript-sessions-always-unknown-repo-and-mode.md) (name grep) — read, different defect (repo/mode detection), same panels
**Filed:** 2026-11-23
**Detected by:** operator, 2026-11-23 (screenshot of "agy untracked by repo": "what does print mean?")

## What is wrong

`bin/k3dm-dispatch-metrics:2641` labels an agy session `mode="print"` when its id is not in agy's `history.jsonl`
(a headless `-p` run, for example an Argon review). Two panels in
`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` show that value raw through `{{mode}}`:
"agy sessions by mode" (legend `{{mode}}`, ~line 1065) and "agy untracked by repo" (legend `{{repo}} {{mode}}`,
~line 1116). "print" means nothing to a reader. The codex panels "Untracked by repo" (~line 464, legend `{{repo}} {{mode}}`) and
"Sessions by mode" (~line 520, legend `{{mode}}`) show the same kind of session as `exec` (`bin/k3dm-dispatch-metrics:680`),
so the two agents use different words for one thing. The titles differ too: the codex panels carry no vendor name
("Sessions by mode") while the agy ones do ("agy sessions by mode"). Only codex and agy emit a `mode` label
(`bin/k3dm-dispatch-metrics:2126-2157,2338-2659`); Claude and Copilot have no session-mode metrics, so they are out of scope.

## Fix

Display-only. In all four panels add a Grafana `renameByRegex` transformation with regex `^(.* )?(exec|print)$` and
renamePattern `$1headless`, so every panel uses the same three words: `headless`, `interactive`, `other` (legends read
`headless` / `k3d-manager headless`). Do **not** change the metric label values: `mode="print"` and `mode="exec"` are read
by `scripts/tests/bin/test_dispatch_metrics.py` and by Prometheus history, and changing them would split the series.

Titles follow one pattern, `<Vendor> sessions by mode` and `<Vendor> untracked by repo`: rename "Sessions by mode" to
"Codex sessions by mode" and "Untracked by repo" to "Codex untracked by repo" (the agy titles already fit). Add a short
"Session modes" glossary to `docs/guides/grafana-dashboards/k3dm-agent-activity.md`: `headless` (codex `exec`, agy `-p`
print runs), `interactive` (a session typed into), `other` (could not be classified), and that the raw metric values
stay `exec`/`print`.

## Contract readers

None change. The `mode` label values stay `print` (agy) and `exec` (codex); writers by grep:
`bin/k3dm-dispatch-metrics:680,2333,2641`; reader `scripts/tests/bin/test_dispatch_metrics.py`. Only the four panels'
display changes. Panel titles are a contract for one reader: `scripts/tests/plugins/agent_dispatch_dashboard.bats:1076`
looks up "Untracked by repo" by title and must follow the rename. No other test, script or guide names the four titles
(grep of `scripts/tests`, `bin`, `docs/guides`, `docs/howto`, fixtures excluded).

## Acceptance

```yaml
must:
  - id: M1
    text: the four mode panels ("Untracked by repo", "Sessions by mode", "agy sessions by mode", "agy untracked by repo") each carry a renameByRegex transformation mapping a display name ending in "exec" or "print" (whole word) to the same name ending in "headless"
  - id: M2
    text: '"interactive", "other" and repo prefixes pass through unchanged (e.g. "k3d-manager interactive" stays as is, "k3d-manager print" becomes "k3d-manager headless") (positive control)'
  - id: M3
    text: the panels' targets (expr, legendFormat) are unchanged, and no other panel gains or loses a transformation (scope control)
  - id: M4
    text: the four titles read "Codex sessions by mode", "Codex untracked by repo", "agy sessions by mode", "agy untracked by repo"; the existing bats check at agent_dispatch_dashboard.bats:1076 uses the new codex title and still passes
  - id: M5
    text: the agent-activity guide has a "Session modes" glossary defining headless, interactive and other for both codex and agy
must_not:
  - id: N1
    text: no mode panel may display the raw value "print" or "exec"
    red_on_current: none of the four panels has a transformation, so legends show "print" and "exec"
  - id: N2
    text: bin/k3dm-dispatch-metrics must not change (the mode label values stay print and exec)
    red_on_current: n/a (scope guard)
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    command: a new test in scripts/tests/plugins/agent_dispatch_dashboard.bats that parses the dashboard JSON and asserts, by panel title, the renameByRegex transformation on all four panels; asserts the four titles; applies each panel's regex and renamePattern (JS replace semantics, unmatched group = empty) to the sample names "print", "exec", "interactive", "other", "k3d-manager print", "k3d-manager exec", "k3d-manager interactive", "codexec" and checks the results; asserts expr and legendFormat unchanged and the count of panels with transformations is exactly four more than before; plus git diff showing bin/k3dm-dispatch-metrics untouched
    red_control: on the current dashboard the transformation assertions fail
    intent: Codex and agy panels use the same titles and the same words (headless, interactive, other), so the operator reads both vendors the same way without asking.
  - id: E2
    proves: [M5]
    kind: offline
    command: grep the guide for a "Session modes" heading and the words headless, interactive, other, exec and print under it; make test-pytest passes (doc-link checks)
    red_control: the current guide has no such heading
    intent: The guide explains what each mode word means for each vendor.
  - id: L1
    proves: [N1, M4]
    kind: live
    command: operator or Claude, read-only, after promote - open the Agent Activity dashboard and check the four titles and that all four mode panels' legends read "headless"
    red_control: a legend still showing "print" or "exec"
    intent: The live dashboard on the hub shows the new wording.
```

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` — add the transformation to the four mode panels
- `scripts/tests/plugins/agent_dispatch_dashboard.bats` — the E1 test, and the title key at ~line 1076
- `docs/guides/grafana-dashboards/k3dm-agent-activity.md` — the "Session modes" glossary

## Routing

Luna, one dashboard file, a test and a guide section. Shares no file with the running dispatches (argocd-alert-regex, totp-a2,
age-identity). Dispatch at the next free slot.
