# Bug: console TOTP gate: flat silent lockout allows slow brute force and operator lockout; world-writable socket

**Status:** OPEN — spec rev 1 (Fable review pending)
**Priority:** P2
**Introduced by:** v1.45.0 web-console plan C (`1026dbe2`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-23 (Fable spec review)
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** the second factor weakens over time unobserved (about 0.4%/day for a cert holder); a cert holder or same-uid process can keep the operator out.
**Findings:** Fable 2 (Medium), Fable 8 (Low). Claude: plausible (constants read; not reproduced: needs root daemon), P2.

## What is wrong

- `scripts/libexec/k3dm-console-totpd.py:789-805`: 5 failures lock for 300 s, then reset (`:744-770`); window ±1 step (`:173-187`).
  About 1,440 guesses a day at 3 in 10^6 each. Failed codes and locks are not logged, counted or alerted (`log_event` call sites).
- No `RevokedKeys` in `scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl`; only the whole-console revoke.
- `:397` sets `totp.sock` to 0666 with 4 admit slots (`:515-525`): a same-uid connect loop blocks console login (it cannot guess).

## Fix direction

Escalating lock (5 min, 30 min, 4 h, then re-enrol); a log line and Pushgateway counter per failure and lock, alert on any lock;
`RevokedKeys` in the template and expected-lines list; short-lived certs; socket 0600 owned by the console uid.

## Operator probe

`ssh-keygen -L -f <console cert>`: certificate validity period.

## Files

| # | File | Change |
|---|------|--------|
| 1 | `scripts/libexec/k3dm-console-totpd.py` | escalating lock with a persisted `lock_level`; monotonic in-process deadline; `load_state` migration; structured log lines; metrics file; admin `UNLOCK`; `totp.sock` 0600 owned by the console uid |
| 2 | `scripts/libexec/k3dm-console-gate.py` | accept the new `LOCKED` reply (`:157` regex, `:338-352` branch) |
| 3 | `scripts/libexec/k3dm-console-totpctl.py` | `totpctl unlock` (usage line `:37`, verb dispatch `:38-90`) |
| 4 | `scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl` | `RevokedKeys /etc/k3dm-web-console/revoked_keys` after `TrustedUserCAKeys` |
| 5 | `bin/k3dm-web-console-sshd` | expected-lines list (`_wc_render` `:25-75`); create an empty KRL if absent; `_wc_dest_check` (`:149-151`), `_wc_files_healthy` (`:217-240`), dry-run plan (`:693`) |
| 6 | `bin/k3dm-console-totp-metrics` (new) | read the metrics file, PUT it to the Pushgateway (pattern: `bin/k3dm-disk-metrics:93-108`) |
| 7 | `bin/k3dm-hermes` | `_publish_console_totp_metrics()` next to `_publish_disk_metrics()` (`:881-891`, call site `:1050`) |
| 8 | `scripts/etc/prometheus/rules/web-console-totp.yaml` (new) | `ConsoleTotpLocked`, `ConsoleTotpReenrolRequired` (synced by `scripts/etc/argocd/applicationsets/prometheus-rules-hub.yaml:31-34`, `include: '*.yaml'`) |
| T | `scripts/tests/bin/test_web_console_totp.py`, `scripts/tests/bin/web_console_sshd.bats`, `scripts/tests/bin/test_console_totp_metrics.py` (new), `scripts/tests/observability/test_console_totp_alert.py` (new) | tests below |

Eight files, so the work is split (see Routing).

## Behaviour

**B1 Escalating lock.** `state.json` gains `lock_level` (int 0–4). Five consecutive failures raise the level by one and
lock for `LOCK_SECONDS = [300, 1800, 14400]` at levels 1–3. The fifth failure still replies `NO`; attempts while locked
reply `WAIT <remaining>`. At level 4 the lock has no expiry and every attempt replies `LOCKED` until it is cleared.
When a lock expires, `failures` resets to 0 and **`lock_level` is kept**, so the next five failures escalate. Only a
successful code, `totpctl unlock`, enrol or rotate resets `failures`, `locked_until` and `lock_level` to 0.

**B2 Clock.** The running daemon enforces a lock against `monotonic()` (`lock_deadline_mono`), so wall-clock jumps
cannot shorten it. `locked_until` stays on disk as wall seconds for restarts (monotonic does not survive a restart).
At startup and on each load the in-process deadline is rebuilt as
`monotonic() + clamp(locked_until - clock(), 0, LOCK_SECONDS[level-1])`. The clamp means a forward-set wall clock at
lock time cannot persist a lock longer than its level allows, and a backward jump across a restart extends it by at most
one duration. Level 4 ignores both clocks.

**B3 State migration.** `load_state` accepts exactly the old 5-key set (it reads as `lock_level: 0`) or the new 6-key
set. Any other key set, a non-int or negative value, or `lock_level > 4` returns `False` (state-unavailable), as
today. Every commit writes the 6-key form.

**B4 Unlock.** A new admin verb `UNLOCK` on `admin.sock` (still peer uid 0, 0600) replies `UNLOCKED` and commits the
reset, or `NOT_ENROLLED` / `UNAVAILABLE`. `totpctl unlock` sends it and prints `unlocked`. It is root only, like `status`.

**B5 Log lines.** `log_event` keeps the existing bare names and adds structured lines, one per event:
`<UTC ISO-8601> event=<name> key=value ...`. Events and fields:
- `totp-failure failures=<n> lock_level=<l>`
- `totp-lock lock_level=<l> seconds=<s|none>`
- `totp-locked-reply lock_level=<l>` (only on the first refused attempt per lock, so a loop cannot flood the log)
- `totp-unlock source=<admin|success|enrol|rotate>`

No line ever carries the submitted code, the secret or a counter value. Logging stays best-effort and never changes a
reply.

**B6 Metrics.** After each failure, lock, unlock and at startup, totpd atomically rewrites
`/var/db/k3dm-web-console-run/totp-metrics.prom`. It uses tmp + `os.replace` in `run_dir`, is root:wheel 0644 and is
text exposition only:
```
k3dm_console_totp_failures_total <int>
k3dm_console_totp_locks_total <int>
k3dm_console_totp_unlocks_total <int>
k3dm_console_totp_lock_level <0-4>
k3dm_console_totp_metrics_written_timestamp_seconds <int>
```
The counters live in memory and restart from 0; `increase()` handles resets. `lock_level` comes from state, so it
survives restarts. totpd itself does **no network I/O**: a root daemon in the login path must not block on HTTP.
`bin/k3dm-console-totp-metrics` (run by Hermes each cycle, like `k3dm-disk-metrics`) reads the file and PUTs it to
`${K3DM_CONSOLE_TOTP_PUSHGATEWAY_URL:-http://localhost:19094}/metrics/job/k3dm-console-totp`. If the file is missing it
exits 0 with a stderr line and pushes nothing.

**B7 Alerts.** `scripts/etc/prometheus/rules/web-console-totp.yaml`, in the same shape as `host-disk.yaml`
(`release: kube-prometheus-stack`, `cluster: hub`):
- `ConsoleTotpLocked`, severity warning:
  `sum(increase(k3dm_console_totp_locks_total{job="k3dm-console-totp"}[1h])) > 0 or max(k3dm_console_totp_lock_level{job="k3dm-console-totp"}) >= 2`, `for: 0m`.
- `ConsoleTotpReenrolRequired`, severity critical: `max(k3dm_console_totp_lock_level{job="k3dm-console-totp"}) >= 4`, `for: 0m`.

**B8 Socket.** `totp.sock` is bound with `os.umask(0o177)` and the old umask restored, then
`os.chown(path, conf["uid"], 0)`, `os.chmod(path, 0o600)`, then `listen`. Nothing can connect before the final mode.
The gate connects as the console uid: `admit()` (`:227-323`) requires the peer chain `sshd-session` (console uid) →
`sshd-session [priv]` (uid 0) → listener. So **owner = console uid is required**: a root-owned 0600 socket would refuse
the gate and lock every login (the socket-uid risk). `admin.sock` is unchanged (0600 root). `run_dir` stays 0755 root.

**B9 Same-uid DoS, a limitation stated rather than fixed.** 0600 stops other local uids (`_www`, `nobody`, other users,
sandboxed daemons) from filling the 4 pending slots (`:515-525`). It does not stop a process running as the console uid.
That uid is the operator's own login uid (`bin/k3dm-web-console-totp:288`, `uid=$op_uid`), and a process holding it can
already do more than block console login. No per-uid quota can separate the gate from that attacker. Out of scope here;
see Open questions.

**B10 RevokedKeys.** The template and `_wc_render` gain `RevokedKeys /etc/k3dm-web-console/revoked_keys`. The file name
must differ from the existing whole-console marker `/etc/k3dm-web-console/revoked`: `_wc_files_healthy` requires that
marker to be **absent** (`bin/k3dm-web-console-sshd:220-222`), and `web_console_common.sh:129,212,217` parks the daemon
when it exists. The installer creates the file only if it is absent, as an empty KRL (`ssh-keygen -k -f <stage>/revoked_keys`,
root:wheel 0644). It treats the file like the host key: it is operator data, never overwritten on reinstall (an overwrite
would un-revoke) and not a manifest part-A row. `_wc_files_healthy` fails if the file is missing, a symlink, not regular,
not root-owned or not 0644. The installer refuses to activate a config while the file is missing. Reason (External
behaviour): sshd then refuses every key, and `sshd -t` does not catch it. To revoke a cert: `ssh-keygen -k -u -f
/etc/k3dm-web-console/revoked_keys <cert or spec>` (operator, root).

## Contract readers

| Contract | Writers | Readers | Change |
|----------|---------|---------|--------|
| `state.json` key set | `totpd.py` commits at `:644`, `:746`, `:777`, `:794` | `load_state` `:141-160`; test fixtures that seed 5-key state, `test_web_console_totp.py:154,251,351,408,754,852` | 6th key `lock_level`; 5-key still loads |
| totpd reply vocabulary | `totpd.py` totp_client branch `:736-805` | gate `:157` (regex), `:338-352` | add `LOCKED` |
| admin verbs | `totpctl.py:42,78-79` | `totpd.py:572-664` | add `UNLOCK` / `UNLOCKED` |
| `totp.sock` mode/owner | `totpd.py:394-398` | gate `:17,:113-145` (connects as the console uid); `test_N12_and_E4_verifier_socket_not_in_child` `:810` | 0666 → 0600, owner `conf["uid"]` |
| `totp.conf` `uid` | `bin/k3dm-web-console-totp:288` | `parse_config` `:49-98`, `admit`, new chown | read only |
| totp log `/var/log/k3dm-web-console-totp.log` | `log_event` `:335-340` | `bin/k3dm-web-console-totp` (mode 0600, `:376`), `scripts/etc/launchd/com.k3d-manager.web-console-totp.plist.tmpl`, `scripts/tests/bin/web_console_totp.bats` | new structured lines appended; bare names kept |
| `run_dir/totp-metrics.prom` (new) | totpd | `bin/k3dm-console-totp-metrics`; uninstall `rm -rf` of `run_dir` (`bin/k3dm-web-console-totp:493`) | new |
| Pushgateway job `k3dm-console-totp` (new) | `bin/k3dm-console-totp-metrics` | `rules/web-console-totp.yaml` | new |
| sshd_config line set | template; `_wc_render` `bin/k3dm-web-console-sshd:25-75` | sshd; `web_console_sshd.bats` render tests | add one line in both, same position |
| `/etc/k3dm-web-console/revoked_keys` (new) | sshd installer stage (beside `_wc_stage_keys` `:464-474`) | sshd (`RevokedKeys`); `_wc_dest_check` `:149-151`; `_wc_files_healthy` `:217-240`; dry plan `:693` | new; distinct from the `revoked` marker (`web_console_common.sh:129,212,217,495-497`; `bin/k3dm-web-console-sshd:150,220,330,381,406,544,563`), which is unchanged |

## External behaviour

Proved on m4-air, 2026-11-23, `ssh -V` / `sshd -V` = `OpenSSH_10.2p1, LibreSSL 3.3.6`. Upstream source is
`openssh/openssh-portable` at tag `V_10_2_P1`, fetched with `gh api .../contents/<file>?ref=V_10_2_P1`.

- **sshd_config(5), local man page:** "Note that if this file is not readable, then public key authentication will be
  refused for all users." It accepts a flat key list or a KRL.
- **Missing or unreadable file means every key is refused.**
  - `auth.c:545-578` `auth_key_is_revoked`: any `sshkey_check_revoked` result other than `0` or `SSH_ERR_KEY_REVOKED`
    is logged as "Error checking authentication key …" and returns 1 (revoked).
  - `authfile.c:437-461` → `krl.c:1275-1297` `ssh_krl_file_contains_key`: `sshbuf_load_file` fails on a missing file
    with a system error, and that falls into the default branch.
- **An empty plain file means nothing is revoked.**
  - `krl.c:1060-1062`: no KRL magic gives `SSH_ERR_KRL_BAD_MAGIC`.
  - `authfile.c:443-456`: the code then falls back to `sshkey_in_file`, which returns `SSH_ERR_KEY_NOT_FOUND`, so the
    key is not revoked.
- **For certificates, both the cert key and its CA key are checked** (`auth2-pubkey.c:804-807`). Listing the CA key
  revokes every cert.
- **`sshd -t` does not read the file.** Live: `sshd -t -f <scratch cfg with RevokedKeys <scratch>/missing> -h
  <scratch hostkey>` gave rc 0, and `sshd -T` echoed `revokedkeys <path>`. So the installer's existing `sshd -t` gate
  cannot catch a missing file, and B10 adds an explicit existence check.
- **Live, scratch key, `ssh-keygen -Q`:**
  - `ssh-keygen -k -f emptykrl` with no keys: rc 0, 44 bytes, and `-Q` reports `ok` (rc 0).
  - A KRL built from the key reports `REVOKED` (rc 1).
  - `-Q` itself only reads KRLs: an empty plain file gives "invalid magic number" (rc 255).
  - So the install creates a real empty KRL. sshd accepts it, `-Q` can audit it, and `-k -u` can extend it.
- **Not proven live:** sshd authenticating against the empty KRL. That is evidence L1 after promote.

## Acceptance

```yaml
must:
  - id: M1
    text: five consecutive failures lock for 300 s, the next five after expiry for 1800 s, then 14400 s, then LOCKED with no expiry
  - id: M2
    text: a daemon restart keeps lock_level and the remaining lock (clamped to the level's duration)
  - id: M3
    text: a correct code resets failures, locked_until and lock_level to 0
  - id: M4
    text: "`totpctl unlock` (admin UNLOCK, peer uid 0 only) and enrol/rotate clear the lock; a non-root admin peer is refused"
  - id: M5
    text: a 5-key state.json loads as lock_level 0 and the next commit writes 6 keys; extra keys or lock_level > 4 are refused
  - id: M6
    text: each failure, lock and unlock writes one structured log line with no code, secret or counter value (positive control - the line exists)
  - id: M7
    text: totpd writes totp-metrics.prom (root 0644, five series) on every failure, lock, unlock and at startup, and contains no network calls; the collector PUTs it to job k3dm-console-totp and Hermes calls the collector
  - id: M8
    text: ConsoleTotpLocked fires on any lock within 1 h and ConsoleTotpReenrolRequired at level 4; neither fires with zero locks and level 0
  - id: M9
    text: totp.sock is 0600 and owned by conf uid before listen, and the gate-chain peer (conf uid) still gets OK for a valid code
  - id: M10
    text: the rendered sshd_config and the _wc_render list both carry RevokedKeys /etc/k3dm-web-console/revoked_keys; install creates an empty KRL root:wheel 0644 only when absent; _wc_files_healthy fails when it is missing, a symlink or the wrong mode
must_not:
  - id: N1
    text: the second lock must not be 300 s (flat reset)
    red_on_current: current code resets to failures 0 and re-locks for 300 s (:744-748, :794)
  - id: N2
    text: a restart between locks must not drop the escalation level
    red_on_current: no lock_level exists; the next lock after restart is 300 s
  - id: N3
    text: a wall-clock jump forward while running must not shorten an active lock
    red_on_current: lock compares wall clock t_now < locked_until (:740); +300 s jump unlocks
  - id: N4
    text: a failed attempt must not leave no totp-failure line in the log
    red_on_current: log_event is never called on NO (:789-805)
  - id: N5
    text: totp.sock must not be 0666 nor connectable by a uid other than conf uid at the filesystem layer
    red_on_current: os.chmod(totp_sock_path, 0o666) (:397)
  - id: N6
    text: the rendered sshd_config must not lack a RevokedKeys line
    red_on_current: template and _wc_render have none
  - id: N7
    text: a reinstall must not replace an existing non-empty revoked_keys
    red_on_current: current install neither creates nor references the file, so the pre-seeded-KRL-and-referenced assertion fails
  - id: N8
    text: install must not activate a config referencing revoked_keys while the file is missing
    red_on_current: current healthy check passes with no revoked_keys
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "escalat"
    red_control: on pre-fix totpd the second lock reads WAIT 300, not WAIT 1800
    intent: pending
  - id: E2
    proves: [M2, N2]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "restart_keeps_level"
    red_control: pre-fix restart leaves no lock_level; assertion on 1800 fails
    intent: pending
  - id: E3
    proves: [N3, M3]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "monotonic or success_resets"
    red_control: VerifierFixture wall += 301 with tick unchanged unlocks pre-fix code
    intent: pending
  - id: E4
    proves: [M4, M5]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "unlock or migration"
    red_control: pre-fix admin replies to UNLOCK with the unknown-verb path; a 6-key state is refused by load_state
    intent: pending
  - id: E5
    proves: [M6, N4]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "structured_log"
    red_control: pre-fix log has no totp-failure line after a NO; code-absence assert paired with line-present control
    intent: pending
  - id: E6
    proves: [M7]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "metrics_file or no_network" scripts/tests/bin/test_console_totp_metrics.py
    red_control: pre-fix run_dir has no totp-metrics.prom; collector test asserts its stub Pushgateway endpoint (scratch port) is the target before PUT
    intent: pending
  - id: E7
    proves: [M8]
    kind: offline
    command: python3 -m pytest scripts/tests/observability/test_console_totp_alert.py
    red_control: rules file absent pre-fix; promtool series with locks_total flat and level 0 must not fire
    intent: pending
  - id: E8
    proves: [M9, N5]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "socket_mode"
    red_control: pre-fix stat shows 0o666; the OK-for-gate-uid check is the positive control
    intent: pending
  - id: E9
    proves: [M10, N6, N7, N8]
    kind: offline
    command: bats scripts/tests/bin/web_console_sshd.bats -f "revoked_keys"
    red_control: pre-fix rendered config has no RevokedKeys; fake-root reinstall with pre-seeded KRL fails the referenced-and-unchanged assert
    intent: pending
  - id: L1
    proves: [M9, M10]
    kind: live
    command: after operator make hub-deploy and console install; operator logs in once with cert + code; Claude reads stat -f '%Su %Lp' of totp.sock and revoked_keys and ssh-keygen -Q -f revoked_keys <console cert> (read-only)
    red_control: login failure or revoked_keys missing blocks the release PR
    intent: pending
interface:
  totpd_reply: "OK | NO | UNAVAILABLE | WAIT <n> | LOCKED"
  admin_verb: "UNLOCK -> UNLOCKED | NOT_ENROLLED | UNAVAILABLE"
  cli: "totpctl unlock"
  state_keys: "secret, last_counter, failures, locked_until, enrolled, lock_level (old 5-key accepted)"
  metrics_file: /var/db/k3dm-web-console-run/totp-metrics.prom
  pushgateway_job: k3dm-console-totp
  sshd_line: RevokedKeys /etc/k3dm-web-console/revoked_keys
```

Test fixtures, for every child:
- Python tests use the existing `VerifierFixture` seams (`clock`, `monotonic`, `peer_cred_fn`, `expected_*_owner`) under
  `tmp_path`. Each fixture first asserts that `run_dir` and `state_dir` are under `tmp_path`.
- Bats tests use `_WC_PREFIX` as a fake root and a scratch `HOME`. The first assert in each is that the prefix is under
  `BATS_TEST_TMPDIR`.
- `sudo` and `launchctl` stubs on `PATH` exit non-zero and record the call. Install targets run only against the fake
  prefix, never unstubbed.
- The existing `test_N1_and_M2_lockout_and_hmac_calls` asserts the flat reset (`:305-317`). It is updated to the
  escalation, because that assertion is the bug.

**Intent approved:** pending

## Routing

There are more than 3 files, so the work splits into three child specs, one dispatch per file set:

| Child | Worker | Files | Evidence |
|-------|--------|-------|----------|
| A: lock, log, metrics file, socket | Luna | 1, 2, 3 + `test_web_console_totp.py` | E1–E6 (totpd part), E8 |
| B: RevokedKeys | Luna | 4, 5 + `web_console_sshd.bats` | E9 |
| C: collector, Hermes hook, alert rules, guide note | Flash | 6, 7, 8 + `test_console_totp_metrics.py`, `test_console_totp_alert.py`, web-console guide section on unlock/revoke | E6 (collector part), E7 |

- A and B touch no common file and can run in parallel. C depends only on the B6 file format fixed above, so it can run
  beside them, but together that is all 3 WIP slots.
- Suggested order: B first (smallest, isolated), then A, then C once A lands, if other v1.45.1 dispatches need slots.
- L1 runs after promote and is done by the operator or Claude, not a worker.

## Open questions

1. **Short-lived certs (Fix direction).** The operator probe (`ssh-keygen -L -f <console cert>`) has not been run, so
   the current validity period is unknown. If it is long (months), RevokedKeys becomes the only way to cut off a lost
   device. Proposal: a separate plan, outside this bug, for CA-side issuance with `-V +1d` (or the trip length) plus a
   renewal path. Decision for the operator: the target validity, and whether v1.45.1 carries it or it goes to the
   roadmap.
2. **Same-uid DoS (B9).** Accept it as a documented limitation (recommended), or add a later mitigation, such as cutting
   the 5 s admitted deadline or a per-peer-pid pending cap? Neither stops a same-uid attacker who forks.
3. **Level-4 recovery when away.** `totpctl unlock` needs root on the hub. From an iPad on travel, a level-4 lock means
   no console until home. Is that the intended trade-off, or should level 4 instead be a long timed lock (for example
   24 h)?
4. **Escalation memory.** `lock_level` decays only on success, unlock or re-enrol. Should it also decay after, for
   example, 24 h without failures?
