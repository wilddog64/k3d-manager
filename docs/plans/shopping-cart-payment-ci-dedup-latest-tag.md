# Task: remove payment's duplicate inline image-build job so `latest` == `sha-<gitsha>`

**Repo (1):** `shopping-cart-payment`
**Work branch (create from `origin/main`):** `fix/ci-dedup-latest-tag`
**Spec repo/branch (where THIS file lives — pull it, do NOT commit to it):**
`k3d-manager` on `k3d-manager-v1.20.0`
**File to change:** `.github/workflows/ci.yaml`

This is a shopping-cart change handed off from k3d-manager. Get the spec from
k3d-manager; do the work in `shopping-cart-payment`.

---

## Problem being solved

The Hub `app-cve-scan` promoter looks for an immutable `sha-<gitsha>` tag whose
digest **equals** the `latest` tag's digest. For basket/order/product-catalog/
frontend this holds — their shared reusable workflow
(`shopping-cart-infra/build-push-deploy.yml`) does one multi-arch buildx push that
co-tags `latest` and `sha-<gitsha>` onto the same manifest.

**payment is the exception:** its `ci.yaml` runs the reusable workflow (`publish`
job) **and** a second, redundant inline job `docker-build` that *also* pushes
`latest` (plus a bare short-sha via `type=sha,prefix=` and a `main` tag via
`type=ref`). The two jobs race, and payment's `latest` ends up pointing at the
inline job's build while the immutable `sha-<gitsha>` tag comes from the reusable
workflow — so `latest` matches **no** `sha-*` tag and the promoter can never find a
candidate for payment.

**Live evidence (2026-07-31):** payment `latest` = `sha256:1af13828…`, and no
`sha-*` tag in ghcr shares that digest. basket/order/product-catalog/frontend each
DO have a matching `sha-*`.

**Fix:** delete the redundant inline `docker-build` job. The reusable `publish` job
already builds, scans, pushes multi-arch, and co-tags `latest` + `sha-<gitsha>` —
making it the single source of `latest`, which then matches `sha-<gitsha>` by digest.

---

## Before You Start

- Get the spec: in the `k3d-manager` repo, `git fetch origin && git checkout k3d-manager-v1.20.0 && git pull origin k3d-manager-v1.20.0`, then read this file.
- In `shopping-cart-payment`: `git fetch origin` then `git checkout -b fix/ci-dedup-latest-tag origin/main`.
- Confirm you are on `fix/ci-dedup-latest-tag` (NOT `main`) before editing.
- Read `.github/workflows/ci.yaml` in full first. Confirm the `docker-build` job is
  only defined, never referenced by another job's `needs:` (the `publish` job needs
  `[build]`, not `docker-build`).

---

## Fix — `.github/workflows/ci.yaml`: delete the `docker-build` job

Remove the entire `docker-build:` job. The `publish:` job immediately follows it and
must remain untouched.

**Exact old block:**

```yaml
          path: target/dependency-check-report.html

  docker-build:
    name: Build Docker Image
    runs-on: ubuntu-latest
    needs: [build, integration-test]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=
            type=ref,event=branch
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          platforms: linux/amd64,linux/arm64
          secrets: |
            GH_TOKEN=${{ secrets.PACKAGES_TOKEN }}

  publish:
```

**Exact new block:**

```yaml
          path: target/dependency-check-report.html

  publish:
```

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| `shopping-cart-payment` | `.github/workflows/ci.yaml` | delete redundant inline `docker-build` job; `latest` now published only by the reusable `publish` job, co-tagged with `sha-<gitsha>` |

---

## Rules

- Change ONLY `.github/workflows/ci.yaml`. Exactly **1 file** in `git show --stat`.
- Do NOT modify the `publish` job, the `build`/`integration-test`/`lint`/`security-scan`
  jobs, `release.yaml`, or any Dockerfile.
- Do NOT touch `go.mod` or the Go builder work on `chore/go-builder-image-1.26`.
- After the edit, the file must still parse as valid YAML and contain exactly these
  top-level jobs: `lint`, `build`, `integration-test`, `security-scan`, `publish`
  (i.e. `docker-build` is gone; nothing else added or removed).
- Gate: `grep -c 'docker-build:' .github/workflows/ci.yaml` → `0`.
- Gate: `grep -c 'type=raw,value=latest' .github/workflows/ci.yaml` → `0`.
- Gate: `grep -c 'publish:' .github/workflows/ci.yaml` → `1`.

---

## Definition of Done

- [ ] `docker-build` job removed; `security-scan` is followed by `publish`
- [ ] `.github/workflows/ci.yaml` still valid YAML; job list is `lint`, `build`, `integration-test`, `security-scan`, `publish`
- [ ] `git show <sha> --stat` shows exactly 1 file
- [ ] Committed and pushed to `fix/ci-dedup-latest-tag`
- [ ] Report the commit SHA back

**Commit message (exact):**
```
ci(payment): drop redundant docker-build job so latest matches sha-<gitsha>
```

---

## What NOT to Do

- Do NOT create a PR (Claude runs `/create-pr` after verifying the commit)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `.github/workflows/ci.yaml`
- Do NOT edit the reusable workflow in `shopping-cart-infra` — it is already correct
- Do NOT rebase, merge, or close any Dependabot PR
- Do NOT commit to `main` or to the k3d-manager spec branch — work on `fix/ci-dedup-latest-tag`

---

## Context (not part of the edit — for Claude, after this merges)

This fix only affects **future** payment builds. The existing divergent `latest`
persists until payment's CI runs again on `main` post-merge. After merge, trigger a
payment `main` build (or merge any payment PR) so the reusable workflow republishes
`latest` co-tagged with a fresh `sha-<gitsha>`; then the Hub `app-cve-scan` (with the
Accept-header fix from `docs/bugs/2026-07-31-app-cve-scan-multiarch-digest-accept-header.md`)
will resolve a candidate for payment. The Accept-header fix is the prerequisite that
unblocks the other four services regardless of this change.
