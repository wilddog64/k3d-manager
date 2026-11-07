# Bug: e2e results never reach the M5 hub, and runs dispatched from it fail before tests

**Filed:** 2026-11-07
**Branch:** `k3d-manager-v1.43.15` (moved 2026-11-07 by Claude, operator: "go ahead to move that four bugs to v1.43.15"; no landed fix to verify in v1.43.14; filed on `k3d-manager-v1.43.14`)
**Status:** OPEN — F1 fix specced 2026-11-07 (machine-setup ROLE=hub installs the publish-back target) and dispatched; F2 waits on one e2e run from the M5
**Priority:** P2 — the hub has had no e2e signal since the 2026-10-31 cutover; the verification dashboards are empty and `E2EResultsMissing` has fired for the full 3-day window
**Waiting on:** fix running — since 2026-11-07
**Approval:** operator 2026-11-07: "please spec (a) dispatch to Luna" (F1 option a: `make machine-setup ROLE=hub` installs the conf file and forced-command entry)
**Assigned:** Codex Luna (`MODEL=gpt-6-luna`)
**Severity:** medium
**Related:** `docs/bugs/2026-09-15-e2e-remote-results-never-reach-grafana.md` (publish-back conf file), `docs/bugs/2026-09-23-e2e-dispatch-forward-ghcr-token-over-stdin.md`, `docs/bugs/2026-10-30-host-disk-labels-the-new-hub-as-m4-and-cannot-reach-m2.md` (its 2026-11-04 regression section), `docs/bugs/2026-11-07-hermes-e2e-summary-crashes-on-null-counts.md`

## Symptom

`E2EResultsMissing` (`absent(e2e_last_run_pass)`) has fired for the whole 3-day retention window (72 series-hours, 0 trips). The hub has no e2e-result ConfigMaps (`k3dm.k3d.io/e2e-result=true`) and no `e2e_*` series. `vulnerability-inventory-exporter` is up and scraped, so it has nothing to export.

## Findings (Claude, 2026-11-07, read-only)

**F1 — publication still targets M4, and M5 has no target.** The M2 log of run `1794051590-16732` ends `WARN: [e2e-remote] M4 publication unavailable; retained 1794051590-16732.publication_pending.json for replay`. The publish-back host comes from `E2E_M2_PUBLISH_BACK_HOST`, read under launchd from `~/.config/k3d-manager/e2e-remote.env` (the 2026-09-15 fix). That file exists on the M4 and names `m4-air.local`. On the M5 the directory holds only `machine-role`. The cutover and `make machine-setup ROLE=hub` did not carry it over, nor the matching publisher key and forced-command entry. The M2 holds 10 `publication_pending` results.

**F2 — runs fail at `deploying-substrate`.** Same run: `GHCR_PAT env var authenticates but cannot pull from ghcr.io — it is missing the read:packages scope`. The Vault fallback then fails with `error: context "k3d-k3d-cluster" does not exist`, although `kubectl config get-contexts` on the M2 lists that context; the fallback (`scripts/plugins/shopping_cart.sh:328`) probably runs with the vCluster's kubeconfig. The forwarded token comes from the dispatching host, now the M5. Cause of the missing scope and the kubeconfig in the fallback are not confirmed.

Since the summary has null counts, Hermes then crashes (separate bug, linked above).

## Progress

- 2026-11-07: operator ran `gh auth refresh` on the M5 (F2 step 1). Next: one e2e run dispatched from the M5 shows whether `deploying-substrate` now passes (E2).
- 2026-11-07 (Claude, read-only over ssh): the M5's `gh auth status` still lists `Token scopes: 'gist', 'read:org', 'repo', 'workflow'`. There is no `read:packages`: the refresh was run without `-s read:packages`, so it kept the old scopes. An e2e run now would fail at `deploying-substrate` again. Next: the operator runs `gh auth refresh -h github.com -s read:packages` on the M5 (browser approval). Then one e2e run is dispatched from the M5.
- 2026-11-07 21:24Z: the operator logged in to `gh` again on the M5. The scopes are now `admin:public_key, gist, read:org, repo`: still no `read:packages`, and `workflow` is gone. The first dispatch was refused with `capacity_cpu`. On the M2, session `/tmp/m2-air.dtach` had attached to itself (client PID 76249 runs inside the session's own zsh, 34517); the two dtach processes used about 190% CPU for nearly two days, which put the load at about 6 of 8. The retry ran as run `1794086678-29708` and failed at `deploying-substrate`. Transcript on the M5, `~/.k3dm/e2e/dispatch/m2-20261107T212437Z.log`:
  - line 12: `GHCR_PAT env var authenticates but cannot pull from ghcr.io — it is missing the read:packages scope`. This confirms F2's cause.
  - line 14: `error: context "k3d-k3d-cluster" does not exist`, in the Vault fallback. This is the secondary issue, still open.
  - line 30: `cliang@m5-air.local: Permission denied (publickey,...)`, then the result was kept as pending. This run's publish-back target is already the M5, and only the forced-command entry is missing, which the F1 fix installs. The M5 has no `e2e-remote.env`, so where the M5 target came from is not established.
  - Next: `gh auth refresh -h github.com -s read:packages,workflow` on the M5, then one more run.

## Decision (operator, 2026-11-07: option a for F1)

1. F1: point publish-back at the M5. Either Claude specs `make machine-setup ROLE=hub` to install the conf file, publisher key and forced-command entry (and a read-only check), or the operator recreates them by hand once. Either way, `make e2e-replay` then drains the 10 pending results.
2. F2: refresh the M5's GitHub credential with `read:packages` (`gh auth refresh -h github.com -s read:packages`, run by the operator), then rerun one e2e. The kubeconfig in the Vault fallback needs a separate look only if the token fix is not enough.

## Fix spec — F1 (2026-11-07)

Read-only state, 2026-11-07 (Claude):
- The M2 still holds `~/.ssh/e2e-m4-publisher` and `.pub`, and its `known_hosts` already has `m5-air.local`. No M2 change is needed.
- The M5 has no `e2e-m2-publisher` line in `~/.ssh/authorized_keys` and no `~/.config/k3d-manager/e2e-remote.env`. Its LAN address is 192.168.39.168, inside the old entry's `from="192.168.39.0/24"`.
- The M4 entry (captured 2026-11-07, key elided): `from="192.168.39.0/24",command="/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/k3d-manager e2e_result_publish",restrict,no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding ssh-ed25519 <key> e2e-m2-publisher@m2-air-20260824 …`. Its conf is one line: `E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local`.

### Change

Add an `install_e2e_publish_back` phase to `bin/k3dm-machine-setup`. It runs only for `--role hub`, after `copy_files` and before `run_agents`, and reports through `report` and `record_failure` like the other phases.

1. **Conf file.** `~/.config/k3d-manager/e2e-remote.env` must hold `E2E_M2_PUBLISH_BACK_HOST=<id -un>@<scutil --get LocalHostName>.local`. The value must match `^[A-Za-z0-9._@-]+$` (the reader's own check, `scripts/plugins/e2e_remote.sh:140`); otherwise call `record_failure`.
   - File missing: create it with mode 600, in a directory with mode 700.
   - File present with the correct line: report `ok`.
   - File names another host (for example one copied from the M4): replace only that line, keep every other line, and report `updated (was <old value>)`.
   - Writes are atomic: `mktemp` in the same directory, then `mv`.
2. **Forced-command entry.** `~/.ssh/authorized_keys` needs exactly one entry for the publisher key:
   `from="<subnet>",command="<REPO_ROOT>/scripts/k3d-manager e2e_result_publish",restrict,no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding <key type> <key blob> <comment>`.
   `REPO_ROOT` is this checkout, resolved from the script's own location.
   - Read the key and `from=` value from the old hub. With `--from HOST` (validated like `copy_files`), run `ssh -o BatchMode=yes -o ConnectTimeout=10 -- HOST` with a fixed remote command that prints the `authorized_keys` lines containing `e2e-m2-publisher`.
   - Take the first such line. The key must match `^ssh-ed25519 [A-Za-z0-9+/]+=* e2e-m2-publisher@[A-Za-z0-9._-]+`, and `from=` must match `^[0-9./,]+$`. Anything else is a `record_failure`, and nothing is written.
   - Entry present with this exact form: report `ok`. No `--from` is needed.
   - Present with the same key blob but other options (for example the M4 path): replace that one line.
   - Missing and no `--from`: `record_failure` with `missing (rerun with FROM=<old hub> to copy the e2e publisher key)`.
   - Never change any other line. Write atomically with `mktemp` in `~/.ssh` and mode 600, keeping the file's existing lines and order, like `bin/hub-cutover:338-370`.
3. **Modes.** `--check` reports the state of both items and writes nothing; a missing or wrong item is a failure. `--dry-run` reports `would write` or `would update` and writes nothing.
4. `docs/howto/m5-hub-migration.md`: a short section, "e2e publish-back". It says `make machine-setup ROLE=hub FROM=<old hub> SECRETS=skip AGENTS=skip` installs both items. It also says that `make e2e-replay` then drains the M2's `publication_pending` results.
5. `scripts/tests/bin/machine_setup.bats`: the Acceptance tests, using the existing scratch `HOME` and stub harness. Stub `ssh`, `scutil` and `id`. The stub `ssh` output keeps the captured line format above, but uses a key generated in the test (`ssh-keygen -q -t ed25519 -N '' -C e2e-m2-publisher@m2-air-20260824`). Put the capture's host and date in a comment beside it. Each test first asserts that `HOME` is the scratch directory and not the real one.

### What NOT to Do

- Do not change `scripts/plugins/e2e_remote.sh`, the M2, the publisher key, `e2e_result_publish`, or any role other than hub.
- Do not run `machine-setup`, `ssh` to a real host, or `make e2e-replay`. Do not touch the real `~/.ssh` or `~/.config`.
- Do not add the key to any repo file. Do not use `eval`. Do not edit `CLAUDE.md`, `memory-bank/` or `docs/roadmap.md`.
- No commit, no PR. Do not skip hooks. F2 is not part of this fix.

## Files

- `bin/k3dm-machine-setup`
- `scripts/tests/bin/machine_setup.bats`
- `docs/howto/m5-hub-migration.md`

## Acceptance

```yaml
interface:
  - "~/.config/k3d-manager/e2e-remote.env on the hub; scripts/plugins/e2e_remote.sh e2e_runner_publish_back; make e2e-replay"
  - "bin/k3dm-machine-setup --role hub [--from HOST] [--check|--dry-run]; make machine-setup ROLE=hub FROM=<host>"
  - "env: scratch HOME; PATH stubs for ssh, scutil, id as in scripts/tests/bin/machine_setup.bats"
must:
  - id: M1
    text: "A run dispatched from the M5 publishes its result to the M5 hub: an e2e-result ConfigMap appears and e2e_last_run_pass has a series."
  - id: M2
    text: "A run dispatched from the M5 passes deploying-substrate."
  - id: M3
    text: "machine-setup --role hub --from OLD writes e2e-remote.env naming <user>@<LocalHostName>.local, and one authorized_keys entry with the old entry's key and from= value, command=<REPO_ROOT>/scripts/k3d-manager e2e_result_publish and the restrict options; a second run reports ok and changes no byte."
  - id: M4
    text: "A conf naming another host has that line replaced and its other lines kept; an entry with the publisher key and an old command path is replaced in place."
must_not:
  - id: N1
    text: "No result is published to the M4."
  - id: N2
    text: "machine-setup never changes an authorized_keys line other than the publisher entry: a file with three unrelated lines (one with options) keeps them byte-for-byte and in order (paired control: M3's run adds the entry)."
  - id: N3
    text: "--check, --dry-run, a non-hub role, a missing --from, or an old-host line failing the key or from= pattern writes neither file (byte-compare or absence), and a non-hub role makes no ssh call (paired control: M3's run writes both)."
evidence:
  - id: E3
    proves: [M3, M4, N2, N3]
    kind: offline
    what: "bats scripts/tests/bin/machine_setup.bats and machine_setup_acceptance.bats; N2 and N3 shown red against a mutated phase (one that rewrites the whole file, one that writes in --check); both suites green."
  - id: E1
    proves: [M1, N1]
    kind: live
    what: "Claude: after the change and make e2e-replay, the hub has e2e-result ConfigMaps, E2EResultsMissing resolves, and the M2's publish audit names the M5."
  - id: E2
    proves: [M2]
    kind: live
    what: "Claude: the next run's summary on the M5 has a phase past deploying-substrate and non-null counts."
```
