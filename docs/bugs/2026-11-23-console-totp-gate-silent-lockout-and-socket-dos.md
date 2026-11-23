# Bug: console TOTP gate: flat silent lockout allows slow brute force and operator lockout; world-writable socket

**Status:** OPEN — spec rev 3 (recovery-code unlock added; pending Fable + Argon review)
**Priority:** P2
**Introduced by:** v1.45.0 web-console plan C (`1026dbe2`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23 (Fable + Argon review of rev 3, then intent approval of E8–E12 and L2; child A waits)
**Triage:** patch → v1.45.1 (security and DR release); metrics, alerts and socket mode split to follow-ups (see Follow-ups)
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** the second factor weakens over time unobserved (about 0.4%/day for a cert holder); a cert holder or same-uid process can keep the operator out.
**Findings:** Fable 2 (Medium), Fable 8 (Low). Claude: plausible (constants read; not reproduced: needs root daemon), P2.

## Rev 3 changes (operator decisions, 2026-11-23)

| Change | Why | Where |
|--------|-----|-------|
| Q3 answered: level 4 is a 24 h timed lock reusing `WAIT <n>`; the permanent-lock alternative and `LOCKED` are removed | operator decision | B1, M1, M9, interface |
| Q4 answered: the level decays by one per 24 h after the last lock expires | operator decision | B1, M15, E1 |
| Recovery codes: an unlock from the console that does not need root on the hub | operator request ("an unlock path from the console that does not need root"), option chosen: "Recovery codes" | B8 (new), B5, Files 1–3, Upgrade order, Rollback, Contract readers, M10–M15, N8–N12, E8–E12, L2 |
| The gate is now a changed file | the gate drops any input that is not exactly 6 digits (`k3dm-console-gate.py:332`) and buffers at most 7 bytes (`:327-328`); the daemon's VERIFY check does the same (`totpd.py`, VERIFY branch). A recovery code cannot reach the daemon without changing both | B8 Wire, Files 2, Routing |
| Child spec A written | [`docs/plans/v1.45.1-totp-a-lock-and-recovery.md`](../plans/v1.45.1-totp-a-lock-and-recovery.md), pending review; one child, not split (Routing) | Routing |

## Rev 2 changes (Fable spec review, 2026-11-23)

| Finding | Kind | Resolution |
|---------|------|------------|
| B8 socket chown cannot run at bind time: `conf` is parsed per loop (`totpd.py:427-428`) and is `None` at start; the gate connects as the console uid | blocker | B8 dropped from v1.45.1; recorded under Follow-ups with the lockout risk |
| Test `os.chown(path, uid, 0)` fails with EPERM for the fixture uid 501 (`test_web_console_totp.py:842-855`) | blocker | gone with B8. Remaining scope needs no chown: the KRL owner check reuses `_wc_file_mode`, whose `stat` goes through `_wc_tool`, stubbed in `web_console_sshd.bats:399-403` |
| B8 closes none of the described DoS: wrong-uid peers are closed before the pending-slot check | should-fix | B9 rewritten: the real DoS is same-uid; 0600 is defence in depth only |
| Monotonic deadline recomputed on every `load_state` lets a wall-clock jump move it | should-fix | B2: deadline set once per lock, never recomputed while that lock exists; macOS sleep note |
| Rollback: v1.45.0 `load_state` requires exactly 5 keys (`totpd.py:150-151`) | should-fix | B3: `lock_level` written only when non-zero; Rollback section |
| Escalation to a permanent lock makes operator lockout worse | should-fix | Open questions 3 and 4 are dispatch blockers; Claude recommends a 24 h final level |
| B10 upgrade path: C1/C2 fail until the operator reruns the part-A install; non-purge uninstall must keep the KRL | should-fix | Upgrade order section; M8 + test for `bin/k3dm-web-console-sshd:739` |
| Scope too big for a patch | should-fix | v1.45.1 = lock escalation, log lines, RevokedKeys. Metrics, collector, Hermes hook, alerts → v1.46.0 |
| New reply word must reach the gate regex (`k3dm-console-gate.py:157`) and branch (`:338-352`) | nit | default design reuses `WAIT <n>`, so the gate is unchanged; `LOCKED` only if the operator picks a permanent level |
| Cite the hub's `sshd -V` | nit | External behaviour: m5-air `OpenSSH_10.2p1`, same tag as m4-air |

## What is wrong

- `scripts/libexec/k3dm-console-totpd.py:789-805`: 5 failures lock for 300 s (`:794`), then reset (`:744-770`); window ±1 step (`:173-187`).
  About 1,440 guesses a day at 3 in 10^6 each. Failed codes and locks are not logged (`log_event` call sites).
- No `RevokedKeys` in `scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl`; only the whole-console revoke.
- `:397` sets `totp.sock` to 0666 with 4 admit slots (`:515-525`). Defence-in-depth gap only (see B9); fixed in a follow-up.

## Fix direction (v1.45.1)

Escalating lock (5 min, 30 min, 4 h, then 24 h repeated), decaying one level per quiet day; a structured log line per
failure, lock, refused attempt and unlock; an admin `UNLOCK`; ten single-use recovery codes that unlock from the console
without root (B8); `RevokedKeys` in the template and the expected-lines list. Metrics, alerts, socket mode and
short-lived certs are follow-ups.

## Operator probe

`ssh-keygen -L -f <console cert>`: certificate validity period (open question 1).

## Files

| # | File | Change |
|---|------|--------|
| 1 | `scripts/libexec/k3dm-console-totpd.py` | escalating lock with a persisted `lock_level` (written only when non-zero); decay; monotonic in-process deadline set once per lock; `load_state` migration; structured log lines; admin `UNLOCK`; recovery codes (B8): `recovery.json`, VERIFY accepts the recovery format, rate limit, burn, admin `RECOVERY_*` verbs |
| 2 | `scripts/libexec/k3dm-console-gate.py` | **changed (rev 3):** line buffer cap 7 → 20 bytes (`:327-328`); the local format check (`:332`) also accepts a recovery code and sends it in canonical grouped form (B8 Wire). Reply regex `:157` and branches `:338-352` unchanged |
| 3 | `scripts/libexec/k3dm-console-totpctl.py` | `totpctl unlock`, `recovery-status`, `recovery-regen` (usage line `:37`, verb dispatch `:38-90`); enrol/rotate also print the ten recovery codes on `/dev/tty` |
| 4 | `scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl` | `RevokedKeys /etc/k3dm-web-console/revoked_keys` after `TrustedUserCAKeys` |
| 5 | `bin/k3dm-web-console-sshd` | expected-lines list (`_wc_render` `:25-75`); stage an empty KRL if absent (beside `_wc_stage_keys` `:464-474`); `_wc_dest_check` (`:149-151`), `_wc_files_healthy` (`:217-240`), dry-run plan (`:693`). The non-purge uninstall list (`:739`) is **not** changed: it already leaves `revoked_keys` in place; a test pins that |
| 6 | `docs/howto/web-console-totp.md`, `docs/howto/web-console-sshd.md` | unlock, revoke a cert, upgrade order, rollback step |
| T | `scripts/tests/bin/test_web_console_totp.py`, `scripts/tests/bin/web_console_sshd.bats` | tests below |

Six files, so the work is split (see Routing).

## Behaviour

**B1 Escalating lock.** `state.json` may carry `lock_level` (int 0–4). Five consecutive failures raise the level by one
(capped at 4) and lock for `LOCK_SECONDS[level-1]`, with `LOCK_SECONDS = [300, 1800, 14400, 86400]` under the
operator decision Q3. The fifth failure still replies `NO`; attempts while locked reply
`WAIT <remaining>`. At level 4 each further run of five failures re-locks for 86400 s (about 5 guesses a day). When a
lock expires, `failures` resets to 0 and **`lock_level` is kept**, so the next five failures escalate. A successful code, a
valid recovery code (B8), `totpctl unlock`, enrol or rotate resets `failures`, `locked_until` and `lock_level` to 0.

**Decay (Q4, operator 2026-11-23).** While no lock is active and `lock_level > 0`, the level drops by one for each full
86400 s since the last lock expired, applied at the next VERIFY and at daemon start. The anchor is `locked_until`
(wall seconds): after a lock expires it stays on disk while `lock_level > 0`, instead of being cleared. When the level
reaches 0 the state is written back in the 5-key form with `locked_until: 0`. Decay reads the wall clock, so a forward
jump can only lower the level toward the 300 s first lock; it never lifts an active lock (B2) or the five-failure lock
itself. Failures below five do not move the anchor (the anchor is "last lock", which the operator accepted as "a day with
no failure" closely enough: under five failures a day never locks).

Level 4 never becomes permanent (Q3): every attempt while locked replies `WAIT <n>`, and the gate's existing branch
(`:346-350`) shows "Too many attempts; try again later". No `LOCKED` reply exists.

**B2 Clock.** The running daemon enforces a lock against `monotonic()` with an in-process `lock_deadline_mono`, so a
wall-clock jump cannot shorten it. The deadline is **set once**:
- when the lock is imposed: `monotonic() + LOCK_SECONDS[level-1]`;
- at daemon start, if the loaded state has an active lock: `monotonic() + clamp(locked_until - clock(), 0, LOCK_SECONDS[level-1])`.

It is never recomputed while that lock exists. Per-request `load_state` (`:730`) still reads the file, but the deadline
is rebuilt only when `locked_until` on disk differs from the value the deadline was built for (a new lock, or an
unlock/enrol/rotate that cleared it). `locked_until` stays on disk as wall seconds, for restarts only. The clamp means
a forward-set wall clock at lock time cannot persist a lock longer than its level allows, and a backward jump across a
restart extends it by at most one duration.

Note: on macOS `time.monotonic()` does not advance while the machine sleeps, so a lock imposed before sleep runs for its
full awake duration after wake. That lengthens locks, never shortens them; accepted and stated in the guide.

**B3 State migration and rollback safety.** `load_state` accepts the old 5-key set (reads as `lock_level: 0`) or the
5-key set plus `lock_level`. Any other key set, a non-int or negative value, or `lock_level > 4` returns `False`
(state-unavailable), as today. **Writers include `lock_level` only when it is non-zero**; a commit at level 0 writes the
exact v1.45.0 5-key form. So a v1.45.0 daemon reads every state this version writes at level 0. See Rollback. Recovery
codes never enter `state.json`; they live in `recovery.json` (B8), which v1.45.0 does not read.

**B4 Unlock.** A new admin verb `UNLOCK` on `admin.sock` (still peer uid 0, 0600) replies `UNLOCKED` and commits the
reset (5-key form), or `NOT_ENROLLED` / `UNAVAILABLE`. `totpctl unlock` sends it and prints `unlocked`. It is root only,
like `status`.

**B5 Log lines.** `log_event` keeps the existing bare names and adds structured lines, one per event:
`<UTC ISO-8601> event=<name> key=value ...`. Events and fields:
- `totp-failure failures=<n> lock_level=<l>`
- `totp-lock lock_level=<l> seconds=<s|none>`
- `totp-locked-reply lock_level=<l>` (only on the first refused attempt per lock, so a loop cannot flood the log)
- `totp-unlock source=<admin|success|recovery|enrol|rotate|decay>` (`decay` when the level reaches 0 by decay)
- `totp-recovery-used remaining=<n>`; `totp-recovery-low remaining=<n>` (level WARN) when `n <= 2`
- `totp-recovery-failure`; `totp-recovery-rate-limited` (first refused attempt per 60 s window only)
- `totp-recovery-regen count=<n>`; `totp-recovery-damaged` (once per change of the file's load result)

No line ever carries the submitted code, the secret, a counter value, or a recovery code, salt or hash. Logging stays best-effort and never changes a
reply. In v1.45.1 these lines are the only record of an attack; alerting on them is the v1.46.0 follow-up.

**B6 Same-uid DoS, a limitation stated rather than fixed.** A peer whose uid is not `conf["uid"]` is closed before it
takes a pending slot (`totpd.py:508-514`, before the `pending_checks >= 4` check at `:515-520`), and `admit()` again
requires the gate chain under the console uid. So the 0666 mode lets another uid open a connection that is closed at
once; it cannot fill the 4 slots. The DoS the red team described needs a process running **as the console uid**, which
is the operator's own login uid (`bin/k3dm-web-console-totp:288`, `uid=$op_uid`) and can already do more than block
console login. No per-uid quota can separate the gate from that attacker. Socket 0600 is defence in depth (see
Follow-ups); open question 2 covers same-uid mitigations.

**B7 RevokedKeys.** The template and `_wc_render` gain `RevokedKeys /etc/k3dm-web-console/revoked_keys`. The file name
must differ from the existing whole-console marker `/etc/k3dm-web-console/revoked`: `_wc_files_healthy` requires that
marker to be **absent** (`bin/k3dm-web-console-sshd:220-222`), and `web_console_common.sh:129,212,217` parks the daemon
when it exists. The installer creates the file only if it is absent, as an empty KRL (`ssh-keygen -k -f <stage>/revoked_keys`,
root:wheel 0644). It treats the file like the host key: operator data, never overwritten on reinstall (an overwrite
would un-revoke) and not a manifest part-A row. A non-purge uninstall keeps it (the `:739` list names `revoked`, not
`revoked_keys`); `PURGE=1` removes it with the rest of `_WC_CONF_DIR` (`:740`). `_wc_files_healthy` fails if the file is
missing, a symlink, not regular, or not `0:0:644` through `_wc_file_mode` (`:132-137`). The installer refuses to activate a
config while the file is missing. Reason (External behaviour): sshd then refuses every key, and `sshd -t` does not
catch it. To revoke a cert: `ssh-keygen -k -u -f /etc/k3dm-web-console/revoked_keys <cert or spec>` (operator, root).

**B8 Recovery codes (operator decision, 2026-11-23).** Ten single-use codes give the operator a way in from the console,
without root on the hub, when locked out or without the authenticator.

- **Generation.** The daemon makes a pending set of 10 codes at `ENROLL_BEGIN`, `ROTATE_BEGIN` and a new
  `RECOVERY_BEGIN`, beside the pending secret (`totpd.py:577-588`, same 300 s pending window). Each code is
  `os.urandom(10)` as base32: 16 characters of `[A-Z2-7]`, 80 bits, shown as `XXXX-XXXX-XXXX-XXXX`.
- **Display.** totpctl's admin reply cap is 64 bytes (`totpctl.py:18-19`) and the daemon's admin request buffer is 32
  bytes (`totpd.py:559`), so the 10 codes (190 characters) cannot travel in one reply. A new verb `RECOVERY_GET <i>`
  (`i` = 0–9, pending set only) replies `CODE <grouped>` (24 bytes), or `UNAVAILABLE` when nothing is pending or the
  window expired. totpctl prints the codes once on `/dev/tty` after the secret, the way it prints the secret today
  (`totpctl.py:105-107`), never on stdout, in argv or in env, and clears the scrollback at the end as it already does
  (`:141`).
- **Storage.** Hashes only, in a separate file `<state_dir>/recovery.json`, root 0600 (owner `expected_dir_owner`),
  written with `commit_state`'s pattern (`totpd.py:100-139`: O_EXCL|O_NOFOLLOW tmp at 0600, fsync, `os.replace`, dir
  fsync; same pre-/post-rename error split). Format: `{"v": 1, "codes": [{"s": "<32 hex salt>", "h": "<64 hex
  sha256(salt || code)>"}]}`, 0–10 entries; a burned code's entry is removed. A salted SHA-256 is enough because each code
  carries 80 bits: a slow KDF adds nothing against an 80-bit search, would block the single-threaded select loop for
  every attempt, and `hashlib.scrypt` depends on the interpreter's OpenSSL build, which is not checked on the hub's
  CommandLineTools Python. `state.json` is untouched, so B3's rollback property holds.
- **Commit order.** `ENROLL_COMMIT` / `ROTATE_COMMIT` write `recovery.json` first, then `state.json`. If the state commit
  fails before the rename, the new codes are live and the old secret stays; totpctl already says "commit not confirmed;
  run web-console-totp-status" (`:147`) and the operator reruns rotate, which issues a fresh set. `RECOVERY_COMMIT` writes
  only `recovery.json` and replaces the whole set.
- **Load.** `load_recovery` gives "recovery unavailable" for a symlink, a non-regular file, a wrong owner, a mode other
  than 0600, any format deviation or more than 10 entries; a missing file means 0 codes (an existing enrolment after the
  upgrade, until the operator runs `recovery-regen`). A bad `recovery.json` **never** makes TOTP login unavailable: it
  only disables recovery and logs `totp-recovery-damaged`.
- **Wire.** Gate: line buffer cap 7 → 20 bytes (`:327-328`). Input is accepted if it is 6 digits, or if after uppercasing
  and removing hyphens it is 16 `[A-Z2-7]` characters; the latter is sent in canonical form, `VERIFY XXXX-XXXX-XXXX-XXXX`
  (26 bytes before the newline, inside the daemon's 31-byte line limit, `totpd.py:695`). Anything else stays the local
  "Invalid code" (`:332-336`). The echo stays off, so lowercase and missing hyphens are accepted to cut typing errors.
  Daemon VERIFY accepts exactly `[0-9]{6}` or `[A-Z2-7]{4}(-[A-Z2-7]{4}){3}`; anything else is the existing wire reject.
  The reply vocabulary is unchanged (`OK | NO | WAIT <n> | UNAVAILABLE`), so the gate regex `:157` and branches
  `:338-352` stay as they are.
- **Rate limit.** One recovery-format attempt per 60 s, locked or not, held in-process against `monotonic()`
  (`recovery_next_mono`). An attempt inside the window replies `WAIT <remaining>` and is not evaluated. Bound: 10 valid
  codes in 2^80 at 1,440 attempts a day is about 1.2×10^-20 per day. A daemon restart resets the window; restarts need
  root or a crash, and a crash loop is itself paced by launchd.
- **Verify.** The candidate is compared with every remaining entry with `hmac.compare_digest`, with no early exit.
  - Valid unused code: commit `recovery.json` without that entry (the burn) **before** replying; then commit `state.json`
    with `failures`, `locked_until` and `lock_level` at 0 (5-key form) and reply `OK`. `last_counter` is unchanged. If
    the burn fails before the rename: `UNAVAILABLE`, nothing reset, the code stays valid. If the state commit fails
    before the rename after the burn: `UNAVAILABLE` and the code is spent (fail closed). Post-rename failures keep
    today's fatal exit.
  - Wrong code while not locked: counts as a failure (`failures += 1`, may lock), reply `NO`.
  - Wrong code while locked: reply `NO`; the lock is unchanged (the 60 s window is the limit).
  - No codes left, or recovery unavailable: a recovery-format input is handled as a wrong code.
  - TOTP input while locked: `WAIT <n>`, as today.
- **Commands (root, peer uid 0 on `admin.sock`).**
  - `totpctl recovery-status` → `RECOVERY_STATUS` → `RECOVERY <n>` | `NOT_ENROLLED` | `UNAVAILABLE`; prints
    `recovery codes left: <n>` (or `not enrolled` / `recovery unavailable`).
  - `totpctl recovery-regen` → `RECOVERY_BEGIN` (`RECOVERY_PENDING` | `NOT_ENROLLED` | `REFUSED` while another admin
    operation is pending) → ten `RECOVERY_GET` → the operator types `yes` on the tty after saving them → `RECOVERY_COMMIT`
    → `OK` | `UNAVAILABLE`. Without `yes` totpctl sends `ABORT` and the old set stays. No TOTP code is asked: root at
    home already outranks the second factor.
- **Never in argv, env or logs.** The gate never logs the input line; totpd's log calls take no argument derived from the
  line; totpctl reads no code from argv. A source-scan test (extending `test_N6_and_N7_source_scan`) and a log scan after
  a recovery login check this, each paired with a positive control (`remaining=` is present).

## Upgrade order (after the release merges)

1. Operator: `make hub-deploy REF=<v1.45.1 tag>` (promote). Promote only moves the `deploy/hub` checkout; it runs no
   root step. Until step 2, the running console sshd keeps the installed v1.45.0 config, so **login keeps working**,
   but `make web-console-sshd-check` (`Makefile:656`) reports:
   - C2 FAIL: `_wc_check_config` (`bin/k3dm-web-console-sshd:158-163`) compares the installed `sshd_config` with the
     rendered new template, which now has the `RevokedKeys` line;
   - C1 FAIL: `_wc_files_healthy` now requires `revoked_keys`.

   Nothing else reads C1 or C2. `bin/k3dm-web-console-totp:140-150` (the part-A completeness check before a TOTP
   install) counts manifest rows by path and does not call `_wc_files_healthy`, so it is unaffected.
2. Operator, at home (sudo password): `make install-web-console-sshd`. It creates the empty KRL and the new config.
   The installer cannot create the KRL from a promote: every write under `/etc/k3dm-web-console` goes through `_wc_priv`
   (root). Reinstalling part A with part C installed is allowed when the port matches (`:396-401`).
3. Operator, at home: `make install-web-console-totp` to pick up the new totpd, gate and totpctl (part C reinstall; the
   repeat check at `bin/k3dm-web-console-totp:304-308` replaces changed files). Then
   `sudo /Library/PrivilegedHelperTools/k3dm-web-console/totpctl recovery-regen` and store the ten codes off the travel
   device. Until then the existing enrolment has no recovery codes (`recovery-status` reads 0).
4. Claude: L1 (read-only); operator: L2.

The release notes carry steps 2 and 3 as operator steps. Steps 2–3 need the operator at home
(`reference_operator_cannot_promote_from_office`), so the promote and both installs are batched in one ask.

## Rollback

v1.45.0's `load_state` refuses any key set other than its 5 keys (`totpd.py:150-151`) and then the gate replies
"console login unavailable" for every login. Because B3 writes `lock_level` only when non-zero, the hazard exists only
while a lock of level ≥ 1 is recorded. Rollback step, root on the hub, **before** reinstalling the old part C:
`sudo /Library/PrivilegedHelperTools/k3dm-web-console/totpctl unlock` (`_WC_HELPER_DIR`, `web_console_common.sh:4`) — it writes the 5-key form.
If the old version is already running and the console says unavailable: root removes the `lock_level` key from
`state.json` with a script that rewrites the file in place without printing it (the file holds the TOTP secret), or
runs `make uninstall-web-console-totp PURGE_SECRET=1` and re-enrols. The guide (file 6) carries both.

`recovery.json` is ignored by v1.45.0 (its `load_state` reads only `state.json`), so recovery codes are inert after a
rollback and live again after a re-upgrade, minus any burned. `PURGE_SECRET=1` removes it with the state dir
(`_wct_purge_state`, `bin/k3dm-web-console-totp:405-409`); a non-purge uninstall keeps it, like `state.json`.

## Contract readers

| Contract | Writers | Readers | Change |
|----------|---------|---------|--------|
| `state.json` key set | `totpd.py` commits at `:599`, `:643`, `:745`, `:776`, `:792` (via `commit_state` `:100-111`) | `load_state` `:141-160`; v1.45.0 `load_state` on rollback; test fixtures that seed 5-key state, `test_web_console_totp.py:154,251,351,408,754,852` | optional 6th key `lock_level`, written only when non-zero; 5-key still loads and is still written at level 0 |
| totpd reply vocabulary | `totpd.py` totp_client branch `:736-805` | gate `:157` (regex), `:338-351` (branches; unknown reply → "console login unavailable") | unchanged (`OK | NO | UNAVAILABLE | WAIT <n>`); recovery reuses `OK`, `NO` and `WAIT` |
| VERIFY request format | gate `verify_totp` `:112-162`, local check `:327-336` | totpd VERIFY branch (6-digit check, line limit `:695`); `test_N1_and_E1_wire_rejections` `:396`; `test_N12_and_E4_verifier_socket_not_in_child` `:835` | adds `VERIFY XXXX-XXXX-XXXX-XXXX` (`[A-Z2-7]`); 6 digits unchanged; every other form still rejected |
| admin verbs | `totpctl.py:42,78-79` | `totpd.py:572-664` | add `UNLOCK` → `UNLOCKED`; `RECOVERY_STATUS`, `RECOVERY_BEGIN`, `RECOVERY_GET <i>`, `RECOVERY_COMMIT` (B8); `RECOVERY_GET` also serves the set pending under `ENROLL_BEGIN` / `ROTATE_BEGIN` |
| `<state_dir>/recovery.json` (new) | totpd only: enrol/rotate/regen commit, burn on recovery login | totpd `load_recovery`; `_wct_purge_state` `bin/k3dm-web-console-totp:405-409` (removes the dir); v1.45.0 does not read it | new, root 0600, hashes only |
| totp log `/var/log/k3dm-web-console-totp.log` | `log_event` `:335-340` | `bin/k3dm-web-console-totp` (mode 0600, `:376`), `scripts/etc/launchd/com.k3d-manager.web-console-totp.plist.tmpl`, `scripts/tests/bin/web_console_totp.bats` | new structured lines appended; bare names kept |
| sshd_config line set | template; `_wc_render` `bin/k3dm-web-console-sshd:25-75` | sshd; `_wc_check_config` (C2) `:158-163`; `web_console_sshd.bats` render tests | add one line in both, same position; C2 fails between promote and reinstall (Upgrade order) |
| `/etc/k3dm-web-console/revoked_keys` (new) | sshd installer stage (beside `_wc_stage_keys` `:464-474`); operator `ssh-keygen -k -u` | sshd (`RevokedKeys`); `_wc_dest_check` `:149-151`; `_wc_files_healthy` `:217-240` → `_wc_check_files` (C1) `:327-334`; dry plan `:693`; uninstall `:739` (keeps it) and `:740` (purge removes it) | new; distinct from the `revoked` marker (`web_console_common.sh:129,212,217,495-497`; `bin/k3dm-web-console-sshd:150,220,330,381,406,544,563,739`), which is unchanged |
| `totp.sock` mode/owner | `totpd.py:394-398` | gate `:17,:113-145`; `test_N12_and_E4_verifier_socket_not_in_child` `:810` | **unchanged** in v1.45.1 (follow-up) |

## External behaviour

Proved on m4-air, 2026-11-23, `ssh -V` / `sshd -V` = `OpenSSH_10.2p1, LibreSSL 3.3.6`. The hub matches: m5-air,
2026-11-23, `ssh -o BatchMode=yes m5-air.local /usr/sbin/sshd -V` = `OpenSSH_10.2p1, LibreSSL 3.3.6` (macOS 26.5.1).
Upstream source is `openssh/openssh-portable` at tag `V_10_2_P1`, fetched with `gh api .../contents/<file>?ref=V_10_2_P1`.

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
  cannot catch a missing file, and B7 adds an explicit existence check.
- **Live, scratch key, `ssh-keygen -Q`:**
  - `ssh-keygen -k -f emptykrl` with no keys: rc 0, 44 bytes, and `-Q` reports `ok` (rc 0).
  - A KRL built from the key reports `REVOKED` (rc 1).
  - `-Q` itself only reads KRLs: an empty plain file gives "invalid magic number" (rc 255).
  - So the install creates a real empty KRL. sshd accepts it, `-Q` can audit it, and `-k -u` can extend it.
- **Not proven live:** sshd authenticating against the empty KRL. That is evidence L1 after the reinstall.

## Acceptance

```yaml
must:
  - id: M1
    text: five consecutive failures lock for 300 s, the next five after expiry for 1800 s, then 14400 s, then 86400 s; level stays 4 and each further five re-lock for 86400 s
  - id: M2
    text: a daemon restart keeps lock_level and the remaining lock, clamped to the level's duration
  - id: M3
    text: a correct code resets failures, locked_until and lock_level to 0
  - id: M4
    text: "`totpctl unlock` (admin UNLOCK, peer uid 0 only) and enrol/rotate clear the lock; a non-root admin peer is refused"
  - id: M5
    text: a 5-key state.json loads as lock_level 0; a commit at level 0 writes exactly the v1.45.0 5-key set; a commit at level >= 1 adds lock_level; extra keys, a negative or non-int lock_level, or lock_level > 4 are refused
  - id: M6
    text: each failure, lock, first refused attempt per lock and unlock writes one structured log line with no code, secret or counter value (positive control - the line exists)
  - id: M7
    text: the in-process lock deadline is computed once per lock (at imposition or at daemon start) and repeated loads during that lock do not change it
  - id: M8
    text: the rendered sshd_config and the _wc_render list both carry RevokedKeys /etc/k3dm-web-console/revoked_keys; install creates an empty KRL 0:0:644 only when absent; _wc_files_healthy fails when it is missing, a symlink or the wrong mode; a non-purge uninstall leaves it in place and PURGE=1 removes it
  - id: M9
    text: at level 4 totpd replies WAIT <n> and the gate's existing branch (:346-350) shows "Too many attempts; try again later" (positive control)
  - id: M10
    text: enrol, rotate and recovery-regen each produce 10 distinct 16-character base32 codes, readable only through RECOVERY_GET while pending; recovery.json is root 0600 and holds only salted SHA-256 hashes; state.json keeps the B3 key set
  - id: M11
    text: while locked, a valid unused recovery code replies OK, resets failures, locked_until and lock_level to 0, and is burned on disk before the reply; the same code a second time replies NO
  - id: M12
    text: recovery-format attempts are limited to one per 60 s against monotonic(), locked or not; an attempt inside the window replies WAIT <n> and is not evaluated; a wrong code while not locked counts as a failure, while locked leaves the lock unchanged
  - id: M13
    text: the gate accepts a recovery code grouped, ungrouped or lowercase and sends VERIFY XXXX-XXXX-XXXX-XXXX; 6-digit input is unchanged; other forms stay a local Invalid code; totpd VERIFY accepts exactly the two forms
  - id: M14
    text: totpctl recovery-status prints the remaining count; recovery-regen replaces the whole set only after the operator types yes (ABORT otherwise); both are refused to a non-root admin peer; a recovery login logs totp-recovery-used remaining=<n> and totp-recovery-low when n <= 2
  - id: M15
    text: with no active lock and lock_level > 0, the level drops by one per full 86400 s since the last lock expired; at 0 the state is the 5-key form with locked_until 0
must_not:
  - id: N1
    text: the second lock must not be 300 s (flat reset)
    red_on_current: current code resets to failures 0 and re-locks for 300 s (:744-748, :794)
  - id: N2
    text: a restart between locks must not drop the escalation level
    red_on_current: no lock_level exists; the next lock after restart is 300 s
  - id: N3
    text: a wall-clock jump forward while running must not shorten an active lock
    red_on_current: lock compares wall clock t_now < locked_until (:740); a +300 s jump unlocks
  - id: N4
    text: a failed attempt must not leave no totp-failure line in the log
    red_on_current: log_event is never called on NO (:789-805)
  - id: N5
    text: the rendered sshd_config must not lack a RevokedKeys line
    red_on_current: template and _wc_render have none
  - id: N6
    text: a reinstall must not replace an existing non-empty revoked_keys
    red_on_current: current install neither creates nor references the file, so the pre-seeded-KRL-and-referenced assertion fails
  - id: N7
    text: install must not activate a config referencing revoked_keys while the file is missing
    red_on_current: current healthy check passes with no revoked_keys
  - id: N8
    text: a locked-out operator typing a valid recovery code at the console must not be refused
    red_on_current: the gate rejects any input that is not 6 digits before contacting totpd (:332), so the code never reaches the daemon
  - id: N9
    text: a burned recovery code must not unlock a second time
    red_on_current: no recovery path exists; the test's first step (valid code -> OK) already fails
  - id: N10
    text: recovery-format attempts must not be evaluated more than once per 60 s
    red_on_current: totpd wire-rejects the recovery format, so the second-attempt WAIT assertion fails
  - id: N11
    text: no recovery code may appear in plaintext in recovery.json, state.json, the log or totpctl argv
    red_on_current: pre-fix has no recovery.json and no remaining= line, so the paired positive controls (10 hash entries; remaining= logged) fail
  - id: N12
    text: a damaged recovery.json must not make TOTP login unavailable
    red_on_current: pre-fix never logs totp-recovery-damaged, so the positive control paired with the TOTP-OK assert fails
evidence:
  - id: E1
    proves: [M1, M15, N1]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "escalat or decay"
    red_control: on pre-fix totpd the second lock reads WAIT 300, not WAIT 1800; the decay case reads lock_level after wall += 86400 past expiry and pre-fix has no lock_level
    intent: pending
  - id: E2
    proves: [M2, N2]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "restart_keeps_level"
    red_control: pre-fix restart leaves no lock_level; assertion on 1800 fails
    intent: pending
  - id: E3
    proves: [N3, M3, M7]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "monotonic or success_resets or deadline_once"
    red_control: VerifierFixture wall += 301 with monotonic unchanged unlocks pre-fix code; deadline_once advances wall between two requests during one lock and asserts the WAIT value follows monotonic only
    intent: pending
  - id: E4
    proves: [M4, M5]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "unlock or migration or level0_five_keys"
    red_control: pre-fix admin replies to UNLOCK with the unknown-verb path; a state with lock_level is refused by pre-fix load_state; level0_five_keys asserts the committed key set equals the v1.45.0 set after unlock
    intent: pending
  - id: E5
    proves: [M6, N4]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "structured_log"
    red_control: pre-fix log has no totp-failure line after a NO; code-absence assert paired with line-present control
    intent: pending
  - id: E6
    proves: [M9]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "level4_reply"
    red_control: pre-fix code never reaches level 4 (flat 300 s), so the WAIT 86400 assertion fails; the gate-message check is the positive control
    intent: pending
  - id: E8
    proves: [M10, N11]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "recovery_generate or recovery_storage or recovery_plaintext"
    red_control: pre-fix ENROLL_BEGIN pends no codes and RECOVERY_GET is an unknown verb; plaintext scans of recovery.json, state.json and the log are paired with the hash-count and remaining= positive controls
    intent: pending
  - id: E9
    proves: [M11, N8, N9]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "recovery_unlock or recovery_burn or gate_recovery_reaches"
    red_control: pre-fix gate prints Invalid code without connecting (stub verifier records no VERIFY line); pre-fix totpd wire-rejects; burn case asserts recovery.json lost the entry before the OK reply is read (commit fault injected after the burn -> UNAVAILABLE and entry gone)
    intent: pending
  - id: E10
    proves: [M12, N10]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "recovery_rate"
    red_control: two attempts 30 s apart on the monotonic seam; pre-fix wire-rejects both, so the WAIT 30 assertion fails; a third attempt at +61 s is the positive control
    intent: pending
  - id: E11
    proves: [M13]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "gate_recovery_input"
    red_control: GateProcess against a stub verifier socket; pre-fix gate sends nothing for grouped, ungrouped and lowercase input; 6-digit input sent unchanged is the positive control
    intent: pending
  - id: E12
    proves: [M14, N12]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_web_console_totp.py -k "recovery_status or recovery_regen or recovery_damaged"
    red_control: pre-fix totpctl has no recovery-status verb (unknown command, rc 1); damaged recovery.json case asserts TOTP OK plus a totp-recovery-damaged line (absent pre-fix)
    intent: pending
  - id: E7
    proves: [M8, N5, N6, N7]
    kind: offline
    command: bats scripts/tests/bin/web_console_sshd.bats -f "revoked_keys"
    red_control: pre-fix rendered config has no RevokedKeys; fake-root reinstall with a pre-seeded KRL fails the referenced-and-unchanged assert; the uninstall-keeps case pre-seeds the KRL and asserts presence after a non-purge uninstall and absence after PURGE=1
    intent: pending
  - id: L1
    proves: [M8]
    kind: live
    command: after operator promote and the two installs (Upgrade order); operator logs in once with cert + code; Claude reads `make web-console-sshd-check` (C1, C2 PASS), stat -f '%Su %Lp' of revoked_keys and ssh-keygen -Q -f revoked_keys <console cert> (read-only)
    red_control: login failure, C1/C2 FAIL or revoked_keys missing blocks the release PR
    intent: pending
  - id: L2
    proves: [M10, M11, M14]
    kind: live
    command: operator at home after Upgrade order step 3 runs sudo totpctl recovery-status (reads 10), logs in once at the console with one recovery code, reruns recovery-status (reads 9) and pastes the log's totp-recovery-used line; Claude reads the pasted output only (recovery.json is never printed)
    red_control: recovery login refused, count not 9, or a code visible in the pasted log blocks the release PR
    intent: pending
interface:
  totpd_reply: "OK | NO | UNAVAILABLE | WAIT <n>"
  verify_request: "VERIFY <6 digits> | VERIFY XXXX-XXXX-XXXX-XXXX ([A-Z2-7])"
  admin_verb: "UNLOCK -> UNLOCKED | NOT_ENROLLED | UNAVAILABLE; RECOVERY_STATUS -> RECOVERY <n> | NOT_ENROLLED | UNAVAILABLE; RECOVERY_BEGIN -> RECOVERY_PENDING | NOT_ENROLLED | REFUSED; RECOVERY_GET <0-9> -> CODE <grouped> | UNAVAILABLE; RECOVERY_COMMIT -> OK | UNAVAILABLE"
  cli: "totpctl unlock | recovery-status | recovery-regen"
  state_keys: "secret, last_counter, failures, locked_until, enrolled; lock_level only when non-zero"
  recovery_file: "<state_dir>/recovery.json, root 0600, {v: 1, codes: [{s: <32 hex>, h: <64 hex sha256(salt||code)>}]}, 0-10 entries"
  recovery_rate: "1 recovery-format attempt per 60 s (monotonic)"
  decay: "-1 level per full 86400 s since the last lock expired"
  lock_seconds: "[300, 1800, 14400, 86400]"
  sshd_line: RevokedKeys /etc/k3dm-web-console/revoked_keys
```

Test fixtures, for every child:
- Python tests use the existing `VerifierFixture` seams (`clock`, `monotonic`, `peer_cred_fn`, `expected_*_owner`) under
  `tmp_path`. Each fixture first asserts that `run_dir` and `state_dir` are under `tmp_path`. No test calls `os.chown`.
- Bats tests use `_WC_PREFIX` as a fake root and a scratch `HOME`. The first assert in each is that the prefix is under
  `BATS_TEST_TMPDIR`. Ownership is read through the existing `_wc_tool stat` stub (`web_console_sshd.bats:399-403`).
- `sudo` and `launchctl` stubs on `PATH` exit non-zero and record the call. Install targets run only against the fake
  prefix, never unstubbed.
- The existing `test_N1_and_M2_lockout_and_hmac_calls` asserts the flat reset (`:236`, `WAIT 300` at about `:305`). It
  is updated to the escalation, because that assertion is the bug.

**Intent approved:** operator, 2026-11-23

Rev 3 note: that approval covers E1–E7 and L1. E8–E12 and L2 (recovery codes, decay) are not yet approved; they
are approved on child A after the Fable + Argon review.

## Routing

More than 3 files, so the work splits into three child specs, one dispatch per file set:

| Child | Worker | Files | Evidence |
|-------|--------|-------|----------|
| A: lock, decay, clock, migration, log, unlock, recovery codes ([spec](../plans/v1.45.1-totp-a-lock-and-recovery.md)) | Luna | 1, 2, 3 + `test_web_console_totp.py` | E1–E6, E8–E12 |
| B: RevokedKeys | Luna | 4, 5 + `web_console_sshd.bats` | E7 |
| C: guide | Flash | 6 (unlock, revoke a cert, upgrade order, rollback, macOS sleep note) | doc review by Claude |

- A and B touch no common file and can run in parallel. C depends on the final reply/levels from A and the install
  behaviour from B; dispatch it after both land.
- Suggested order: B first (smallest, isolated), then A after review and intent approval of rev 3, then C.
- **A is one child, not split (rev 3).** It has three source files plus the test file. A split into A1 (lock, decay,
  unlock) and A2 (recovery) was weighed: both change `totpd.py` (state handling, VERIFY branch, admin verbs),
  `totpctl.py` and `test_web_console_totp.py`, so under one-dispatch-per-file they would run in sequence anyway, and A2
  would rebase onto A1's state and commit changes. One child with one reviewer pass is cheaper and safer. Operator to
  confirm with the intent approval.
- L1 runs after promote and the reinstalls and is done by the operator or Claude, not a worker; L2 is the operator's.

## Follow-ups (out of scope for v1.45.1)

**F1 Metrics and alerts → v1.46.0** (design kept from rev 1 so the next plan can start from it).
- totpd atomically rewrites `/var/db/k3dm-web-console-run/totp-metrics.prom` (tmp + `os.replace` in `run_dir`,
  root:wheel 0644) after each failure, lock, unlock and at startup, with `k3dm_console_totp_failures_total`,
  `_locks_total`, `_unlocks_total`, `_lock_level`, `_metrics_written_timestamp_seconds`. Counters in memory, `lock_level`
  from state. totpd itself does no network I/O.
- `bin/k3dm-console-totp-metrics` (new; pattern `bin/k3dm-disk-metrics:93-108`) PUTs the file to
  `${K3DM_CONSOLE_TOTP_PUSHGATEWAY_URL:-http://localhost:19094}/metrics/job/k3dm-console-totp`; missing file → exit 0
  with a stderr line. `bin/k3dm-hermes` gains `_publish_console_totp_metrics()` next to `_publish_disk_metrics()`
  (`:881-891`, call site `:1050`).
- `scripts/etc/prometheus/rules/web-console-totp.yaml` (synced by `prometheus-rules-hub.yaml:31-34`):
  `ConsoleTotpLocked` (warning, any lock in 1 h or level ≥ 2) and `ConsoleTotpReenrolRequired` (critical, level 4 —
  rename if level 4 stays timed).
- Contract rows for the metrics file (reader: uninstall `rm -rf` of `run_dir`, `bin/k3dm-web-console-totp:493`) and the
  Pushgateway job move with it.

**F2 Socket 0600 (defence in depth).** Not a simple bind-time chown:
- `conf` is parsed inside the loop (`totpd.py:427-428`) and is `None` until the first good parse, so the console uid is
  unknown at bind time. A root-owned 0600 socket refuses the gate (it connects as the console uid, `gate :113-145`) and
  locks every login.
- A design must reconcile ownership in the loop: root 0600 while `conf` is `None`, then `chown(conf uid, -1)` + 0600
  once parsed, and re-chown if `totp.conf` changes uid (a re-enrol under another operator uid), with a test seam for the
  chown (the fixture uid cannot `chown` to group 0).
- Benefit is small (B6): other uids are already closed before taking a slot. File as a P3 at the next grooming.

**F3 Short-lived certs** — open question 1.

## Open questions

1. **Short-lived certs.** The operator probe (`ssh-keygen -L -f <console cert>`) has not been run, so the current
   validity period is unknown. If it is long (months), RevokedKeys becomes the only way to cut off a lost device.
   Proposal: a separate plan for CA-side issuance with `-V +1d` (or the trip length) plus a renewal path. Decision for
   the operator: the target validity, and roadmap placement. Does not block dispatch.
2. **Same-uid DoS (B6).** Accept it as a documented limitation (recommended), or add a later mitigation, such as cutting
   the 5 s admitted deadline or a per-peer-pid pending cap? Neither stops a same-uid attacker who forks. Does not block
   dispatch.
3. **Final level — DECIDED 2026-11-23 (24 h timed, see Operator decisions).** `totpctl unlock` needs root on the hub. From an iPad on travel, a
   permanent lock means no console until home. **Claude's recommendation: level 4 is a 24 h timed lock, repeated per
   five failures, not permanent.** It keeps the travel case recoverable (wait a day), still caps guessing at about 5 a
   day (≈1.5×10^-5/day), and needs no new reply word, so the gate is unchanged. The cost: no hard stop; detection is the
   log line until F1. Operator to confirm or choose permanent.
4. **Escalation memory — DECIDED 2026-11-23 (decay, see B1).** `lock_level` resets only on success, unlock, enrol or rotate.
   Should it also decay, for example one level per 24 h with no failure? Without decay, typo sprees months apart keep
   climbing toward the 24 h level. With decay, an attacker who pauses 24 h between bursts drops a level each time, but
   that pacing already limits them to about 5 guesses a day, the same rate as level 4, so decay costs little security.
   Claude leans to decay; operator decision. The answer adds one line to B1 and one evidence case to E1.

## Operator decisions (2026-11-23)

- Q3: final level is a 24-hour timed lock (`LOCK_SECONDS = [300, 1800, 14400, 86400]`), reusing `WAIT <n>`.
- Q4: the lock level decays (Claude's recommendation, accepted).
- New request: an unlock path from the console that does not need root on the hub. Child B (RevokedKeys) can dispatch now.
- Unlock without root: **recovery codes** (operator chose "Recovery codes (Recommended)"). Ten single-use 80-bit codes,
  hashes only in `recovery.json`, one attempt per 60 s, burned before the reply, regenerated by root `totpctl
  recovery-regen` (B8). Design goes to Fable + Argon review before intent approval; child A waits for both.
