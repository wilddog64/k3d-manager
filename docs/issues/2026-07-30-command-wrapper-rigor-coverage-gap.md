# Command Wrapper Rigor Coverage Gap

## What Was Investigated

The project convention prefers `_kubectl` or `_run_command` for host-side
shell execution. This investigation checked whether the committed rigor
protocol and pre-commit hook enforce that convention.

## Actual Output

```text
K3DM_ENABLE_AI=<unset>

--- total direct kubectl executable lines ---
81

--- direct kubectl executable lines by file ---
     39 scripts/plugins/shopping_cart.sh
      7 scripts/tests/run-cert-rotation-test.sh
      6 scripts/lib/providers/k3s-hostinger.sh
      4 scripts/plugins/vault.sh
      4 scripts/lib/providers/k3s-gcp.sh
      4 scripts/lib/providers/k3s-az.sh
      4 scripts/etc/ldap/ldap-password-rotator.sh
      3 scripts/plugins/copilot.sh
      3 scripts/plugins/argocd.sh
      2 scripts/lib/providers/k3s-aws.sh
      1 scripts/tests/plugins/openldap.sh
      1 scripts/plugins/jenkins.sh
      1 scripts/lib/providers/k3s-oci.sh
      1 scripts/lib/providers/k3s-oci-storage.sh
      1 scripts/lib/provider.sh

--- current audit run (empty staged diff) ---
running under bash version 5.3.15(1)-release
exit=0
```

`_agent_audit` only evaluates staged `.sh` changes. Its implemented checks
are BATS weakening, per-function `if` counts, bare `sudo`, tab indentation,
one `kubectl exec` credential pattern, and hard-coded IPs in YAML. It has no
check for direct `kubectl`, `helm`, `docker`, `curl`, or other process calls.
The BATS suite likewise has coverage for bare `sudo` and the credential
pattern, but no command-wrapper test.

The optional AI lint does not close this gap. The pre-commit hook runs it only
when `K3DM_ENABLE_AI=1`; it was unset during this investigation. More
importantly, `scripts/etc/agent/lint-rules.md` does not require `_kubectl` or
`_run_command`, so enabling it would not make the convention enforceable.

## Root Cause

The wrapper convention is guidance, not an executable rigor rule. Existing
violations also predate any future staged-diff check, so they would remain
invisible until their file was edited.

## Parser-Derived Baseline

On 2026-07-30, `shfmt --to-json` parsed every shell file found by
`shfmt -f scripts bin`, excluding the vendored foundation subtree and
third-party Playwright `node_modules`. There were no parser errors. The scan
counted raw `CallExpr` nodes for tools with a dedicated wrapper or that should
otherwise flow through `_run_command`: `kubectl`, `helm`, `curl`, `k3d`,
`docker`, `ssh`, and `wget`.

| Source class | Raw calls |
| --- | ---: |
| Host manager (`scripts/plugins`, `scripts/lib`, `bin`) | 410 |
| Tests | 27 |
| Container shell (`scripts/etc/argocd/platform-ops`) | 14 |
| Other standalone shell | 6 |
| **Total** | **457** |

The 410 host-manager candidates are `kubectl`=311, `curl`=73, `ssh`=15,
`docker`=6, `k3d`=4, and `helm`=1. The largest raw-`kubectl` concentrations
are `scripts/plugins/shopping_cart.sh`=66, `bin/cluster-up`=65,
`bin/cluster-status`=29, and `scripts/lib/providers/k3s-hostinger.sh`=24.

This is the actionable migration baseline, not a claim that all 457 calls are
defects. Tests and self-contained container scripts need explicit exceptions
or local adapters; the 410 host-manager calls are the candidates that violate
the proposed host wrapper convention.

Not every raw process call is a violation. Host-side manager shell code can
use `_kubectl`/`_run_command`; embedded CronJob scripts need a self-contained
adapter such as `_hub_kubectl`; and the Python webhook correctly uses its
timeout-aware `_spawn_capture_text` subprocess adapter. A blanket text
replacement would break those execution contexts.

## Recommended Follow-up

1. Write a narrowly scoped policy that defines the required wrapper per
   execution context: host Bash, standalone/container Bash, Python, tests,
   and remote SSH payloads.
2. Add a deterministic staged-diff checker for host Bash direct command
   invocations, with explicit allowlists for the defined exceptions. Add BATS
   tests for direct-call rejection, wrapper acceptance, and exception paths.
3. Create a baseline inventory and migrate host-side files incrementally,
   starting with `scripts/plugins/shopping_cart.sh`, rather than failing all
   existing files at once.
4. Keep the AI review optional and supplementary; it is not suitable as the
   only enforcement mechanism for an objective command-execution rule.
