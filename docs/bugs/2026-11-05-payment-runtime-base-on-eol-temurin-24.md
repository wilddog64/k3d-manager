# Bug: payment's runtime base moved to eclipse-temurin:24-jre-alpine, a frozen non-LTS tag on alpine 3.22.1, so each new build has more CRITICAL CVEs than the deployed one

**Status:** VERIFIED — restated 2026-11-07 by Claude, verification already recorded below; was: FIXED, verified offline and by scan. Fix merged to `main` as `c08870a0` (PR wilddog64/shopping-cart-payment#100). E1, E2 and E3 pass; independent verify PASS 2026-11-06. The image reaches the cluster through the CVE loop, once the tag-pagination fix is deployed by `make platform-ops`.
**Priority:** P2
**Severity:** medium. If the newest payment image were promoted, it would replace one CRITICAL OS finding with five. Today the CVE loop cannot promote it (see the tag-pagination bug), so nothing bad has shipped yet. Once that bug is fixed, the loop would promote this image.
**Filed:** 2026-11-05
**Detected by:** Claude, investigating the hub alert `CriticalCVEFixAvailableNotRemediated` (operator report, 2026-11-05)
**Branch:** `k3d-manager-v1.43.14` (tracking only)
**Approval:** operator, 2026-11-05: "go ahead to dispatch those two P2 bugs". Claude picked A + B, with Java 21 (the builder stage and `pom.xml` `<java.version>` are both 21).
**Related:** `docs/bugs/2026-11-05-app-cve-scan-reads-only-first-ghcr-tag-page.md` (land this fix before or with that one); `docs/bugs/2026-10-31-cve-rebuild-cannot-fix-base-or-library-cves.md`

## Evidence

The Trivy scans ran on the M4 on 2026-11-06 with `--pkg-types os --severity CRITICAL` and the same Trivy DB:

| Image | Base | CRITICAL OS findings |
|---|---|---|
| Deployed on Hostinger, `sha256:b3fb4b07…` | alpine 3.24.2 | CVE-2026-111497 (brotli-libs 1.2.0-r1) |
| GHCR `latest` = `sha-d5048735…`, `sha256:6dd2e6ee…`, built 2026-11-05 from the dependabot spring-boot bump | alpine 3.22.1 | CVE-2026-33845, CVE-2026-42010 (gnutls 3.8.8-r0); CVE-2026-31789 (openssl, libssl3, libcrypto3 3.5.1-r0) |

- In payment `Dockerfile`, the runtime stage is `FROM eclipse-temurin:24-jre-alpine`. It was bumped from `21-jre-alpine` by dependabot in `dc54bbb4` (2026-10-27).
- Java 24 is a non-LTS release that is out of support. Its alpine image no longer gets rebuilds, and CI run 41957536745 resolved it to `@sha256:4044b6c8…` on alpine 3.22.1.
- The runtime stage has no `apk upgrade`.
- Inferred, not proven: the deployed image predates the bump (21-jre on a current alpine). I did not check this against its image config.

## Fix

- **A.** The runtime stage goes back to `FROM eclipse-temurin:21-jre-alpine AS runtime`, to match the builder (`21-jdk-alpine`) and `pom.xml` (`<java.version>21</java.version>`). In `.github/dependabot.yml`, the `docker` entry gets `ignore: [{dependency-name: "eclipse-temurin", update-types: ["version-update:semver-major"]}]`, so a Java major bump is always a deliberate manual change.
- **B.** Add `RUN apk upgrade --no-cache` as the first `RUN` in the runtime stage, before `addgroup`. An image rebuilt from a stale base then still picks up the current alpine fixes. This is part of the 2026-10-31 base-CVE bug's intent.

Out of scope: `go/Dockerfile` (the Go rewrite), the builder stage, `k8s/`, and CI workflows.

Work in a branch, `fix/runtime-lts-base`, and open no PR. Claude reviews it and opens the PR after the operator's go.

## Files

- `Dockerfile`
- `.github/dependabot.yml`

## Acceptance

```yaml
must:
  - id: M1
    text: "A payment build from main produces an image whose OS has no CRITICAL finding that the currently deployed image lacks."
must_not:
  - id: N1
    text: "The runtime FROM line never names a non-LTS or end-of-life eclipse-temurin major."
evidence:
  - {id: E1, proves: [M1], kind: live, text: "Claude: trivy image --pkg-types os --severity CRITICAL on the new sha-* digest and on the deployed digest, same DB, compared."}
  - {id: E2, proves: [N1], kind: offline, text: "Static check of the payment Dockerfile runtime FROM line (21-jre-alpine), the apk upgrade line in the runtime stage, and the dependabot ignore rule (python yaml parse). Red on origin/main 70aea7d."}
  - {id: E3, proves: [M1], kind: offline, text: "docker build of the branch succeeds locally (or in the PR's CI); the built image's /etc/alpine-release is 3.24 or newer."}
interface:
  - "wilddog64/shopping-cart-payment Dockerfile and .github/dependabot.yml"
```

## PR #100 checks (Claude, 2026-11-06)

- `gh pr checks 100`: every check passes, including Image Build Check (run 42154175281, job 127685008246). Build, Scan & Push is skipped on a PR, as expected.
- Copilot: one COMMENTED review, "No open issues", no inline comments. Its note says it could not run at the selected tier, so this is a light review.
- **E3:** the job built the image with runtime `FROM eclipse-temurin:21-jre-alpine@sha256:ac05c3c42b7c…` and ran `RUN apk upgrade --no-cache && addgroup …`. On the M4, `docker run --rm --entrypoint cat <that digest> /etc/alpine-release` gives `3.24.4`. The built image is that base plus `apk upgrade`, so it is 3.24 or newer. The PR job does not push an image, so this checks the base digest, not the built image's own file.

## E1 and independent verification (2026-11-06)

Claude scanned first; a separately tasked verifier (`claude-sonnet-5-5`) repeated it from the Acceptance section only. Trivy 0.76.1, DB 2026-11-05 19:01:45 UTC, all scans on the same DB, `--pkg-types os --severity CRITICAL --platform linux/amd64 --image-src remote`, all rc 0.

| Image | OS | CRITICAL | New minus deployed |
|---|---|---|---|
| Deployed `sha256:b3fb4b07…` | alpine 3.24.2 | CVE-2026-111497 (brotli-libs 1.2.0-r1, fixed 1.2.1-r0) | n/a |
| Fix `sha-c08870a0` `sha256:28a81600…` | alpine 3.24.4 | none | empty, rc 0 |
| Newest `sha-321b7652` `sha256:34497a00…` | alpine 3.24.4 | none | empty, rc 0 |
| Pre-fix control `sha-d5048735` `sha256:6dd2e6ee…` | alpine 3.22.1 | includes the three at right | CVE-2026-31789, CVE-2026-33845, CVE-2026-42010, rc 1 |

CI: run 42157751676, success, headSha `c08870a0`, `build-push` success. Scan validity checked: OS metadata populated, os-pkgs target present, arch amd64 matching node `srv1754834`, digests match. Recorded with `bin/k3dm-codex-dispatch verify` from the verifier's evidence file.

Errors seen: the `_smartcd` shell hook on every call (the verifier's first outputs landed in the repo root because `cd` did not apply; moved out, `git status` clean); two of the verifier's own shell mistakes, rerun; Trivy's vendor-severity warning and update notice. None affects the comparison.

## Note 2026-11-06, alert still firing

`CriticalCVEFixAvailableNotRemediated` for `wilddog64/shopping-cart-payment`, `CVE-2026-111497`, has fired since 2026-11-02T18:23Z on the M5 hub. The running `payment-service` image is `sha256:b3fb4b07...1e38`. Whether that digest carries `c08870a0` was not checked. This alert is the live signal for the image reaching the cluster: it should clear once the CVE loop rolls the fixed image out. No new bug filed.
