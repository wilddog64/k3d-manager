# Bug: ask-bash runs an interpreter when its name is respelled

**Status:** OPEN — filed 2026-11-09, intent approval pending
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-09
**Introduced by:** f68bdee1 (2026-08-03, the interpreter deny line)
**Should have been caught by:** unknown
**Prior art:** not run (`make find-similar-docs` could not reach its vector store from the M4, 2026-11-09); exact-slug glob found nothing; read `docs/bugs/2026-10-08-ask-bash-shell-string-bypasses-path-scope.md` and `docs/bugs/2026-11-08-ask-bash-interpreter-deny-matches-repository-path.md`, different defects in the same file
**Severity:** medium — an `/ask` agent can run an interpreter it is meant to be denied; the macOS sandbox still refused a HOME read
**Approval:** operator, 2026-11-09 ("go ahead to file a P2 bug then dispatch to Flash")
**Intent approved:** pending
**Filed:** 2026-11-09
**Detected by:** independent verifier's break-it pass on `b98cff7e`, 2026-11-09
**Affected:** `bin/k3dm-ask-bash`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

Through `bin/k3dm-ask-bash -c COMMAND`, these ran and printed their output on the M4, 2026-11-09, with exit 0:
`py''thon3 -c ...`, `pyth\on3 -c ...`, `/usr/bin/pyth?n3 -c ...`, `no''de -e ...`, `pe''rl -e ...`, and `<root>/pyth*`
where the glob expands to a program named `python3`. Plain `python3` is denied.

The same commands pass on the script before `b98cff7e`, so that fix did not cause this.

With the default OS sandbox on, the bypassed interpreter was refused a read of a file under `HOME`
(`PermissionError: Operation not permitted`). With `K3DM_ASK_OS_SANDBOX=0` the same read succeeded.

## Root cause

`bin/k3dm-ask-bash:95` greps the raw command text. Bash removes quotes and backslashes and expands globs afterwards,
so the text checked is not the program that runs. More patterns cannot close this.

## Fix

Add a deny rule to the `sandbox-exec` profile, which judges the program actually being executed:

    (deny process-exec (regex #"/(python[0-9.]*|Python|perl[0-9.]*|ruby[0-9.]*|node|deno|bun|osascript|php[0-9.]*|lua[0-9.]*|tclsh[0-9.]*|Rscript|gdb|lldb)$"))

Put it in `_profile` (`bin/k3dm-ask-bash:243`), after the existing rules. Escape the `$` so bash does not expand it.

Tests go in `scripts/tests/bin/ask_bash_scope.bats`. They must run with the sandbox on, so do not set
`K3DM_ASK_OS_SANDBOX=0` in them. Use scratch roots under `TEST_ROOT` and scratch `HOME`, asserted first.

## Files

- `bin/k3dm-ask-bash`
- `scripts/tests/bin/ask_bash_scope.bats`

## Do not

- Remove or change the text deny on line 95, or any other deny pattern. It still gives the clear `Blocked` message.
- Add more text patterns for quoting, backslashes or globs.
- Remove `K3DM_ASK_OS_SANDBOX`, or change its default.
- Restrict file writes or exec from writable directories. See Known limits.

## Known limits (not fixed here)

- A renamed copy of an interpreter still runs: `/usr/bin/perl` copied to `harmless` printed its output under this rule
  (M4, 2026-11-09). A Homebrew `python3` copy failed only because of its framework path. Closing this needs write or
  exec limits on `/tmp` and similar directories, which is a larger change to what `/ask` may do.
- The rule exists only on macOS. On Linux, or with `K3DM_ASK_OS_SANDBOX=0`, only the text check applies.

## Contract readers

No shared contract changes: arguments, environment and the allow/deny result stay the same, except that a respelled
interpreter now exits 126 instead of running. Callers: `bin/k3dm-webhook:2901` and `scripts/lib/webhook/agent.py:379`,
neither changes.

## Proof of external behaviour

M4, macOS 26.5.2, 2026-11-09, `/usr/bin/sandbox-exec` with `(allow default)` plus the rule above:

- Denied, rc 126, `Operation not permitted`: `py''thon3`, `/usr/bin/pyth?n3`, `pe''rl`, `no''de`, `/usr/bin/rub?`,
  `osa''script`, a symlink named `harmless` to Homebrew `python3`, and executable scripts with a perl or python shebang.
- Still rc 0 with normal output: `git`, `kubectl` 1.37.2, `helm` 4.3.1, `argocd` 3.6.1, `ls`, `cat`, `grep`, `jq`, `yq`.

## Acceptance

```yaml
must:
  - id: M1
    text: "with the OS sandbox on, reading a file inside the repository root through ask-bash exits 0 and prints the file"
  - id: M2
    text: "with the OS sandbox on, a non-interpreter program in the repository root runs, exits 0 and prints its output, including when its name is written with quotes"
must_not:
  - id: N1
    text: "with the OS sandbox on, an interpreter named with quotes inside the name runs (py''thon3, pe''rl, no''de)"
  - id: N2
    text: "with the OS sandbox on, an interpreter named with a backslash inside the name runs (pyth\\on3)"
  - id: N3
    text: "with the OS sandbox on, an interpreter reached by a glob runs (/usr/bin/pyth?n3, or a glob matching a program named python3 inside the root)"
  - id: N4
    text: "with the OS sandbox on, a script whose shebang names an interpreter runs"
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3, N4]
    kind: offline
    intent: "tests run the real ask-bash inside the real macOS sandbox against scratch folders: interpreters written in disguise (split with quotes, a backslash or a wildcard) are refused and print nothing, while reading files and running ordinary programs still work"
interface:
  - "bin/k3dm-ask-bash -c COMMAND, with HOME, K3DM_REPO_ROOT and K3DM_SHOPPING_CARTS_ROOT set by the caller and K3DM_ASK_OS_SANDBOX unset, on macOS"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run `bats scripts/tests/bin/ask_bash_scope.bats`. Give the command, exit code and every error line. Do not run
   `make test`, `make test-bin` or `make test-pytest`.
2. Nested `sandbox-exec` may be refused inside your own sandbox. If so, say so and name the tests affected. Do not
   skip them, weaken them, or set `K3DM_ASK_OS_SANDBOX=0` to get a pass; Claude reruns them outside.
3. For each `must_not`: remove the rule, show its test red, restore it, show it green. If the sandbox stops you, say so.
4. List every place where you chose something the spec did not decide.

## Notes

No live evidence: the tests run the real script in the real sandbox on the same host type as the webhook.
