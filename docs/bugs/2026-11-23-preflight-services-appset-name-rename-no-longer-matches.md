# Bug: `cluster-preflight` no longer renames the services Applications (`sed` pattern matches a retired template line)

**Status:** OPEN
**Priority:** P3 — degraded preflight bookkeeping; production Applications are unaffected
**Introduced by:** `4c5d3556` (v1.16.0, services-git Application name became `'{{.name}}-{{.path.basename}}'`)
**Should have been caught by:** offline test (the render function is stubbed out in `cluster_preflight_pin_guard.bats:12`; nothing renders it)
**Introducing change reviewed:** unknown
**Waiting on:** fix running — since 2026-11-23 (R1 landed 5f7ef7be; services-git.yaml:51 still `'{{.name}}-{{.path.basename}}'`)
**Triage:** patch → v1.45.1 (operator, 2026-11-23)
**Intent approved:** operator, 2026-11-23
**Prior art:** Pass 1 `ls docs/bugs/*-preflight-services-appset-name-rename-no-longer-matches.md`: none; `make find-similar-docs` not run (vector store unavailable); [`v1.1.1-bugfix-preflight-cluster-name-label.md`](v1.1.1-bugfix-preflight-cluster-name-label.md) (name grep) — read, different defect in the same render family
**Filed:** 2026-11-23
**Detected by:** Claude, while writing the R1 spec, 2026-11-23

## What is wrong

- `bin/cluster-preflight:223` rewrites `^      name: '{{.path.basename}}'$` to `'<cluster>-preflight-{{.path.basename}}'`.
- The template line is now `      name: '{{.name}}-{{.path.basename}}'` (`scripts/etc/argocd/applicationsets/services-git.yaml:41`),
  so the `sed` expression matches nothing and the clone appset keeps the production name pattern. (Verified by reading
  both files, 2026-11-23; not run live.)
- Effect: the clone's service Applications are named `<cluster>-<service>`, not `<cluster>-preflight-<service>`. The wait
  loop's classifier (`bin/cluster-preflight:131`, `name.startswith(f"{cluster_name}-preflight-")`) does not count them,
  and the cleanup that deletes `*-preflight-*` names will not find them. Whether they collide with a production
  Application depends on the preflight cluster's name; not checked.

## Fix

Match the current line (`'{{.name}}-{{.path.basename}}'` → `'<cluster>-preflight-{{.path.basename}}'`) and make the render
fail if any expected `sed` substitution matched nothing (compare before/after, or `grep -q` the expected name in the
output), so the next template change cannot silently break it again. Add a test that renders the real template.

## Acceptance

```yaml
must:
  - id: M1
    text: _cluster_preflight_render_services_appset on the real services-git.yaml produces an Application name template of '<cluster>-preflight-{{.path.basename}}' and an appset name '<cluster>-preflight-services-git'
  - id: M2
    text: the render exits non-zero when the Application name line is not found (positive control for the guard)
must_not:
  - id: N1
    text: the rendered clone must not keep the production name template '{{.name}}-{{.path.basename}}'
    red_on_current: bin/cluster-preflight:223 matches the retired '{{.path.basename}}' line, so the production template survives
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    command: bats test sourcing bin/cluster-preflight's render function with envsubst available, rendering the repo template into BATS_TEST_TMPDIR; plus a case with a doctored template lacking the name line
    red_control: on current code the rendered file still contains name '{{.name}}-{{.path.basename}}'
    intent: A preflight run creates its own clearly-labelled copies of the shopping-cart apps, so the preflight waits for and cleans up the right apps and never touches production ones.
```

## Files

- `bin/cluster-preflight` — match the current Application name line in `_cluster_preflight_render_services_appset`; fail the render when an expected substitution matched nothing
- `scripts/tests/bin/cluster_preflight_render.bats` — new: E1 (real template render, doctored template without the name line)

## Routing

Luna (`bin/cluster-preflight` + one new bats file). **Waits for R1:** the `sed` target is a line in
`scripts/etc/argocd/applicationsets/services-git.yaml`, which R1's running dispatch owns; match the line R1 leaves.
The fix itself does not edit any R1 file.
