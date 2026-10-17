# Order-service Go rewrite omitted Dependabot coverage, leaving CVE rebuilds vulnerable

**Filed:** 2026-10-06
**Release:** v1.41.0
**Branch:** `k3d-manager-v1.41.0`
**Status:** REOPENED 2026-10-17 — remediation still not done; fix spec F1–F3 below
**Priority:** P2 — coverage is fixed, but no one has verified the vulnerable dependency is gone from the deployed image
**Component:** shopping-cart-order dependency updates / application CVE remediation chain
**Severity:** high — vulnerable application dependency remains pinned despite image rebuilds

## Symptom and evidence

The operator's Grafana report showed shopping-cart-order with `golang.org/x/text`
installed at `v0.37.0`, fixed at `v0.39.0`, severity HIGH. The screenshot is operator-provided
context; this session did not read the live cluster or obtain a CVE identifier.

At application commit `6386ed17ee26b7977e26189115b5eaf32dece592`, `go/go.mod` contained:

```go
golang.org/x/text v0.37.0 // indirect
```

`.github/dependabot.yml` covered only Maven `/`, Docker `/`, and GitHub Actions `/`.
It omitted `gomod /go` and `docker /go` even though `go/go.mod` and `go/Dockerfile` exist.

## Root cause and boundary

The Java-to-Go migration introduced a new dependency ecosystem and container directory
without updating Dependabot coverage. Rebuilding source that still pins the vulnerable module
cannot manufacture a fixed application binary. Dependency mutation belongs to the application
repository; clean-image selection and promotion are later stages.

This verifies the source-update coverage gap. It does not prove that every current promoter
failure has this cause, nor that Dependabot recognizes the reported advisory or can resolve a
compatible fixed version. No live scanner, alert, promoter, or rollout result was inspected.

## Fix already merged in the application repository

- [Application bug #81](https://github.com/wilddog64/shopping-cart-order/issues/81)
- [Application fix PR #82](https://github.com/wilddog64/shopping-cart-order/pull/82)
- Verified merge commit: `fc3fae5a24675b464c2c72ed27b747cc1ef74b86`.
- Added weekly `gomod /go` and `docker /go` entries.
- Added a CI guard comparing tracked Go, Maven, npm, Docker, and Actions dependencies with
  default-branch ecosystem/directory coverage, plus six regression cases.
- GitHub Java CI and Dependabot coverage workflow completed successfully on fix commit
  `e02eb783e5f3b7a4687a3af3029a2e264a3a465e`.

Validation output from the application fix session:

```text
......
----------------------------------------------------------------------
Ran 6 tests in 0.001s

OK
All tracked dependency manifests have Dependabot coverage.
Original configuration correctly fails for docker /go and gomod /go.
Changed YAML parses successfully.
```

## Follow-up / acceptance criteria

- [x] Restore Go and Go-container Dependabot coverage in shopping-cart-order.
- [x] Add a regression guard against future ecosystem/directory coverage gaps.
- [ ] Confirm dependency graph, Dependabot alerts, and security updates are enabled and produce
  a compatible fixed dependency PR; inspect indirect-module updates as well.
- [ ] Confirm Go CI passes for the actual dependency update and the merge publishes a new image.
- [ ] Confirm candidate scan and promotion select the fixed immutable digest.
- [ ] Confirm the running pod image ID and fresh Trivy report no longer show the finding.
- [ ] Consider applying the coverage guard to other shopping-cart repositories after auditing
  their actual manifests. No other application repos were changed in this task.

## Prior-art check and vector indexing

Exact-slug and repository text searches found no existing report for this coverage gap.
Similarity retrieval was attempted but unavailable in this cloud environment:

```text
find-similar-docs: retrieval unavailable — no embeddings credential. $K3DM_EMBEDDINGS_API_KEY is unset or empty; k3dm-embeddings-api-key: cannot run security (FileNotFoundError); gemini-cli-api-key: cannot run security (FileNotFoundError); hub Vault: cannot run kubectl: [Errno 2] No such file or directory: 'kubectl'
find-similar-docs: falling back to the exact-slug glob is still correct.
```

`scripts/index-docs.py` indexes tracked Markdown under `docs/bugs`, `docs/issues`,
`docs/plans`, and `docs/retro`. This report is eligible once the indexing checkout contains
this commit. Run the usual `make index-docs` on that checkout; live pgvector ingestion was
not attempted or verified here.

**Operational lesson:** language migrations must update dependency ecosystem and directory
coverage. A successful rebuild alone is not evidence that a source dependency CVE is fixed.

## Recurrence — 2026-10-17: the deployed order image still carries 7 Go HIGH CVEs

**Approval:** explicit 2026-10-17 "go ahead" (operator), on Claude's proposed `go get` PR.

Found while checking `make image-pin-drift`'s order `DRIFT` (see
`docs/bugs/2026-10-17-services-digest-pin-not-bumped-by-app-ci.md`). `trivy image --severity HIGH,CRITICAL`
on both the pinned order image (`sha-61568ccc`) and `:latest` (`sha-fc3fae5a`): 0 CRITICAL, the same 9 HIGH.
7 are in `/app/order-service`:

| Module | Installed | Fixed | CVE |
|---|---|---|---|
| `stdlib` | 1.25.14 | 1.26.9 / 1.27.2 | CVE-2026-78667, -78669, -97031 |
| `golang.org/x/crypto` | v0.52.0 | v0.55.0 | CVE-2026-56854 |
| `golang.org/x/net` | v0.55.0 | v0.60.0 | CVE-2026-46600, -78669 |
| `golang.org/x/text` | v0.37.0 | v0.39.0 | CVE-2026-56852 |

The other 2 are `musl` CVE-2026-40200 in `alpine:3.19`, covered by Dependabot PRs #90/#89 (`alpine:3.24`).

**Why the coverage fix did not close it.** `x/crypto`, `x/net` and `x/text` are `// indirect` in
`go/go.mod`, and Dependabot's `gomod` ecosystem opened no PR for them, so the second acceptance box above
never ticked. `stdlib` has Dependabot PR #92 (`golang:1.27-alpine`), unmerged.

**Ordering trap (same as `docs/plans/shopping-cart-go-builder-image-adoption.md`).** `x/net` v0.60.0
declares `go 1.26.0`. `go get` raises `go/go.mod` to `go 1.26.0`, and the builder `golang:1.25-alpine` runs
with `GOTOOLCHAIN=local`, so `docker build` would fail. The builder bump therefore lands in the **same** PR.
CI's `setup-go` reads `go-version-file: go/go.mod`, so it follows automatically. Dependabot then closes #92
as superseded.

## Fix — shopping-cart-order (separate repo; spec for Codex)

**Branch:** `fix/go-x-deps-cves`, from `origin/main` (`385c60b8`).

**F1.** In `go/`, run exactly:

```bash
go get golang.org/x/crypto@v0.55.0 golang.org/x/net@v0.60.0 golang.org/x/text@v0.39.0
go mod tidy
```

Expect `go.mod` to show those three versions and `go 1.26.0`, plus whatever transitive bumps `go get`
requires (e.g. `x/sys`). Do not hand-edit `go.mod` or `go.sum`, and do not bump any other module.

**F2.** In `go/Dockerfile`, line 2:

Old:
```dockerfile
FROM docker.io/library/golang:1.25-alpine AS builder
```
New:
```dockerfile
FROM docker.io/library/golang:1.27-alpine AS builder
```

Leave the runtime `alpine:3.19` line alone (that is PR #90's).

**F3.** In `CHANGELOG.md`, under `## [Unreleased]`, add a `### Security` entry (append to the existing
heading):

```markdown
- Bump the order service's indirect Go modules past their HIGH CVEs: `golang.org/x/crypto` v0.55.0
  (CVE-2026-56854), `golang.org/x/net` v0.60.0 (CVE-2026-46600, CVE-2026-78669) and `golang.org/x/text`
  v0.39.0 (CVE-2026-56852). They are `// indirect`, so Dependabot never proposed them. `x/net` v0.60.0
  needs Go 1.26, so the builder image moves to `golang:1.27-alpine` in the same change, which also clears
  three Go `stdlib` CVEs (CVE-2026-78667, -78669, -97031). Spec:
  `docs/bugs/2026-10-06-shopping-cart-order-go-dependabot-coverage-gap.md` (k3d-manager).
```

## Files

- `go/go.mod`, `go/go.sum`
- `go/Dockerfile`
- `CHANGELOG.md`

## Rules

Run from `go/` and paste the output of each:

- `test -z "$(gofmt -l .)"`
- `go vet ./...`
- `go test ./... -race -cover`
- From the repo root: `docker build -f go/Dockerfile go` (it must succeed; this is the check that catches
  the ordering trap). If Docker is not reachable from the sandbox, say so; do not skip silently.

## Definition of Done

- [ ] F1–F3 applied; the gates above pass (paste the output).
- [ ] `go list -m golang.org/x/crypto golang.org/x/net golang.org/x/text` shows v0.55.0, v0.60.0, v0.39.0.
- [ ] Commit message: `fix(deps): bump indirect x/crypto, x/net, x/text past HIGH CVEs; Go 1.27 builder`.

## What NOT to Do

- Do NOT create a PR, push, or commit to `main`. Claude commits, pushes and opens the PR; the operator merges.
- Do NOT skip hooks (`--no-verify`). Do NOT modify files outside `## Files`, including the Java tree
  (`pom.xml`, root `Dockerfile`), `go/Dockerfile.local`, and the runtime base image.
- Do NOT run the integration tests (`-tags integration`) or call any live service.

## Live proof

After the merge: CI publishes a new `sha-*` image; `make image-pin-drift` shows order `DRIFT` to it; a fresh
`trivy image` on it shows none of the 7 Go findings. Bumping the order pin then needs the operator's go
(it deploys to both clusters).
