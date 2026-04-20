# Active Context — k3d-manager

## Current Branch: `recovery-v1.1.0-aws-first` (as of 2026-04-19)

**v1.1.0 recovery** — prior `k3d-manager-v1.1.0` accumulated "system mess" (Chrome-killing CDP launches, broken `gcp.sh` auto-restart, URL mismatch, identity seesaw). Cut fresh branch off `main`; AWS path functionally verified via `make up CLUSTER_PROVIDER=k3s-aws` on 2026-04-19 (3-node k3s Ready, `aws sts get-caller-identity` OK, shopping-cart pods mostly Healthy).

**Seed commit** `11da18d8` (Gemini, 2026-04-19): added `scripts/etc/playwright/vars.sh` + thin plan skeleton.

**Expanded specs (Claude, 2026-04-19):** 3 Codex-ready phase specs under `docs/bugs/v1.1.0-recovery-phase-{a,b,c}-*.md`. E2E-gated — one phase at a time.

### Phase status

| Phase | Status | Spec | Files | Commit msg |
|---|---|---|---|---|
| A — shared vars | **COMPLETE** (impl `3de58f4d`, memory-bank `349bddbf`, Gemini) | `docs/bugs/v1.1.0-recovery-phase-a-shared-vars.md` | `scripts/etc/playwright/vars.sh`, `scripts/plugins/acg.sh` | `fix(playwright): reconcile shared vars with existing auth dir` |
| B — robot engine | **COMPLETE** (impl `a986d5bb`, Gemini) | `docs/bugs/v1.1.0-recovery-phase-b-robot-engine.md` | `scripts/playwright/acg_credentials.js` | `fix(playwright): disconnect over CDP, provider flag, IPv4, patient sign-in` |
| C — gcp.sh | **HANDED OFF TO GEMINI** (2026-04-19) | `docs/bugs/v1.1.0-recovery-phase-c-gcp-identity.md` | `scripts/plugins/gcp.sh` (new) | `feat(gcp): add plugin with surgical latch-on identity pattern` |
| D — docs | queued | N/A | `README.md`, `docs/howto/*` | `docs: align README and guides with unified 127.0.0.1/vars.sh` |

Phase A notes: E2E A1/A2/A4 ✓. A3 shellcheck shows 5 pre-existing SC2034 warnings on constants (not new) — cleanup deferred to Phase B via `# shellcheck disable=SC2034` header on `vars.sh`.

### Side-finding (non-blocking for recovery work)

order-service pod on ubuntu-k3s sandbox in CrashLoopBackOff. Root cause: `RabbitMQHealthIndicator` NPE — stack trace names `rabbitmq-client-1.0.0-SNAPSHOT.jar` (**pre-fix** JAR). Fix already shipped in `rabbitmq-client 1.0.1` via shopping-cart-order PR #24 (2026-04-11). Pod is running a stale image. Issue filed: `wilddog64/shopping-cart-order#26` — effectively a deploy-staleness tracker; resolution is rebuild `:latest` + pod rollout, not code.
