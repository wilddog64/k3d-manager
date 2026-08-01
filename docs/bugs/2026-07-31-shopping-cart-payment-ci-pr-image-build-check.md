# Bugfix: shopping-cart-payment — validate the Docker image build on PRs (close the #28 CI gap)

**Repo:** `shopping-cart-payment`
**Branch (create off `origin/main`):** `fix/ci-pr-image-build-check`
**Files:** `.github/workflows/ci.yaml` (add one job; no other file)

---

## Problem

PR #28 bumped the Java `Dockerfile` base image `eclipse-temurin:21`→`25`, which broke
`main`'s image build (JDK 25 + Spring Boot 3.2.0-managed Lombok 1.18.30 →
`mvn package` `cannot find symbol`). It merged **green** and only failed after merge.

**Root cause of the gap:** the only job that builds the Docker image —
`publish` / `Build, Scan & Push` — is gated:

```yaml
# .github/workflows/ci.yaml (publish job)
if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```

So it runs **only on push to `main`**, never on PRs. The required PR checks
(`Build and Test`, `Checkstyle & SpotBugs`, `Integration Tests`, `Security Scan`)
all compile on the runner's **JDK 21** (`env.JAVA_VERSION: '21'`) and never touch the
`Dockerfile`. A base-image/JDK bump therefore cannot be validated before merge — it
compiles fine on JDK 21, merges, and breaks the image build on `main`.

**Fix:** add a PR-triggered job that **builds the Docker image without pushing**, so the
`Dockerfile` (and its base images) are exercised pre-merge. Build the full image (both
stages) so both the builder JDK and the runtime JRE base are validated.

---

## Reproduction

Open a PR that changes `Dockerfile`'s `FROM` base image to an incompatible tag.
Today: all required checks pass and the PR is mergeable. Desired after this fix:
the new `Image Build Check` job runs the `docker build` and fails the PR.

---

## Fix

Add ONE new job to `.github/workflows/ci.yaml`. Insert it as a new top-level job
under `jobs:` — recommended placement is **after the `security-scan` job and before the
`publish` job** (line ~165, between the end of `security-scan:` and `  publish:`).

### New job (exact block to add — mind the 2-space job indentation)

```yaml
  image-build-check:
    name: Image Build Check
    needs: [build]
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build image (no push)
        uses: docker/build-push-action@v6
        with:
          context: .
          file: ./Dockerfile
          push: false
          secrets: |
            GH_TOKEN=${{ secrets.PACKAGES_TOKEN }}
```

Notes on the block:
- `push: false` — build only, never publish. No `packages: write` permission needed.
- `if: github.event_name == 'pull_request'` — PR-only; push-to-main already builds via
  the real `publish` job, so this avoids a duplicate build there.
- `secrets: GH_TOKEN=...` — the `Dockerfile` builder stage runs
  `RUN --mount=type=secret,id=GH_TOKEN mvn package` to pull the private
  `rabbitmq-client-java` package from GHCR. The secret **id must be `GH_TOKEN`** to match
  the `Dockerfile`; the value comes from `secrets.PACKAGES_TOKEN` (same source the
  reusable `publish` workflow uses).

---

## ⚠️ Hard prerequisite — Dependabot secrets (owner action, NOT Codex)

The incident PR (#28) was a **Dependabot** PR. Dependabot PRs run in a restricted context
and **do NOT receive repository Actions secrets** — only secrets in the separate
**Dependabot secrets** store. So on the exact PRs this check is meant to catch (base-image
bumps, which Dependabot raises), `secrets.PACKAGES_TOKEN` will be **empty** unless
`PACKAGES_TOKEN` is added under **Settings → Secrets and variables → Dependabot**.

This is the **same token** already flagged as the fix for the rabbitmq-401 issue. Until it
is present in the Dependabot store, `image-build-check` will fail on Dependabot PRs at
`mvn package` (cannot resolve the private dependency) — a false failure. Add the Dependabot
secret as part of shipping this.

## Making it required (owner action, NOT Codex)

A non-required check does not block merge. After the workflow lands and the job is
observed green on a normal PR, add it to branch protection:

```bash
gh api repos/wilddog64/shopping-cart-payment/branches/main/protection/required_status_checks/contexts \
  -X POST -f 'contexts[]=Image Build Check'
```

---

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/ci.yaml` | add one `image-build-check` job (PR-only, `docker build` with `push: false`) |

---

## Rules

- Change ONLY `.github/workflows/ci.yaml`. No `Dockerfile`, no `pom.xml`, no other file.
- Pin all actions to a version tag (`@v3`, `@v4`, `@v6`) — never `@main`/`@latest` (supply-chain rule).
- Match existing 2-space job indentation; keep the file valid YAML.
- Do NOT change the existing `publish` job's `if:` — the real push-time build stays as is.
- Note: the 4 open Dependabot GHA-major PRs also touch `ci.yaml` (`actions/cache`,
  `actions/upload-artifact`); if they merge first, `git pull --rebase origin main` before
  pushing — the changes are on different lines, so conflicts should be trivial.

---

## Definition of Done

- [ ] `.github/workflows/ci.yaml` has a new `image-build-check` job exactly as above
- [ ] `python -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/ci.yaml"))'` parses clean (or `yamllint`)
- [ ] The existing `publish` job is unchanged (`git diff` shows only the added job)
- [ ] `CHANGELOG.md` gets a one-line `### Added` entry for the PR image-build check
- [ ] Committed and pushed to `fix/ci-pr-image-build-check`
- [ ] memory-bank updated with the commit SHA and task status

**Note on verification:** on a *normal* (non-Dependabot) PR the job should build and pass
(it has `PACKAGES_TOKEN`). Report the job green on the PR. The owner adds the Dependabot
secret + required-check afterward (see the two owner-action sections above).

**Commit message (exact):**
```
ci: build Docker image on PRs (no push) to catch base-image/JDK breaks pre-merge
```

---

## What NOT to Do

- Do NOT create the PR — Claude runs `/create-pr`. Push the branch only.
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify `Dockerfile`, `pom.xml`, the `publish` job, or any file other than `ci.yaml` + `CHANGELOG.md`
- Do NOT add `push: true` or any registry-push step — this check must never publish an image
- Do NOT commit to `main` — work on `fix/ci-pr-image-build-check`
