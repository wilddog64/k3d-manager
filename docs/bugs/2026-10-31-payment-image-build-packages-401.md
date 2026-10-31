# Bug: payment image build gets 401 from GitHub Packages since 10-30, so CVE fixes cannot ship

**Status:** OPEN
**Priority:** P2
**Approval:** operator, 2026-10-31 (filing: "go ahead for 1 and 2"); fix pending
**Filed:** 2026-10-31
**Detected by:** Claude, answering the operator's "why these tables have no data" on the CVE autopatch
dashboard
**Affected:** `wilddog64/shopping-cart-payment` CI job `Build, Scan & Push / build-push`; secret
`PACKAGES_TOKEN`; `app-cve-scan` promotion for `shopping-cart-payment`
**Related:** `docs/bugs/2026-10-31-cve-rebuild-cannot-fix-base-or-library-cves.md`;
`docs/issues/2026-06-17-order-java-maven-verify-github-packages-401.md` (a local-only 401, not this);
memory note on the packages token (expiry ~2027-01-20, image build 401 on expiry)

## Observed failure

Every push to payment `main` since 2026-10-30 fails in the image build. Run for `dfa34be6`
(2026-10-30T10:41Z):

```
Could not transfer artifact com.shoppingcart:rabbitmq-client:pom:1.1.0 from/to github-rabbitmq-client
(https://maven.pkg.github.com/wilddog64/rabbitmq-client-java): status code: 401, reason phrase: Unauthorized
```

The package exists (versions 1.1.0, 1.0.2, 1.0.1). History of payment `main` CI:

| Commit | Date | Actor | Result |
|---|---|---|---|
| `79d4d9d4` | 10-23 | k3dm-dependabot-merger[bot] | success |
| `dc54bbb4`, `c26bd052` | 10-27 | wilddog64 | success |
| `dfa34be6` | 10-30 | k3dm-dependabot-merger[bot] | **failure** |

`dfa34be6` changed only `release.yaml` (docker/login-action 4.6.0 → 4.7.0), which is not the failing
workflow. A merger-bot run passed on 10-23, so the actor does not explain it. The Actions secret
`PACKAGES_TOKEN` was last set 10-22 and passed on 10-27. So the token stopped authenticating between
10-27 and 10-30: revoked, rotated elsewhere, or expired early. Not confirmed: Claude cannot read the
secret.

Effect: no new `sha-*` image exists, so the nightly `app-cve-scan` logs
`failed to resolve immutable sha-* candidate for ghcr.io/wilddog64/shopping-cart-payment; reason=no-match
— promotion skipped`. CVE-2026-111497 (brotli-libs, CRITICAL, fixed in 1.2.1-r0) stays open on payment.

## Fix

1. Operator: check the PAT behind `PACKAGES_TOKEN` (expiry, revocation, `read:packages` scope) and
   refresh the payment repo secret from Keychain. Check `shopping-cart-order` too, which reads the same
   package.
2. Claude: rerun payment `main` CI and confirm the image push.
3. Follow-up: the image build should fail with "PACKAGES_TOKEN rejected (401)" in one line, and an
   expiry check should alert before the token lapses.

## Acceptance

```yaml
must:
  M1: payment main CI pushes a new sha-* image
  M2: the next app-cve-scan resolves a payment candidate (reason=ok)
must_not:
  N1: no secret value appears in any log or doc while fixing
evidence:
  E1:
    proves: [M1]
    kind: live
    intent: >-
      You will see payment's main CI green and a new sha- image in GHCR. It failed if the build still
      says 401.
    what: gh run view on the rerun; gh api for the new package version
  E2:
    proves: [M2]
    kind: live
    intent: >-
      You will see k3dm_app_cve_candidate_resolution for payment say reason="ok" after the next nightly scan.
      It failed if it still says no-match.
    what: Pushgateway metric on the M5 hub, read-only
interface:
  - shopping-cart-payment CI (push to main)
  - k3dm_app_cve_candidate_resolution{service="shopping-cart-payment"}
```

**Intent approved:** pending
