# Bug: payment's runtime base moved to eclipse-temurin:24-jre-alpine, a frozen non-LTS tag on alpine 3.22.1, so each new build has more CRITICAL CVEs than the deployed one

**Status:** OPEN. Filed 2026-11-05. Not dispatched. The fix is in `wilddog64/shopping-cart-payment`, not in this repo.
**Priority:** P2
**Severity:** medium. If the newest payment image were promoted, it would replace one CRITICAL OS finding with five. Today the CVE loop cannot promote it (see the tag-pagination bug), so nothing bad has shipped yet. Once that bug is fixed, the loop would promote this image.
**Filed:** 2026-11-05
**Detected by:** Claude, investigating the hub alert `CriticalCVEFixAvailableNotRemediated` (operator report, 2026-11-05)
**Branch:** `k3d-manager-v1.43.14` (tracking only)
**Approval:** pending
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

## Fix (proposal; the operator picks)

- **A (recommended).** Move the runtime to a maintained LTS tag (`eclipse-temurin:21-jre-alpine`, or `25-jre-alpine` if the app runs on 25), and keep it there. Add a dependabot `ignore` for non-LTS major versions of `eclipse-temurin`.
- **B (also).** Add `RUN apk upgrade --no-cache` in the runtime stage, so an image rebuilt from a stale base still picks up the current alpine fixes. This is part of the 2026-10-31 base-CVE bug's intent.

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
  - {id: E2, proves: [N1], kind: offline, text: "Static check of the payment Dockerfile runtime FROM line, and of the dependabot ignore rule."}
interface:
  - "wilddog64/shopping-cart-payment Dockerfile and .github/dependabot.yml"
```
