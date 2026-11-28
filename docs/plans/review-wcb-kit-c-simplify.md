# Blind review brief — capture kit child c (simplify the operator path)

**Status:** review brief, 2026-11-28
**Repo / branch:** `k3d-manager`, `k3d-manager-v1.47.0`, read only
**Intent approved:** operator, 2026-11-28
**Intent approval words:** "can you draft the spec and have neon/fable review it? send me intents when done. I can apporve it with my phone"
**Reviewer role:** blind, read-only; do not read other reviewers' output; change no files

## What to review

`docs/plans/web-console-b-capture-kit-c-simplify.md` (rev 1). Read it, then the code it changes:
`scripts/lib/wcb_capture/api.py`, `scripts/lib/wcb_capture/stage.py`, and its contract readers
(`supervisor.py`, `filters.py`, `scan.py`, `collect.py`, `isolation.py`). Parent contract:
`docs/plans/web-console-b-capture-kit.md` (Contract between children; Token; §3 reads).

## Questions

1. **Security:** can any resolved value, the capture token or the connector token leak (stdout, error text, argv,
   env, a file other than `terms` / `tunnel-token`)? Is C2 (running `security add-generic-password -w` with inherited
   stdio) safe, and is C3 (`getpass` + `O_EXCL|O_NOFOLLOW`) sufficient against a pre-planted file or symlink?
2. **Privacy ordering:** does the `terms`-before-anything invariant hold for every path, including fallbacks and
   `--after-disable`? Is reusing `terms` for `--after-disable` safe?
3. **External behaviour:** is the Cloudflare API reading right (list filters, `domain` with a path, `auth_domain`)?
   Is the fallback enough if the read-only token cannot list with filters?
4. **Acceptance:** is every `must_not` red on current code by the stated mutation, and does each test prove what it
   claims? Any missing case or contract reader?
5. **Scope:** does it actually make sitting 1 simpler, without loosening any parent invariant? Anything to cut?

## Output

A verdict (APPROVE / NEEDS FIXES / REJECT), then numbered findings, each with severity (blocker / should / nit),
file:line, the problem, and a concrete fix. No praise, no restating the spec.
