# Bugfix: shopping-cart-payment — Dockerfile build stage pins go1.21 but go.mod requires go1.25

**Repo:** `shopping-cart-payment`
**Branch (create off `origin/main`):** `fix/dockerfile-go125-build-stage`
**Files:** `go/Dockerfile`

---

## Problem

The `go` CI job (`.github/workflows/go-ci.yml`) fails at the final
`docker build -f Dockerfile .` step on `main` (and on any Go PR):

```
#11 [build 4/4] RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/payment-service ./cmd/server
#11 0.143 go: go.mod requires go >= 1.25.0 (running go 1.21.13; GOTOOLCHAIN=local)
#11 ERROR: process "/bin/sh -c CGO_ENABLED=0 ... go build ..." did not complete successfully: exit code: 1
```

**Root cause:** `go/go.mod` declares `go 1.25.0` (raised from `1.21` by the pgx
#37 and x/net #38 Dependabot bumps, which require a newer Go). The Dockerfile
build stage still pins `FROM golang:1.21 AS build`. With the default
`GOTOOLCHAIN=local`, the go1.21 toolchain refuses to build a module requiring
go >= 1.25.0. This defect was latent — it was masked by the earlier
golangci-lint v2.5.0 failure (which ran earlier in the same job) until that was
fixed in #43.

This break is on `main` now: PRs #37 and #38 merged over it because the `go`
check is not a required status check.

---

## Reproduction

On `origin/main`:

```
docker build -f go/Dockerfile go/
```

→ fails at `go build ./cmd/server` with `go.mod requires go >= 1.25.0 (running go 1.21.13)`.
Equivalently: re-run the `go` CI check on any Go PR → the `docker build` step fails.

---

## Fix

### Change 1 — `go/Dockerfile`: bump the build-stage base image to go1.25

**Exact old block (line 1):**

```dockerfile
FROM golang:1.21 AS build
```

**Exact new block:**

```dockerfile
FROM golang:1.25 AS build
```

The runtime stage (`gcr.io/distroless/static-debian12:nonroot`) is unaffected —
do not touch it.

---

## Files Changed

| File | Change |
|------|--------|
| `go/Dockerfile` | build-stage base image `golang:1.21` → `golang:1.25` to match `go/go.mod` go1.25.0 |

---

## Rules

- Change ONLY the build-stage `FROM` line. Do not touch the runtime stage,
  `WORKDIR`, `COPY`, `RUN`, `go.mod`, `go.sum`, or any other file.
- Keep the tag pinned to a minor version (`golang:1.25`) — do NOT use
  `golang:latest` (supply-chain rule). Match the existing `golang:1.21` style.
- If `golang:1.25` still reports a toolchain older than `go.mod`'s directive at
  build time, bump to the exact patch that satisfies it and record which tag you
  used.

---

## Definition of Done

- [ ] `go/Dockerfile` line 1 reads `FROM golang:1.25 AS build`
- [ ] `grep -c 'FROM golang:1.21' go/Dockerfile` → `0`
- [ ] The `go` CI check passes (push the branch — go-ci runs on push; confirm the
      `docker build` step and the whole `go` job are green)
- [ ] Committed and pushed to `fix/dockerfile-go125-build-stage`
- [ ] memory-bank updated with the commit SHA and task status

**Commit message (exact):**
```
fix(docker): bump Go build stage to golang:1.25 to match go.mod go1.25.0
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `go/Dockerfile`
- Do NOT change `go.mod`, `go.sum`, the go directive, or the runtime stage
- Do NOT commit to `main` — work on `fix/dockerfile-go125-build-stage`
