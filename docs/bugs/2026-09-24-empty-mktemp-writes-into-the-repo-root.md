# Bug: an unchecked `$(mktemp)` silently writes test and job files into the repo root

**Branch:** `k3d-manager-v1.37.0`
**Filed:** 2026-09-24 by Claude
**Status:** OPEN — root cause confirmed by measurement; fix specced below, not applied

## Symptom

Three untracked files appeared in the repository root during a test run:

```
.join-failures.38822    9 bytes   "ubuntu-2"    2026-09-24 09:19:23
.join-failures.55968    9 bytes   "ubuntu-2"    2026-09-24 09:20:41
.pub                    0 bytes                 2026-09-24 09:17:49
```

Nothing failed. No test went red, no error was printed, and the suite reported
**1237 ok / 0 not ok**. The files were noticed only because `git status` showed them.

## Root cause — one mechanism, two sites

`$(mktemp)` returns an **empty string** when it cannot create a file (an unwritable or
missing `TMPDIR`), and it does so on a path that no caller checks. Every path derived from
that empty value loses its directory and becomes **relative to the current working
directory**, which during a test run is the repo root.

### Site 1 — `.join-failures.<pid>`

`scripts/tests/plugins/shopping_cart.bats:223`

```bash
_k3sup_join_agents_parallel ubuntu-1,ubuntu-2,ubuntu-3 server "$(mktemp)"
```

reaches `scripts/plugins/shopping_cart.sh:1227-1232`

```bash
function _k3sup_join_agents_parallel() {
  local hosts_csv="$1" server_ip="$2" local_kubeconfig="$3"
  local failure_file="${local_kubeconfig}.join-failures.$$"
  ...
  : > "${failure_file}"
```

With `$3` empty, `failure_file` is `.join-failures.$$` and `: >` creates it in the CWD.
The content confirms the attribution exactly: the test at line 221 stubs
`_k3sup_join_agent() { [[ "$1" != ubuntu-2 ]]; }`, so `ubuntu-2` is the one host that
fails and gets recorded — and both stray files contain precisely `ubuntu-2`.

### Site 2 — `.pub`

`scripts/tests/lib/k3s_oci_provider.bats:237-238`

```bash
_OCI_SSH_KEY=\"\$(mktemp)\"
touch \"\${_OCI_SSH_KEY}.pub\"
```

With `mktemp` empty, this is `touch ".pub"` in the CWD — which matches the observed
0-byte file.

### Why it appeared now and not before

The 09:17–09:20 window is a `make test-all` run inside a **sandboxed `codex exec`**, where
`/var/folders` was not writable; that run reported `mktemp` permission failures. A normal
run on the operator's shell does not reproduce it, which is exactly why this has gone
unnoticed: **the failure mode is invisible on the machine where the tests usually run.**

## Why this matters more than three stray files

1. **It is silent.** An unwritable `TMPDIR` produces no error, no red test and no log line —
   just files in the wrong place and assertions that pass for the wrong reason. A test that
   writes to and reads back `.join-failures.$$` in the repo root still passes.
2. **It leaks across tests.** A CWD-relative path is shared by every test in the run, so two
   tests can collide, and state survives `teardown()` because the cleanup removes a temp dir
   that was never used. The PID suffix is the only thing that prevented a collision here.
3. **One `git add -A` from being committed.** This is part of why that command is banned in
   this repo — but the ban is a mitigation, not a fix.
4. **The production function is also wrong, not just the test.**
   `_k3sup_join_agents_parallel` accepts an empty kubeconfig and writes to the CWD rather
   than refusing. On a real host that is a write into whatever directory the operator
   happened to be in.
5. **This is a known class here.** The memory-bank already tracks *six remaining
   `_vault_hdr=$(mktemp)` sites* as an open item. Same unchecked call, higher stakes: those
   hold Vault request headers.

## Fix (proposed, NOT applied)

Three parts. The third is what stops recurrence.

**F1 — make the production function refuse an empty base.** In
`_k3sup_join_agents_parallel`, fail fast rather than deriving a relative path:

```bash
  if [[ -z "${local_kubeconfig}" ]]; then
    _err "[shopping-cart] _k3sup_join_agents_parallel requires a kubeconfig path"
    return 1
  fi
```

Guard the argument, **not** the symptom — do not "fix" this by prefixing a temp dir, which
would hide a caller passing nothing.

**F2 — stop the tests depending on `mktemp` at all.** BATS already provides
`BATS_TEST_TMPDIR`, which is created for you and removed after the test. Replace
`"$(mktemp)"` with `"${BATS_TEST_TMPDIR}/<name>"` in both sites. That removes the failure
mode instead of detecting it, and it is strictly less code.

There are **10** `mktemp` uses in `scripts/tests/plugins/shopping_cart.bats` alone; sweep the
file rather than fixing only line 223, and check
`scripts/tests/lib/k3s_oci_provider.bats` for the same.

**F3 — a repo-root cleanliness gate, so this cannot regress silently.** A test that asserts
`git status --porcelain` produces no new untracked entries in the repo root after the suite
runs. Without F3, F1 and F2 fix today's two sites and the next unchecked `$(mktemp)`
reintroduces the class.

Implement F3 as a check over the tracked tree, not a `git` call inside a BATS test (which
would be slow and order-dependent): assert that no file matching `.join-failures.*`, `.pub`,
or a bare dotfile-with-pid shape exists at the repo root, and wire it where
`make check-doc-links` already runs.

### Verification

- Reproduce before fixing: run the affected tests with `TMPDIR=/nonexistent` and confirm the
  stray files appear and the suite still reports green. **A fix is not proven until the
  pre-fix reproduction is demonstrated**, because the tests pass either way — that is the
  whole defect.
- Then confirm the same command produces no repo-root files and the suite is still green.
- Mutation-check F3 by `touch .join-failures.999` and confirming the new gate fails.

## Out of scope

- The six `_vault_hdr=$(mktemp)` sites. Same class, different blast radius, and they touch
  Vault request headers — they need their own spec and their own verification.
- The three stray files currently in the working tree are the operator's to remove; they are
  untracked and harmless. Do not delete them as part of a fix commit.
