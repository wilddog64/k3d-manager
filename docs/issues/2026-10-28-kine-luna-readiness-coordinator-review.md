# Coordinator review of Luna Kine recovery-readiness task

## Dispatch and authorization

Operator explicitly requested Kine recurrence P2 dispatch to Luna while running
a new M4 test-all. Native task kine-recurrence-readiness-luna, GPT-6-Luna,
allowed exactly one offline report. Scope commit1c8dcfe3. Worker did not run
live Docker/Kubernetes/SSH/Keychain/Git-network/SQLite/Make recovery commands,
change production/runbook files, stage/commit, or authorize recovery.

## Independent review and rework

First draft correctly identified the transaction failure, unknown trigger,
backup/approval gaps and no automatic rollback. Coordinator requested rework
for stale runbook claims, missing concrete command/effect classification,
end-to-end DRY_RUN safety, and overstrong volume preservation language.

Source inspection confirms the historical runbook's not-built data recovery
claim conflicts with current hub-recover-all/hub_data_recover. Its older
make-up guidance conflicts with current routing to bin/hub-up. Make's general
KEEP_LOCAL/DELETE_HUB defaults are not proof of safe k3d teardown: bin/cluster-down
explicitly forces _keep_hub=0 for providerk3d. Luna correctly retained this
exception rather than assuming a generic Makecomment determined behavior.

The accepted revision distinguishes explicit leftover cleanup tested with
fakes from unproven survival through real k3d cluster deletion. It explains
why DRY_RUN=1 make hub-recover-all has no end-to-end guarantee: raw preflight
state/Git operations, approval and raw cleanup/restore calls remain; an
existing hub can cause conditional refusal after a nested dry-run but that
is not a generally safe preview. No such command was executed.

Report now includes proposed metadata/interactive/stateful/destructive command
classes and readiness matrix. Proposed runbook patch remains separate scope;
no upstream Kine fix, root trigger or permanent recovery is claimed.

## Coordinator local metadata sample

Read only the non-secret local export marker; actual output:

```json
{
  "path": "/Users/cliang/.k3dm/hub-data/last-success",
  "exists": true,
  "scope": "local timestamp only; not remote export integrity proof",
  "timestamp_utc": "2026-10-28T10:33:40+00:00",
  "age_seconds": 39602
}
```

This was supplied to Luna as preliminary coordinator evidence. It does not
verify the remote snapshot, manifest, decryptability, restore viability or
operator's accepted recovery point. All of those remain pending.

## Validation and landing proof

Independent command and actual output, exit0:

```text
python3 scripts/check-doc-links.py docs/issues/2026-10-28-hub-kine-recurrence-luna-review.md
check-doc-links: 1 file(s) OK
```

Staged _agent_lint/_agent_audit and normal checkpoint hooks pass, whitespace
check clean. Native landing repeated report-link/diff/lint/audit gates and
passed; report commitd4481849 pushed, nativeverify pass. No BATS/ShellCheck
rerun for a report-only file; current full operator run is separate and still
active, not claimed complete. Native landing output:

```text
scope: in-scope
tests: passed
landed: kine-recurrence-readiness-luna
push: git -C /Users/cliang/src/gitrepo/personal/k3d-manager push origin k3d-manager-v1.43.9
```

Actual remote log proof:

```text
d4481849 checkpoint: before review Kine recurrence recovery readiness and command boundaries
1c8dcfe3 checkpoint: before authorize bounded Luna Kine recurrence readiness review
02203bb6 checkpoint: before record pushed fixture proof and review Cloudflare AI preflight claims
```

Only docs changed since operator run's starting02203bb6; runtime sources
still carry the previously tested fixture fixa7b5e5df. No root-cause fix or
live incident closure implied. Proper P2 remains OPEN; no PR (Claude ownsPRs).
