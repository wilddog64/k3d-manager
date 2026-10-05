# Bug: `sandbox-up` can hang with no limit when the sandbox server node stops answering SSH

**Branch:** `k3d-manager-v1.41.0`
**Filed:** 2026-10-03, Claude
**Status:** FIXED (Codex, Claude-verified; recorded in `396a3e2b`). Status line updated 2026-10-04.
**Files:** `scripts/lib/webhook/lifecycle.py`, `scripts/plugins/shopping_cart.sh`, tests, `CHANGELOG.md`

## What the operator asked for

> "we need to address this so cloud agent trigger run won't hung forever"

## What happened (2026-10-03, operator terminal `make up CLUSTER_PROVIDER=k3s-aws`)

- **The log stopped moving.** It sat at `Running: k3sup install` / `Public IP: 44.245.8.111` from 08:16:59 onward.
- **The server node was alive but not answering.** Instance `i-0bf394180ce3a98ba` (t3.medium):
  - EC2 reported it running, with both status checks `ok`;
  - SSH got as far as the connection and then reported `Connection timed out during banner exchange`;
  - `:6443` timed out.
- **CPU had been pinned since the monitoring stack landed.** It ran at about 64% from 08:04, when the previous run deployed the monitoring stack, and then hit 96%. CPU credits were 0.
- **The node never recovered.** An operator `reboot-instances` did not get a new boot onto the console in the next 8 minutes. The operator tore the sandbox down.
- **The root cause of the saturation is not proven.** Memory pressure on a 4 GB node is the leading theory, but no one could get in to measure it. That is out of scope here; see "Follow-up".

The same run, started by a cloud agent through the bridge (`sandbox-up`), has nothing that ends it.

## Root cause — two missing bounds

1. **The webhook cluster job has no deadline.** `_run_cluster` (`scripts/lib/webhook/lifecycle.py`) waits with `os.waitpid(pid, 0)`:
   - it blocks until `make` exits, however long that takes;
   - the 2-minute progress timer and the stall analysis only post Slack notices, and never end the job;
   - while the job runs, `_running_cluster_job()` answers every other cluster request with 409, so the hang also blocks `sandbox-down`;
   - the bridge stops watching after `LIFECYCLE_TIMEOUTS["sandbox-up"]` (3600 s) plus its margin, and answers "watch expired", but the job underneath keeps running.
   
   `_run_make_target` in the same file already has the right pattern: a `_wait(pid)` deadline loop, `killpg(SIGTERM)` and `timed out after Ns`. The 2026-06-15 issue (`docs/issues/2026-06-15-acg-credential-extraction-sandbox-404-timeout.md`) describes a webhook timeout firing SIGTERM, so a cluster job used to have a limit. The current `_run_cluster` has none.
2. **`make up` goes on to `k3sup` against a host whose SSH does not answer.** In `scripts/plugins/shopping_cart.sh`:
   - `_ubuntu_k3s_trust_host` gives up after 120 s of failed `ssh-keyscan` and *continues* (`_warn "... k3sup may prompt"; return 0`);
   - `k3sup install` then opens its own SSH session, with no connect deadline and no keepalive;
   - the follow-up heredoc `ssh` (copying `k3s.yaml`) has neither `ConnectTimeout` nor `ServerAliveInterval`.

## Fix

### H1 — `scripts/lib/webhook/lifecycle.py`: give `_run_cluster` a hard deadline

- **Add one module-level helper** next to `_STALL_TICKS_THRESHOLD`:

  ```python
  def _cluster_job_timeout(action):
      _defaults = {"up": 3300, "down": 1500}
      _env = {"up": "K3DM_CLUSTER_UP_TIMEOUT", "down": "K3DM_CLUSTER_DOWN_TIMEOUT"}
      try:
          return int(os.environ.get(_env.get(action, ""), _defaults.get(action, 1500)))
      except ValueError:
          return _defaults.get(action, 1500)
  ```

  The defaults are deliberately below the bridge's `LIFECYCLE_TIMEOUTS` (3600 / 1800). That way a cloud agent following the job with `--wait-final` always sees a terminal status, never "watch expired".
- **Replace the blocking wait in `_run_cluster`.** Old:

  ```python
          _, _status = os.waitpid(pid, 0)
          _rc = os.WEXITSTATUS(_status) if os.WIFEXITED(_status) else -os.WTERMSIG(_status)
  ```

  New: poll with `os.waitpid(pid, os.WNOHANG)` until `time.monotonic()` passes `_cluster_job_timeout(action)`, in the same shape as `_run_make_target._wait`. On expiry:
  - `os.killpg(pid, signal.SIGTERM)`;
  - poll for up to 30 s more; if the process is still alive, `os.killpg(pid, signal.SIGKILL)` and then `os.waitpid(pid, 0)`;
  - `_write_log(f"ERROR: cluster-{action} timed out after {timeout}s — killed")`;
  - `raise RuntimeError(f"cluster-{action} timed out after {timeout}s")`.

  The existing `except` path then runs unchanged: the failure note, `_analyze_failure`, `_finish("failed")` and, for `up`, the `_run_cleanup` thread.
  
  Keep the existing post-exit `os.killpg(pid, signal.SIGTERM)`, which reaps stray children.
- **Check how `time` is imported** in `lifecycle.py`; it is used by `_run_make_target`.
- **Do not change** `_run_cluster_resume`, `_run_make_target`, the provider map or the `KEEP_LOCAL=1` down path.

### H2 — `scripts/plugins/shopping_cart.sh`: fail fast when the server node's SSH does not answer

- **Add a new private function** directly after `_ubuntu_k3s_trust_host`:

  ```bash
  function _ubuntu_k3s_wait_ssh_ready() {
    local host="$1" ssh_user="$2" ssh_key="$3"
    local budget="${K3DM_SSH_READY_TIMEOUT:-180}" waited=0
    until ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=10 "${ssh_user}@${host}" true >/dev/null 2>&1; do
      if (( waited >= budget )); then
        _err "[shopping_cart] ${ssh_user}@${host} did not answer SSH within ${budget}s — node unresponsive; not starting k3sup"
        return 1
      fi
      sleep 10
      (( waited += 10 ))
    done
  }
  ```

  `ConnectTimeout` covers both the TCP connect and the banner exchange, which is exactly the failure seen here. `_err` exits non-zero, so `make up` fails with that message instead of hanging.
- **Call it in the server-install path**, after the existing `_ubuntu_k3s_trust_host "${external_ip}"` and before `_run_command -- k3sup install`:

  ```bash
  _ubuntu_k3s_wait_ssh_ready "${external_ip}" "${ssh_user}" "${ssh_key}" || return 1
  ```

- **Bound the heredoc `ssh` that copies `k3s.yaml`.** Add these options to it, keeping everything else byte-identical:

  ```
  -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4
  ```

- **Do not change** `_ubuntu_k3s_trust_host`, or the agent-join path at line ~1150. Do not wrap `k3sup` itself in a timeout; H1 bounds anything that hangs after SSH was ready.

### H3 — docs

- **`docs/howto/cloud-session-requests.md`**, in the `sandbox-up` / `sandbox-down` section, add one short paragraph:
  - the webhook ends a cluster job after 55 min (`up`) or 25 min (`down`) and marks it `failed`;
  - a node that never answers SSH fails `up` within about 3 minutes;
  - after either, the agent can request `sandbox-down`.
- **`CHANGELOG.md` `[Unreleased]` → `### Fixed`:** one prose bullet.

## Gates (offline; paste actual output)

1. **Deadline fires.** A pytest case in `scripts/tests/bin/webhook_lifecycle.py` (or a new `scripts/tests/bin/test_webhook_cluster_timeout.py`) that:
   - stubs `_posix_spawn_job` to start a real `sleep 60` in its own process group;
   - sets `K3DM_CLUSTER_UP_TIMEOUT=1`;
   - runs `_run_cluster(job_id, "up")`.
   
   Assert all of these:
   - it returns in under 40 s;
   - the job `status` file reads `failed`;
   - the output contains `timed out after 1s`;
   - the `sleep` process is gone.
2. **Normal exit is unchanged.** The same harness, with a command that exits 0 quickly, gives `success`.
3. **SIGTERM-resistant child is still killed.** A stub child that runs `trap '' TERM; sleep 60` ends with `failed` within the 30 s grace period plus the deadline (SIGKILL path).
4. **Timeout parsing.** `_cluster_job_timeout`:
   - `up` gives 3300 and `down` gives 1500 by default;
   - the env override is honoured;
   - a non-integer env value falls back to the default;
   - the defaults are less than `LIFECYCLE_TIMEOUTS` in `bin/k3dm-cloud-bridge`. Load that value by importing or parsing the bridge, not by hard-coding it.
5. **SSH preflight (BATS, stubbed `ssh` and `sleep`):**
   - an `ssh` stub that always fails makes `_ubuntu_k3s_wait_ssh_ready` return non-zero with `did not answer SSH`, after `K3DM_SSH_READY_TIMEOUT/10` attempts (use `K3DM_SSH_READY_TIMEOUT=30`);
   - a stub that succeeds on the 2nd call returns 0;
   - in the server-install function, a failing preflight means `k3sup` is never invoked. Use a `k3sup` stub that records calls, and assert its call log is empty.
6. **Mutations.** For each one, `cp` a snapshot, mutate, show the test red, restore from the snapshot, and show `cmp` byte equality. Never restore with `git checkout`.
   - (a) revert the wait to `os.waitpid(pid, 0)` → gate 1 red (give the test its own pytest timeout so it fails instead of hanging);
   - (b) drop the SIGKILL escalation → gate 3 red;
   - (c) make the preflight `return 0` on budget exhaustion → gate 5 red.
7. Run all of:
   - `shellcheck scripts/plugins/shopping_cart.sh` (no new warnings);
   - the touched BATS file;
   - bare `pytest` on the touched test files;
   - `make test-pytest`;
   - `make test-python-unit`;
   - `python3 scripts/check-doc-links.py`.
8. `git diff --stat`: only the files named above, plus tests.

## Definition of Done

- [ ] H1–H3 complete; gates 1–8 pass, output pasted.
- [ ] Commit message, exactly (trailers on consecutive lines):

  ```
  fix(webhook): bound cluster jobs with a deadline; fail fast when the sandbox node's SSH does not answer

  Co-Authored-By: Codex <noreply@openai.com>
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`.
- [ ] Operator, after Claude verifies: `make restart-webhook`.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, or use `--no-verify`.
- Do NOT edit `memory-bank/` (Claude records it).
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, or `bin/k3dm-cloud-bridge`.
- Do NOT change `_ubuntu_k3s_trust_host`, the agent-join path, `_run_cluster_resume`, `_run_make_target`, the provider map, or the `KEEP_LOCAL=1` down path.
- Do NOT run `make up`, `make down`, `bin/cluster-up` or `bin/cluster-down`, or touch the live sandbox, the webhook, the bridge or ACG credentials. Every test is offline.
- Do NOT create, read, echo or log any token value.

## Follow-up (not in this fix)

Find out why the t3.medium server node saturated about 12 minutes after the monitoring stack deployed. Measure memory on the next healthy sandbox: `free -m` and the top pods by memory, before and after `observability`. Then decide between a larger instance type and a lighter sandbox monitoring profile. This needs a live node; it is Claude's or the operator's job.
