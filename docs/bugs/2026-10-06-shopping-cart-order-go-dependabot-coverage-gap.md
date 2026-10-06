# Order-service Go rewrite omitted Dependabot coverage, leaving CVE rebuilds vulnerable

**Filed:** 2026-10-06
**Release:** v1.41.0
**Branch:** `k3d-manager-v1.41.0`
**Status:** Application coverage FIXED; live dependency/image remediation NOT VERIFIED
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
