# Dispatch spec: improve k3s-aws SSH readiness failure diagnostics

**Purpose:** Implement the scoped offline fix for the reproduced ACG SSH readiness failure.
**Canonical bug:** `docs/bugs/2026-10-21-k3s-aws-ssh-readiness-timeout-hides-failure-cause.md`
**Observed live output:**

```text
WARN: [shopping_cart] ssh-keyscan ubuntu not ready after 120s — k3sup may prompt
ERROR: [shopping_cart] ubuntu@ubuntu did not answer SSH within 180s — node unresponsive; not starting k3sup
```

Implement the canonical bug's proposed source-level diagnostics and offline regression tests. Bound/redact SSH failure classification, calculate elapsed readiness time consistently with the configured deadline, preserve the `k3sup` fail-closed gate, and correct failure-analysis wording so it distinguishes observations from hypotheses. Include safe retry guidance that accounts for an existing CloudFormation stack. Do not claim the cause of the 2026-10-21 timeout; the stack was subsequently deleted and no SSH stderr, EC2 status checks, or console output was captured.

Do not provision, tear down, or query live AWS/EC2 resources. Do not deploy or perform live verification. The two ACG tasks (this diagnostics fix and `acg-observability-appset-teardown-fix`) will be independently tested/landed and then operator-live-verified together in one future successful ACG bring-up/teardown cycle.

## Files

- `scripts/plugins/shopping_cart.sh`
- `scripts/lib/providers/k3s-aws.sh`
- `bin/k3dm-webhook`
- `scripts/tests/plugins/shopping_cart.bats`
- `scripts/tests/bin/`
- `docs/howto/acg.md`
- `docs/bugs/2026-10-21-k3s-aws-ssh-readiness-timeout-hides-failure-cause.md`
- `docs/issues/2026-10-21-k3s-aws-ssh-readiness-dispatch-spec.md`
