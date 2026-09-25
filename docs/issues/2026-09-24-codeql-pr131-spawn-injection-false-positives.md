# CodeQL PR #131 — spawn injection alerts are false positives

**Date:** 2026-09-24
**PR:** #131 (`k3d-manager-v1.37.0` → `main`)
**Alerts:** 23, 24, 26, 27
**Disposition:** dismissed as `false positive` with this document as the rationale

## What CodeQL reported

| Alert | Rule | Severity | Location |
|---|---|---|---|
| 26 | `py/command-line-injection` | critical | `scripts/lib/webhook/proc.py:38` |
| 27 | `py/command-line-injection` | critical | `bin/k3dm-webhook:991` |
| 23 | `py/path-injection` | high | `scripts/lib/webhook/proc.py:38` |
| 24 | `py/path-injection` | high | `bin/k3dm-webhook:991` |

Both locations are the `os.posix_spawn(...)` call in a capture helper. Alert 25
(`py/clear-text-logging-sensitive-data`, `bin/k3dm-hermes:451`) is **not** in this set — it is
main's pre-existing alert 22 at a shifted line, and is left open like its predecessor.

## Why these are not exploitable

Both rules are about the *executable* being attacker-controlled. At both sinks it is not.

**1. `cmd[0]` is a literal at every call site.**

`proc.py`'s helper is reached from `_run_make_target` (`lifecycle.py:83-89`), which builds
`["make", "--no-print-directory", *argv_tail]` — `cmd[0]` is the constant `"make"`. The
`bin/k3dm-webhook` helper's call sites pass `"aws"`, `"/bin/bash"`, or a `Path` resolved from
`__file__`. No call site derives `cmd[0]` from request input.

**2. When `cwd` is set, the spawned executable is hard-coded.**

```python
cmd = ["/bin/bash", "-c", f"cd {_shlex.quote(str(cwd))} && {cmd_str}"]
exe = cmd[0]
```

`exe` resolves to `/bin/bash`. The `_shutil.which(exe)` lookup that CodeQL follows as a
path-injection sink can only ever receive `"make"`, `"aws"`, or an absolute path.

**3. Argument values that *do* come from a request are validated before they reach argv.**

`parse_make_request` (`scripts/lib/webhook/make_targets.py:1-80`) is a closed allowlist:

- `target` must be a key of the `MAKE_TARGETS` dict.
- each arg key must appear in that target's own allowlist.
- each value must satisfy `_ARG_PATTERNS[key].fullmatch(value)` — anchored patterns over
  metacharacter-free charsets (`[a-z0-9-]`, `sha256:[0-9a-f]{64}`, literal alternations).

A value that could express a shell metacharacter cannot pass `fullmatch`. `shlex.quote` is
then applied per element on top of that.

## Why they surfaced now

v1.37.0 extracted an inline spawn into a shared primitive imported by six modules and moved
~2054 lines of `bin/k3dm-webhook` into five new modules. That makes an interprocedural taint
path *visible* to CodeQL without changing what the code can do. CodeQL's own run summary says
so:

> Alerts not introduced by this pull request might have been detected because the code changes
> were too large.

The dataflow CodeQL traced is real. What it cannot see is that an anchored `fullmatch` against
a metacharacter-free charset is a sanitizer.

## What would make these real

Any of the following would turn these back into true positives — re-open the alerts if one lands:

- a call site that puts request-derived data in `cmd[0]`;
- a new `MAKE_TARGETS` arg pattern whose charset admits a shell metacharacter, a `.` wildcard,
  or that is not anchored with `fullmatch`;
- a new caller of `_spawn_capture_text` / `_posix_spawn_capture` that bypasses
  `parse_make_request` for argv it builds from a request body.

## Process note

The four alerts carry an in-code `# codeql[...]` marker at each sink pointing at this document,
so the reasoning sits next to the code rather than only in the dismissal text. GitHub code
scanning does not treat those comments as dismissals on its own — the alerts were dismissed
through the code-scanning API, and the comments exist for the next reader.

Precedent followed: v1.34.0's alerts 19/20 were documented rather than dismissed because they
did not block a merge. These four block the PR's required check, so they are dismissed **and**
documented.
