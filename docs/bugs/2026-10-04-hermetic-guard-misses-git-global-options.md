# Bug: the hermetic pytest guard misses remote git behind `-C`, `-c`, an absolute path, or a named remote

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED — Codex, verified by Claude 2026-10-04. Claude changed `cwd = kwargs.get("cwd",
os.getcwd())` to `kwargs.get("cwd") or os.getcwd()`: callers that pass `cwd=None` broke the new path
resolution (6 `test_e2e_bugs.py` reds that Codex reported as pre-existing; they were not). 14 guard
tests; Codex's 4 mutations plus Claude's (`-c` as a one-word flag) each turn a test red.

The guard also caught `test_pager.py::test_failed_poll_pages_job_failure_and_reraises` reading the
real Keychain through `_sms_keychain`. It passed under `make test-pytest` only because the tripwire's
`security` stub is allowed. The test now stubs `_sms_keychain`.
**Severity:** low. No current test is known to reach the network this way. But the guard reports
"hermetic" when it cannot see these calls, so a future test could reach GitHub and the guard would
not stop it.

## Observed

Found while verifying `scripts/tests/conftest.py` (`967b1636`, python-agent-rigor brief B).
`_git_remote_violation` works out the git subcommand as the first word after `git` that does not
start with `-`:

```python
subcommand = next((word for word in words[1:] if not word.startswith("-")), "")
```

Four calls get past it:

| Call | What the guard does | Why |
|---|---|---|
| `git -C <repo> fetch` | allows it | the subcommand is taken to be `<repo>`, which is not in `HERMETIC_GIT_COMMANDS` |
| `git -c user.name=x push` | allows it | the subcommand is taken to be `user.name=x` |
| `/usr/bin/git ls-remote https://…` | allows it | `words[0] != "git"`, so the check returns at once |
| `git fetch upstream`, where only `upstream` is a network URL | allows it | only `remote.origin.url` is looked up |

The guard also looks up the remote URL in the Popen `cwd`, not in the `-C` directory. Even with the
subcommand found, `git -C <network-repo> fetch` run from a local-only directory would pass.

## Fix spec

### File 1 — `scripts/tests/conftest.py`

1. **Match git by basename.** `_git_remote_violation` accepts `words[0]` when
   `os.path.basename(words[0]) == "git"`, so `/usr/bin/git` is covered.
2. **Parse git's global options.** Add `_git_parse(words, cwd)`. It returns
   `(subcommand, index, effective_cwd)`. It walks `words[1:]`:
   - `-C <dir>`: consume both words. `effective_cwd` becomes `<dir>`, resolved against the previous
     `effective_cwd` when it is relative. Repeated `-C` options chain, as they do in git.
   - `-c <name=value>`, `--git-dir <path>`, `--work-tree <path>`, `--namespace <name>` and
     `--config-env <name=envvar>`: consume both words.
   - Any other word starting with `-` (including the `--opt=value` forms): consume one word.
   - The first word that does not start with `-` is the subcommand. `index` is its position in
     `words`.
   - No subcommand: return `("", -1, effective_cwd)`.
3. **Use the parse result.**
   - Use `index` for the `clone` source, `words[index + 1]`, instead of `words.index(subcommand)`,
     which can match an earlier word.
   - The URL check (`any(_is_remote_url(...))`) looks only at `words[index + 1:]`.
   - Pass `effective_cwd` to the remote lookup.
4. **Named remotes.** `_remote_url(cwd)` becomes `_remote_url(cwd, name="origin")` and reads
   `remote.<name>.url`. For `fetch`, `pull`, `push` and `ls-remote`, the remote name is the first
   word after `index` that does not start with `-`. Use it when `git config --get remote.<name>.url`
   returns a value, and fall back to `origin` otherwise. A URL in that position is already handled
   by the URL check.
5. Keep `_remote_url` on `_ORIGINAL_POPEN_INIT`, so the lookup itself is never guarded or recursive.
   Change nothing else: not `HERMETIC_BLOCKED`, the network rule, the modes, the report summary,
   or the error message format.

### File 2 — `scripts/tests/bin/test_hermetic_guard.py`

Add these tests. The existing 8 stay unedited and green. Build fixture repos in `tmp_path` with
`git init` and `git remote add`. Set the network remote URL to `https://example.invalid/x.git`.
Use a bare repo in `tmp_path` as the local remote. A blocked call must raise before anything
executes, and an allowed call must touch only local paths.

1. `git -C <net_repo> fetch`, with `cwd` set to a local-only repo → raises, matching `git-remote`.
2. `git -C <local_repo> fetch`, where `origin` is a bare repo in `tmp_path`, and the Popen `cwd` is
   a directory whose `origin` is the network URL → runs, exit 0. This proves the `-C` directory is
   used, not the `cwd`.
3. `git -c user.name=x push`, with `cwd=<net_repo>` → raises.
4. `[shutil.which("git"), "ls-remote", "https://example.invalid/x.git"]` → raises.
5. `git fetch upstream`, in a repo whose `origin` is local and whose `upstream` is the network URL
   → raises.
6. `git -C <a> -C <b> fetch`, with `<b>` relative to `<a>` and `<a>/<b>` a network repo → raises.

## Rules

- Modify only Files 1–2. Do not touch `scripts/tests/tripwire.sh`, `scripts/lib/`,
  `scripts/lib/foundation/` or the hooks.
- Do not commit or push. `.git` writes are denied in your sandbox, so leave changes unstaged.
  Claude commits.
- No real network: `example.invalid` never resolves, and the guard must raise before git runs.
- Run and paste:
  - `pytest scripts/tests/bin/test_hermetic_guard.py -q`
  - `make test-pytest` (summary line)
  - `"$TMPDIR"/ruffenv/bin/ruff check scripts/tests/conftest.py scripts/tests/bin/test_hermetic_guard.py`
    (or `make lint-python RUFF=<path>`)
  - `bats scripts/tests/lib/bats_negation_lint.bats`
- Mutations: first snapshot `scripts/tests/conftest.py` to `$TMPDIR`. Apply each mutation alone,
  show the red test names, restore, and prove the restore with `cmp`.
  1. Treat `-C` as a one-word flag again → test 1 red.
  2. Compare `words[0] == "git"` again, with no basename → test 4 red.
  3. Always look up `origin` → test 5 red.
  4. Resolve the second `-C` against the Popen `cwd`, not the first `-C` → test 6 red.
- Do not run `make test`.

## Done when

All four calls in the table raise `HermeticViolation`. The `-C` local-fetch test passes. The
existing 8 tests and `make test-pytest` stay green. The 4 mutations each turn a test red, and the
file is restored.
