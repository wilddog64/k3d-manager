# Review: v1.46.0 istio appset stale-sandbox sweep (blind spec review)

**Filed:** 2026-11-27
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0`
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately

## Task

Review [`v1.46.0-istio-appset-stale-sandbox-sweep.md`](v1.46.0-istio-appset-stale-sandbox-sweep.md) against the code
on this branch. You get the spec and the repository, nothing else. Do not edit any file; write your review as your
final answer. No network calls; never read Keychain values or decode secret data; do not run kubectl or the cleanup
script against any cluster.

Answer:

- Safety: can the sweep ever select an object that targets Hostinger, the hub itself, or a server-URL destination?
  Check the matching rule (exact destination name, cluster name inside the secret compared base64-encoded, templated
  `{{...}}` destinations), the refused sandbox names, and the delete order. Is the positive control strong enough?
- Is deleting the `istio-ambient` ApplicationSet safe for Hostinger's running Istio (cascade, finalizers,
  `preserveResourcesOnDeletion`, owner references)? Cite the template and ArgoCD defaults the repo relies on.
- Webhook path: `/cleanup-stale-sandbox` timeout, dry-run default, exit codes; does moving the dry-run exit change
  existing behaviour or tests?
- Tests: is the kubectl stub design concrete; can each `must_not` fail as stated; are existing assertions untouched?
- Every cited file:line; anything missing from `## Files` or `## Contract readers`.

## Files

| File | Change |
|---|---|
| `docs/plans/v1.46.0-istio-appset-stale-sandbox-sweep.md` | read only (start here) |
| `bin/cleanup-stale-sandbox` | read only |
| `scripts/tests/bin/cleanup_stale_sandbox.bats` | read only |

## What NOT to Do

- Do not edit, create, stage or commit any file. Do not contact the hub or any cluster.

## Output

Findings most severe first, each tagged BLOCKER / MAJOR / MINOR with file:line evidence and a concrete fix, then a
verdict: READY, NEEDS FIXES, or REWRITE.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete fix; the review ends with a verdict
must_not:
  - id: N1
    text: the reviewer changes any file or makes a network call
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report has findings and a verdict
    intent: A second model checks the sandbox-sweep design before Luna builds it, so cleaning up a dead sandbox can never delete Hostinger's or the hub's own ArgoCD objects.
interface: none
```

**Intent approved:** operator, 2026-11-27
**Approval words and scope:** "can you start first group - 5 P2s (review by Fable/Neon)"
