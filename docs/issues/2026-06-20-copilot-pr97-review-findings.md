# Copilot PR #97 Review Findings

**Date:** 2026-06-20
**PR:** #97 — `feat(eso): app-cluster ESO operator generator + data-layer routing label`
**Reviewer:** Copilot (`copilot-pull-request-reviewer[bot]`) — 1 comment, state COMMENTED
**Outcome:** No code change — finding is informational; the fix targets the correct path.

---

## Finding 1 — `cluster-secret.yaml.tmpl` is not wired into the registration path

**File:** `scripts/etc/argocd/cluster-secret.yaml.tmpl:8`

**Copilot:** `cluster-secret.yaml.tmpl` is not referenced anywhere (no `envsubst`/`cat`/path
usage), and `register_app_cluster` in `scripts/plugins/argocd.sh` builds the cluster secret
via an inline heredoc. So adding the `k3d-manager/role: app-cluster` label to the template
won't affect the existing registration path unless `register_app_cluster` is updated to
include the label or to render this template.

### Verification

- **Template is dead config — confirmed.** `grep -rln cluster-secret.yaml.tmpl` across
  `*.sh`/`*.bats`/`Makefile` → **zero references**. The label added there (Fault B Change 2)
  is cosmetic / for future consistency only.
- **The actually-broken path *is* fixed.** The live failure was the Hostinger app-cluster
  secret missing the label. Hostinger registration is `_hostinger_register_cluster`
  (`scripts/lib/providers/k3s-hostinger.sh`), which builds its **own** heredoc and does
  **not** call `register_app_cluster`. Fault B Change 1 adds the label directly to that
  heredoc (`k3s-hostinger.sh:130`) — the effective fix.
- **The generic path is also covered.** `register_app_cluster` (`argocd.sh:1145`) does not
  carry the label in its heredoc, but it calls `_argocd_set_active_app_cluster`
  (`argocd.sh:1215`), which `kubectl label`s the active cluster secret
  `k3d-manager/role=app-cluster --overwrite` at runtime (and clears it from others). So that
  path applies the label too, just by a different mechanism.

**Net:** three label mechanisms exist (Hostinger heredoc — now fixed; generic
`register_app_cluster` runtime labeling via `_argocd_set_active_app_cluster`; and the dead
template). No registration path is left unlabeled. No change required.

### Process note

The dead `cluster-secret.yaml.tmpl` predates this PR. Future cleanup option: either wire it
into a generic registration path or delete it — out of scope here. Worth a follow-up if a
provider-agnostic registration is generalized (cf. Phase 2 Phase-3 note about extending
per-cluster auth beyond Hostinger).
