# Bug: `producer | grep -q` under pipefail reports a present match as absent

**Status:** LIVE-VERIFIED — 2026-10-18: after `make refresh CLUSTER_PROVIDER=k3s-hostinger` installed the fixed sweep (2790 bytes, pre-fix 2770) at about 19:10Z, its first run at about 19:22Z left the host pod IP pool unchanged (45/254 used, 0 stale removed, 0 allocation errors, probe up). Offline: fixed `0fc16826`, 104/104 sites, guard BATS 2/2, N1/M3 red on pre-fix, touched suites 420/420. The first close as "no live surface" was wrong (see Live verification)
**Priority:** P3
**Fix commit:** `0fc16826`
**Approval:** approved — operator, 2026-10-18: "others please dispatch to codex" (v1.43.4 bug)
**Found:** 2026-10-17, by the independent acceptance verifier for e2e-sandbox-provision

## Symptom

`kubectl config get-contexts -o name | grep -qx -- "$ctx"` intermittently said `ubuntu-k3s` was
absent right after it was created. The verifier's harness failed 3 of 59 full-suite runs (M2 once,
M1b twice), each time with the call log showing the context listed and then reported missing.

## Root cause

`grep -q` exits on its first match. When the producer writes anything after that line, the write
hits a closed pipe, the producer dies with SIGPIPE (rc 141), and `pipefail` turns the pipeline's
status into a failure. The `if ! ...` reads that as "no match". It is a race: it fires only when
the producer is still writing after grep has exited, so it passes most of the time.

`scripts/plugins/e2e.sh` sets `set -euo pipefail` at top level, so every plugin sourced into the
same dispatcher shell after it also runs under pipefail — a file without its own `pipefail` line
is not safe on that basis. Most `bin/` scripts set it themselves.

## Fix pattern

Let grep read to EOF instead of exiting early:

    producer | grep -x -- "$x" >/dev/null

or capture first: `out="$(producer)"` then match against `$out`.

Regression test shape (deterministic): stub the producer as a shell function that prints the match,
`sleep 0.3`, then prints another line. Under `grep -q` the second write always hits a closed pipe.
See the two "more contexts follow it in the listing" tests in
`scripts/tests/plugins/e2e_sandbox_preflight.bats`.

## Remaining scope

As of 2026-10-18, `grep -rn '| *grep -q' scripts bin` (excluding `scripts/tests/` and
`node_modules`) finds 105 occurrences in about 30 files. A per-site audit of "can the producer
write after the match" is slower and riskier than converting every site, and the conversion is
behaviour-preserving: `grep -q` and `grep … >/dev/null` give the same exit status; the only
difference is that the second reads its input to EOF. So the fix converts every site except
the exclusions below.

The highest-stakes site is `scripts/etc/hostinger/k3dm-cni-ipam-sweep.sh` lines 44 and 48 (a
false "absent" there would delete a live pod's IP reservation). It is safe today only because the
whole `printf` fits in one pipe-buffer write; convert it like the rest.

## Fix

1. In every file under `scripts/` and `bin/`, except the exclusions, rewrite each pipeline
   `PRODUCER | grep -q<flags> ARGS` to `PRODUCER | grep -<flags-without-q> ARGS >/dev/null`.
   Keep every other flag and argument exactly (`-qx` → `-x`, `-qE` → `-E`, `-qxF --` → `-xF --`,
   bare `-q` → no flag). If the site already redirects stderr (`2>/dev/null`) keep it. Where grep
   ends a `&&`/`||` chain or sits in `if`, only the grep words change.
2. **Exclusions — do not edit:**
   - `scripts/lib/foundation/` (lib-foundation subtree; list its sites in the report for an
     upstream follow-up).
   - `scripts/tests/` (test code).
   - `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl` and `scripts/etc/e2e/redis.yaml`: these run
     in container `/bin/sh` without `pipefail`, so they cannot misfire.
   - Any site whose producer streams forever (`-f`, `--follow`, `--watch`, `tail -f`): converting it
     would hang. The 2026-10-18 scan found none; if Codex finds one, leave it and list it.
3. Add `scripts/tests/fixtures/grep-q-pipe-allowlist.txt`, one `path` per line, listing the two
   container files above (and any streaming site from step 2).
4. Add `scripts/tests/lib/grep_q_pipe_guard.bats`:
   - Guard: `grep -rnE '\| *grep +-[A-Za-z]*q' scripts bin` (excluding `scripts/tests/`,
     `scripts/lib/foundation/`, `node_modules`, and allowlisted paths) finds nothing.
   - Behaviour: the deterministic SIGPIPE shape from the e2e tests (producer prints the match,
     `sleep 0.3`, prints another line; `set -o pipefail`) — `producer | grep -x match >/dev/null`
     succeeds every time across 5 iterations.
   - CNI sweep: run `scripts/etc/hostinger/k3dm-cni-ipam-sweep.sh`'s existing BATS suites unchanged.
5. If a converted site lives in a file that ships to a host (the CNI sweep script), note in the
   report that the operator must reinstall it with `make refresh CLUSTER_PROVIDER=k3s-hostinger`.

## Acceptance

```yaml
must:
  - id: M1
    text: Outside scripts/tests/, scripts/lib/foundation/, node_modules and the allowlist, no file under scripts/ or bin/ contains a pipeline into grep with a -q flag.
  - id: M2
    text: Every converted grep keeps its other flags, pattern and arguments, and redirects stdout to /dev/null.
  - id: M3
    text: grep_q_pipe_guard.bats exists, passes, and fails if a new "| grep -q" is added to a non-allowlisted file.
  - id: M4
    text: The full make test suite and make test-pytest pass with no new failures versus the pre-fix branch.
must_not:
  - id: N1
    text: Under pipefail, a pipeline whose producer writes after the matching line must not report the match absent (the guard's behaviour test is red when its pipeline uses grep -q).
  - id: N2
    text: No file under scripts/lib/foundation/, scripts/tests/ (other than the new guard and fixture), or the allowlist changes.
  - id: N3
    text: No converted site prints grep's matching lines to stdout or the terminal.
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3]
    kind: offline
    text: bats scripts/tests/lib/grep_q_pipe_guard.bats plus the suites for every touched file (CNI sweep, e2e preflight, k3s providers), shellcheck on every touched shell file, make test and make test-pytest; N1 shown red by pointing the behaviour test at a grep -q pipeline; M3 shown red by a temp copy containing a new grep -q.
interface:
  - Shell pipelines of the form PRODUCER | grep -q… under scripts/ and bin/
  - scripts/tests/fixtures/grep-q-pipe-allowlist.txt
```

## Definition of Done

- [ ] E1 green; red demonstrations pasted; `git diff --stat` lists only converted files, the allowlist and the guard test.
- [ ] Report lists: converted-site count per file, the lib-foundation sites left for upstream, and any streaming site skipped.
- [ ] Commit message verbatim: `fix: read grep matches to EOF so pipefail cannot turn SIGPIPE into a false miss`
- [ ] Pushed to `origin/k3d-manager-v1.43.4`; memory-bank updated with the SHA.

## What NOT to Do

- Do NOT create a PR, merge, or commit to `main`. Do NOT use `--no-verify`.
- Do NOT change any other part of a line, refactor surrounding code, or "fix" unrelated issues found on the way.
- Do NOT modify `scripts/lib/foundation/`. Do NOT run anything against a host or cluster.

## Live verification

Correction, 2026-10-18: this was first closed as having no live surface. Two converted sites are
in `scripts/etc/hostinger/k3dm-cni-ipam-sweep.sh`, the CNI IP-reservation sweep that a systemd
timer runs on the Hostinger node. That copy is installed by `make refresh
CLUSTER_PROVIDER=k3s-hostinger` and is not touched by a merge, so the host still runs the
pre-fix `grep -q` lines until the operator reinstalls it.

1. Operator: `make refresh CLUSTER_PROVIDER=k3s-hostinger` from the v1.43.5 branch.
2. Evidence: the installed `/usr/local/sbin/k3dm-cni-ipam-sweep` matches the repo file
   (checksum), and the next timer run records a fresh `cni-ipam-sweep.state` with no release of
   a reservation that belongs to a running pod. The Hermes CNI IPAM publisher already reads that
   state file, so the CNI panels show the run.
3. Then set Status to `LIVE-VERIFIED` with the date and the evidence.

## Live evidence

**Live evidence:** 2026-10-18 · run cni-ipam-sweep-20261018T1922Z · env ubuntu-hostinger · scenario post-install-sweep · commit 0fc16826 · proves fix

- `make refresh CLUSTER_PROVIDER=k3s-hostinger` copied `k3dm-cni-ipam-sweep.sh` at 2790 bytes,
  the fixed size; the pre-fix file is 2770.
- Grafana "k3dm Host Pod IP Pool" at 19:28:54Z: "Since last sweep" 6.62 min, so the sweep ran at
  about 19:22Z. The previous run, at about 19:08Z, came before the install.
- Reservations 45 used of 254 (17.7%), unchanged across the run. "Stale reservations removed per
  sweep" stayed at 0, so no live pod's reservation was released. Allocation errors (1h): 0. Probe:
  up.
