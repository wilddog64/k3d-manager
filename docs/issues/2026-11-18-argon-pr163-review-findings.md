# PR #163 (v1.44.2) — blind Argon review findings

Copilot is capped until 2026-12-01, so a blind Argon (`gemini-4-argon-medium`, read-only) review of the code diff (`main...k3d-manager-v1.44.2`, docs and memory-bank excluded; spec `docs/plans/release-pr163-v1.44.2-review.md`) stood in for the Copilot gate. Claude verified every finding against the code on 2026-11-17/18.

| # | Finding (Argon severity) | Verdict | Record |
|---|---|---|---|
| 1 | `scripts/plugins/hub_data.sh` `_hub_data_repoint_vault`: shard values traced under `set -x` (medium) | Confirmed. Line 866 (Secret write) is new in this PR; 852 (shard load) and 861 (Keychain cache) were already on `main`. **Fixed in 8eeaaeb8**: the whole repoint body runs under `_no_trace`; test S2-6 runs it with `set -x` and the real `_no_trace` and was red before the fix | this file |
| 2 | `bin/k3dm-codex-dispatch:1011`: `scheme=branch` project gets the branch name as version (low) | Confirmed, latent, P3 | `docs/bugs/2026-11-18-codex-dispatch-branch-scheme-project-version-is-branch-name.md` |
| 3 | `_dispatch_status` second loop: running project task shows `state: unknown` (low) | Confirmed, P3 | `docs/bugs/2026-11-18-codex-dispatch-status-project-task-state-unknown.md` |
| 4 | `_dispatch_stalled` / stall-watch scan only the newest `v*` dir (low) | Confirmed, P3 | `docs/bugs/2026-11-18-dispatch-stall-scan-skips-project-version-dirs.md` |
| 5 | `_dispatch_resolve_version`: slug reused across projects resolves to the project (low) | Confirmed edge case, P3 | `docs/bugs/2026-11-18-codex-dispatch-resolve-version-slug-reused-across-projects.md` |
| 6 | `land` numstat compares against `$rel` in another repo (low) | Confirmed, pre-existing on `main`, P3 | `docs/bugs/2026-11-18-codex-dispatch-land-numstat-uses-k3d-manager-release-in-other-repo.md` |
| 7 | `open --count` counts a review child linked after start (low) | Duplicate | `docs/bugs/2026-11-17-open-count-ignores-linked-review-role.md` |
| 8 | Hermes `vault_seal` unknown when one pod lacks labels (low) | Confirmed, matches the H1 spec; single-pod hub, P3 | `docs/bugs/2026-11-18-hermes-vault-seal-unknown-when-one-pod-unlabelled.md` |
| 9 | Resolve during an approval re-sample skips withdrawal (low) | Confirmed, mostly pre-existing, P3 | `docs/bugs/2026-11-18-hermes-resolve-during-approval-resample-skips-withdraw.md` |

**Gate result:** one medium security finding, fixed in the PR. No P0/P1 remains; the seven P3s are captured for triage.

## Finding 1 — fix detail

Before: tracing stayed on through the shard loop, the `_vault_cache_unseal_keys` call (shards as arguments) and the
`printf '%s\n' "${shards[@]}" | jq … | _no_trace _kubectl …` pipeline. `_no_trace` only silences the wrapped command;
xtrace still prints the expanded `printf` arguments and every `shard=…` assignment.

After:

```bash
function _hub_data_repoint_vault() {
  _no_trace _hub_data_repoint_vault_untraced "$@"
}
```

Only the outer call (`_hub_data_repoint_vault ctx [dir]`) is traced, and it carries no secret.

**Root cause:** the security rule covers Vault tokens in arguments and logs, but specs for code that handles unseal
shards did not ask for an xtrace test; S2-3 checked kubectl argv and stderr, not the trace stream.

**Process note:** a spec that moves shards, tokens or keys through shell variables should carry a `set -x` trace test
(like S2-6) as a `must_not`, with the real `_no_trace` loaded — the bats suite stubs `_no_trace` as a pass-through,
which first made S2-6 fail even after the fix.

## Second review: blind Fable diff review (2026-11-18)

With Fable quota spare (operator: 64% of the weekly allowance left), three blind, read-only Fable reviews ran in parallel
on the same diff, split by area. Claude verified every finding against the code.

| Area | Finding | Verdict | Record |
|---|---|---|---|
| hub_data | Secret probe and write lacked `--no-exit`: a missing `vault-unseal` (or API error) exited recovery at step 6 with no message; S2-2/S2-5 stubs returned instead of exiting (medium) | Confirmed. **Fixed in 3609a2ad**: `--no-exit` on both; the S2 stub now exits like the real `_kubectl`; S2-2/S2-5 red before the fix | this file |
| hub_data | `key-threshold` recorded as the shard count (low) | Confirmed, no reader outside tests; init is 1/1 | — |
| hub_data | drill skips the Secret rewrite (low) | By design ("Drill branch unchanged") | — |
| hub_data | root token in `jq --arg` in `hub_recovery.sh:75` (low, pre-existing) | Confirmed, P3 | `docs/bugs/2026-11-18-hub-recovery-root-token-in-jq-argv.md` |
| dispatch | stall scan misses project dirs (high) | Same as Argon #4, P3 (latent for dirused) | Fable section in `docs/bugs/2026-11-18-dispatch-stall-scan-skips-project-version-dirs.md` |
| dispatch | project dir above the release hides k3d-manager tasks (high) | Confirmed, latent, P3 | `docs/bugs/2026-11-18-codex-dispatch-project-version-above-release-hides-k3d-manager-tasks.md` |
| dispatch | slug collision; `scheme=branch`; status `unknown` (medium) | Same as Argon #5, #2, #3 | Fable sections in those docs |
| dispatch | non-semver highest tag resets version to v0.0.1 (medium) | Confirmed, P3 | `docs/bugs/2026-11-18-codex-dispatch-non-semver-highest-tag-resets-project-version.md` |
| dispatch | bash 3.2 arithmetic (low) | Not a finding: script already needs bash 4 (`local -A` on `main`) | — |
| dispatch | `open`, `prune`, metrics, docs, test gaps (low) | Confirmed, P3 hygiene | `docs/bugs/2026-11-18-codex-dispatch-multi-project-low-findings.md` |
| webhook | `_kubectl_json` drops only `Warning: ` lines (medium) | Confirmed in code; hub behaviour unproven, P3 | `docs/bugs/2026-11-18-webhook-kubectl-json-filter-misses-klog-lines.md` |
| Hermes | r7 reads only the first `not synced` group; `<= 2` untested (medium/low) | Confirmed, P3 | `docs/bugs/2026-11-18-hermes-r7-reads-only-first-eso-not-synced-group.md` |
| Hermes | approve re-propose voids digest/expiry checks (medium, pre-existing) | Confirmed, P3 | `docs/bugs/2026-11-18-hermes-approve-repropose-voids-digest-and-expiry-checks.md` |
| Hermes | resolve during re-sample (low) | Same as Argon #9 | Fable section in that doc |
| Hermes | sealed card recommends r3/r4; Withdrawn lists unshown repairs (low) | Confirmed, P3 | `docs/bugs/2026-11-18-hermes-sealed-root-cause-card-recommends-other-repairs.md` |
| Hermes/webhook | any-sealed-pod rule; label-set disagreement (low) | Confirmed, single-replica hub | Fable section in `docs/bugs/2026-11-18-hermes-vault-seal-unknown-when-one-pod-unlabelled.md` |
| webhook | LLM call when the cluster is unreachable (low) | By design (spec: the diagnosis always sees the state lines) | — |

**Gate result after both reviews:** two medium defects fixed in the PR (8eeaaeb8, 3609a2ad); no P0/P1 open; the rest captured as P3.
