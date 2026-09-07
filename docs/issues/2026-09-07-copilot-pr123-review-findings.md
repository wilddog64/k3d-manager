# PR #123 review findings — v1.32.0 (monthly security audit + webhook `/ask` hardening)

PR: https://github.com/wilddog64/k3d-manager/pull/123
Date: 2026-09-07

Three items were addressed on this PR: one CI failure surfaced by the first CI run of the
F2 sandbox tests, plus two Copilot review points (one inline, one in the review body).

---

## 1. CI failure — `k3dm-ask-bash denies credential-dir reads` (Linux-only)

**Where:** `scripts/tests/lib/webhook.bats:852` (BATS test #324), CI `lint` job.

**Symptom:** green on macOS locally, red on CI (ubuntu). The first assertion (`status -eq 1`)
passed but the scope-message assertion (`$output == *"scope"*`) failed.

**Root cause (verified in an ubuntu:24.04 container, not assumed):** the suite overrides the
home directory for isolation —

```bash
# scripts/tests/lib/webhook.bats:33-34
_BATS_WEBHOOK_HOME="$(mktemp -d)"
export HOME="${_BATS_WEBHOOK_HOME}"
```

On macOS `mktemp -d` returns a path under `/var/folders/...` (outside every allow-listed
sandbox prefix), so `${HOME}/.cloudflared/...` is denied "Out of scope" — test passes. On
Linux `mktemp -d` returns `/tmp/tmp.XXXX`, and **`/tmp` is an intentionally-allowed diagnostic
prefix** in `bin/k3dm-ask-bash`. So `${HOME}/.cloudflared/...` resolved *inside* `/tmp`, the
scope loop allowed it, `exec bash` ran `cat` on a missing file (exit 1, "No such file"), and
the "scope" assertion failed. This is a **test bug, not a sandbox gap** — the sandbox
correctly denies real credential dirs in production (where `$HOME` is a real home) and
correctly treats `/tmp` as scratch. Confirmed: a direct `k3dm-ask-bash` call on
`/root/.cloudflared/anything` denies correctly on Linux; only the `${HOME}`-derived path
under `/tmp` slipped through.

**Fix:** pin the test to fixed system credential paths that are unconditionally outside every
allow-listed prefix, independent of the mutated `$HOME`:

```bash
run "${repo_root}/bin/k3dm-ask-bash" -c "cat \"/etc/cloudflared/cert.pem\"" "/etc/cloudflared/cert.pem"
...
run "${repo_root}/bin/k3dm-ask-bash" -c "cat \"/etc/kubernetes/admin.conf\"" "/etc/kubernetes/admin.conf"
```

Verified passing on macOS and in an ubuntu:24.04 container.

**Process note:** sandbox scope tests must not build "out-of-scope" paths from `$HOME` when
the suite reassigns `$HOME` to a `mktemp -d` (which is under `/tmp` on Linux — an in-scope
prefix). Use fixed absolute paths outside the allow-list.

---

## 2. Copilot (inline) — non-deterministic audit report month

**Where:** `scripts/lib/hermes/audit.py:182`.

**Flag:** `run_audit(..., now=...)` injects a deterministic timestamp, but the report header
used `timestamp()[:7]` (wall clock) for `report["month"]`, so the digest month ignored the
injected `now` and was non-deterministic in tests / non-live runs.

**Fix:** derive the month from the already-resolved injected `now`:

```python
# before
"month": timestamp()[:7],
# after
"month": now.strftime("%Y-%m"),
```

The now-unused `from hermes.records import timestamp` import was removed. Hermes suite:
47 passed.

---

## 3. Copilot (review body) — sandbox egress via git network subcommands

**Where:** `bin/k3dm-ask-bash` (F2 egress hardening).

**Flag:** the "no egress" hardening blocks `curl|wget|nc|ssh|scp|…` so a readable-file exfil
has nowhere to send data, but **git network subcommands** (`git clone|fetch|pull|push|
remote|ls-remote|submodule|…`) are an unblocked egress path — a reader could push readable
content to an attacker remote, bypassing the client block. The pre-existing git guard only
covered *destructive* forms (`reset --hard`, `push --force`, `branch -D`, …), not network.

**Fix:** add a network-git guard in the always-blocked section, fail-closed, while leaving
local read-only inspection (`git log/status/diff/show/rev-parse/blame/…`) allowed:

```bash
if echo "$CMD" | grep -qE '\bgit\b.*\b(clone|fetch|pull|push|remote|ls-remote|submodule|send-pack|fetch-pack|upload-pack|request-pull|daemon)\b'; then
  _deny "$CMD"
fi
if echo "$CMD" | grep -qE '\bgit\b.*--remote\b'; then
  _deny "$CMD"
fi
```

Two regression tests added: `denies git network subcommands` (clone/fetch/pull/push/remote/
ls-remote/`archive --remote` all blocked) and `allows local read-only git inspection`
(`git --version`, `git rev-parse --is-inside-work-tree` not denied). shellcheck clean;
sandbox suite 11/11 on macOS and Linux.
