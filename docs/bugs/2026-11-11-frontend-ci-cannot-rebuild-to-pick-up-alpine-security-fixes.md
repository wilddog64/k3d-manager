# shopping-cart-frontend CI cannot rebuild to pick up Alpine security fixes

**Status:** LANDED 2026-11-11 on shopping-cart-frontend `fix/ci-rebuild-alpine-fixes` (`34cfac9`; not yet on main) — found 2026-11-11 by Claude during the operator-approved manual rebuild for CVE-2026-9947 / CVE-2026-87636 (libxslt)
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-11
**Severity:** medium — a fixed Alpine package cannot reach the live frontend without a code commit, so a CVSS 9.6 libxslt fix sits published but unshipped
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Prior art:** docs/bugs/2026-11-11-app-cve-scan-ignores-unknown-severity-the-alert-counts.md (not scored; vector store unavailable) — read, related: that bug is the k3d-manager alert side, this one is the frontend repo's build side
**Repo:** wilddog64/shopping-cart-frontend (`.github/workflows/ci.yml`, `Dockerfile`)
**Approval:** operator, 2026-11-11 ("first trigger a plain rerun to see what happen. depending on that to write a spec and dispatch to Luna")
**Intent approved:** operator, 2026-11-11

## What happened (Claude, 2026-11-11)

- Live Hostinger frontend: `ghcr.io/wilddog64/shopping-cart-frontend@sha256:14bf71a5…` (`sha-54998781`, built 2026-11-10 by run 42749861025), which carries libxslt `1.1.43-r3`. Alpine v3.24 publishes `1.1.43-r4` (pkgs.alpinelinux.org, read 2026-11-11).
- `gh workflow run ci.yml --ref main` → run **43020700531**: every check passed and **`Build, Scan, Push & Deploy` was skipped**. Its condition is
  `if: github.ref == 'refs/heads/main' && github.event_name == 'push' && !startsWith(github.event.head_commit.message, 'ci(deploy):')`
  so a manual dispatch cannot publish an image.
- Even a push-triggered build would likely ship `-r3` again. The push step uses `cache-from: type=gha`, and the runtime stage's `RUN apk upgrade --no-cache` (Dockerfile, after `FROM nginx:1.31-alpine`) has the same instruction text and parent each time. BuildKit reuses the cached layer until the base digest moves.

## Fix (in shopping-cart-frontend)

1. `Build, Scan, Push & Deploy` also runs for `workflow_dispatch` on `refs/heads/main`. Keep the `ci(deploy):` loop guard for push events (`head_commit` is null on dispatch).
2. The runtime stage's `apk upgrade` layer is rebuilt on every image build: declare `ARG APK_UPGRADE_EPOCH` immediately before `RUN apk upgrade --no-cache` and pass `APK_UPGRADE_EPOCH=${{ github.run_id }}` in the push step's `build-args` (and in the PR `Docker Build` step, so it is exercised). Builder-stage caching (npm) stays.
3. No change to the Trivy severity gate here. Whether CI should fail on `UNKNOWN` is an operator decision recorded in the app-cve-scan bug.

Out of scope: run 42749861025's deploy-step failure (`k8s/base/kustomization.yaml was not updated to newTag: sha-…`). Separate defect, to be filed after this lands.

## Files

| File | Change |
|---|---|
| `.github/workflows/ci.yml` | push job also on `workflow_dispatch` from main; `APK_UPGRADE_EPOCH=${{ github.run_id }}` in both build steps |
| `Dockerfile` | `ARG APK_UPGRADE_EPOCH` directly above the runtime-stage `RUN apk upgrade --no-cache` |
| `tests/ci/` (new, or the repo's existing test location) | E1 and E2 offline tests (Python or BATS reading the YAML and Dockerfile) |

## Worker definition of done

- Work in `wilddog64/shopping-cart-frontend` only, on a branch from `main`; change only the files above. Do not push or open a PR: Claude reviews, then opens the PR.
- E1 evaluates the `if:` expression with a small evaluator over the five event cases, not by grepping the string.
- Show every `must_not` test red against today's code, then green. Mutation-test each guard (break it, see the test fail, restore). Run the full touched suites, not only the new tests, and run the change once read-only against real data where the spec says how. Paste command, rc and the proving lines for each; list every error you saw, and any choice the spec left open. Leave changes uncommitted; Claude reviews and lands.

## Acceptance

```yaml
must:
  - id: M1
    text: a workflow_dispatch run on main builds, scans and pushes ghcr.io/wilddog64/shopping-cart-frontend:sha-<sha>
  - id: M2
    text: two image builds of the same commit run the runtime-stage apk upgrade both times (no cached layer for it)
must_not:
  - id: N1
    text: a push whose head commit message starts with "ci(deploy):" runs the push job
  - id: N2
    text: the push job runs for pull_request events or for refs other than main
evidence:
  - id: E1
    proves: [M1, N1, N2]
    kind: offline
    intent: "a test evaluates the push job's if-condition for push/main, dispatch/main, push with a ci(deploy): message, PR, and dispatch on a branch: only the first two run; the dispatch/main case fails on today's workflow"
  - id: E2
    proves: [M2]
    kind: offline
    intent: "a test reads the Dockerfile and workflow: the ARG sits directly above the runtime-stage apk upgrade, and both build steps pass it a per-run value; fails on today's files"
  - id: E3
    proves: [M1, M2]
    kind: live
    intent: "Claude dispatches CI on main after merge: the push job runs, its build log shows the apk upgrade step executing (not CACHED), and `apk info -v libxslt` in the new image prints 1.1.43-r4"
  - id: E4
    proves: [M1]
    kind: live
    intent: "the live Hostinger frontend deployment runs the new digest and the next app-cve-scan no longer reports CVE-2026-9947 for it"
interface:
  - .github/workflows/ci.yml (job "Build, Scan, Push & Deploy", step docker/build-push-action)
  - Dockerfile (runtime stage)
```

## External behaviour proof

- GitHub Actions skips the job on `workflow_dispatch`: run 43020700531 (2026-11-11 12:29Z, wilddog64/shopping-cart-frontend), job conclusion `skipped`.
- BuildKit cache invalidation by a changed `ARG` used by later instructions is documented Docker behaviour (Dockerfile reference, "Impact on build caching" under ARG). E3 is the live proof on this repo's builder.

## Contract readers

- `ghcr.io/wilddog64/shopping-cart-frontend:sha-*` / `:latest`: writer this job (gains dispatch-triggered writes); readers ArgoCD Image Updater / Hostinger frontend deployment (unchanged; they already follow new digests, as `sha-54998781` went live without its kustomization PR).
- `ci/frontend-image-sha-*` branches: writer the deploy step (unchanged; dispatch runs also create them).
- k3d-manager `app-cve-scan.sh` rebuild dispatcher (PR #135 `fix/cve-rebuild-dispatch` in this repo): to grep at dispatch whether it triggers `workflow_dispatch` and relied on the skip.

## Review notes (Claude, 2026-11-11)

- External behaviour proof: an `ARG` that the following `RUN` never references still busts that `RUN`'s cache. Probe on the M4, Docker 29.8.2 (OrbStack), 2026-11-11: `FROM alpine:3.22` / `ARG APK_UPGRADE_EPOCH` / `RUN date > /stamp`; epoch 1 twice gave the same image `sha256:4b3d2b2f…` (step `CACHED`), epoch 2 gave `sha256:e825bbfa…`.
- `tests/ci/test_ci_contract.py`: 2 of 3 red on pre-fix code (workflow_dispatch row, cache buster), all green after; the third is the `ci(deploy):` skip regression guard and passes both ways by design. Not yet wired into the frontend CI.
- Next: PR `fix/ci-rebuild-alpine-fixes` → main (needs the operator's go), then `gh workflow run` on main for E-live: image digest changes and the scanned image carries libxslt 1.1.43-r4.
