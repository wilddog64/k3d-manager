# Task: bump Go builder base image to 1.26 so x/crypto/x/net Dependabot PRs build

**Repos (2):** `shopping-cart-payment`, `shopping-cart-order`
**Work branch (create in BOTH repos, from `origin/main`):** `chore/go-builder-image-1.26`
**Spec repo/branch (where THIS file lives — pull it, do NOT commit to it):**
`k3d-manager` on `k3d-manager-v1.20.0`
**File to change (one per repo):** `go/Dockerfile`

This is a shopping-cart change handed off from k3d-manager. Get the spec from
k3d-manager; do ALL the work in the two shopping-cart repos.

---

## Problem being solved

The security-relevant Go Dependabot PRs fail CI and cannot merge:

- payment: #39 (`x/crypto 0.27→0.52`), #38 (`x/net 0.26→0.55`), #37 (`pgx 5.7→5.9`)
- order: #46 (`x/crypto`), #48 (`x/net`), #47 (`pgx`)

These bumps raise the module's `go` directive to `go 1.25.0`. The Docker build
stage pins an old Go and runs with `GOTOOLCHAIN=local`, so `go build` refuses to
proceed:

```
go: go.mod requires go >= 1.25.0 (running go 1.21.13; GOTOOLCHAIN=local)
#11 ERROR: process "/bin/sh -c CGO_ENABLED=0 ... go build ..." exit code: 1
```

The non-Docker CI jobs already read the version from `go.mod`
(`setup-go@v7` + `go-version-file: go/go.mod`) and pass; **only the Docker build
stage has a hardcoded `golang:1.21` builder.** Bumping that builder base image to
`1.26` (matching what `shopping-cart-basket` already uses) satisfies the `go >=
1.25.0` requirement. `main`'s own `go.mod` stays at `go 1.21`; a newer builder
compiles it fine — the fix is inert until a PR that raises the directive rebases
onto it.

---

## Before You Start

- Get the spec: in the `k3d-manager` repo, `git fetch origin && git checkout k3d-manager-v1.20.0 && git pull origin k3d-manager-v1.20.0`, then read this file.
- In EACH shopping-cart repo: `git fetch origin` then `git checkout -b chore/go-builder-image-1.26 origin/main`.
- Confirm you are on `chore/go-builder-image-1.26` (NOT `main`) in each repo before editing.

---

## Fix

### shopping-cart-payment — `go/Dockerfile`

**Exact old line (line 1):**

```dockerfile
FROM golang:1.21 AS build
```

**Exact new line:**

```dockerfile
FROM golang:1.26 AS build
```

### shopping-cart-order — `go/Dockerfile`

**Exact old line (line 2):**

```dockerfile
FROM docker.io/library/golang:1.21-alpine AS builder
```

**Exact new line:**

```dockerfile
FROM docker.io/library/golang:1.26-alpine AS builder
```

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| `shopping-cart-payment` | `go/Dockerfile` | builder base `golang:1.21` → `golang:1.26` |
| `shopping-cart-order` | `go/Dockerfile` | builder base `golang:1.21-alpine` → `golang:1.26-alpine` |

---

## Rules

- Change ONLY the single `FROM ... golang ...` builder line in each repo's `go/Dockerfile`.
- Do NOT edit `go.mod`, workflow files, or any other file. Exactly **1 file** per repo in `git show --stat`.
- Do NOT touch the Java Dockerfile or any `temurin` image — this is the Go build stage only.
- Keep the `AS build` / `AS builder` stage alias exactly as-is (only the version token changes).

---

## Definition of Done

- [ ] `shopping-cart-payment/go/Dockerfile` line 1 reads `FROM golang:1.26 AS build`
- [ ] `shopping-cart-order/go/Dockerfile` line 2 reads `FROM docker.io/library/golang:1.26-alpine AS builder`
- [ ] `git show <sha> --stat` shows exactly 1 file (`go/Dockerfile`) in each repo
- [ ] Committed and pushed to `chore/go-builder-image-1.26` in BOTH repos
- [ ] Report both commit SHAs back

**Commit message (exact, both repos):**
```
build(docker): bump Go builder image to 1.26 for x/crypto/x/net updates
```

---

## What NOT to Do

- Do NOT create a PR (Claude runs `/create-pr` after verifying your commits)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify `go.mod`, `.github/workflows/`, the Java Dockerfile, or any file other than `go/Dockerfile`
- Do NOT rebase, merge, or close any Dependabot PR — that is Claude's step after this lands on main
- Do NOT commit to `main` or to the k3d-manager spec branch — work on `chore/go-builder-image-1.26` in each shopping-cart repo

---

## Context (not part of the edit — for Claude, after this merges)

Once `chore/go-builder-image-1.26` merges to `main` in each repo, trigger
`@dependabot rebase` on the Go PRs (payment #39/#38/#37, order #46/#48/#47) so they
pick up the new builder and go green. `shopping-cart-basket` is handled separately:
merge its existing PR #30 (workflow/golangci/source modernization) first, then
rebase basket #28/#27/#24. The passing migration-major PRs (spring-boot, stripe,
temurin, gh-action majors) are independent owner-merge decisions.
