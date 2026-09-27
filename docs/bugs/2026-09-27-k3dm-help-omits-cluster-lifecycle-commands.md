# Bug: `/k3dm help` omits the cluster lifecycle slash commands

**Filed:** 2026-09-27
**Source:** Claude session — operator could not find the command that produces deployment metrics
**Branch:** `k3d-manager-v1.39.0`

## Description

`/k3dm help` is the only self-describing command surface in Slack. It enumerates all 24
allowlisted make targets with their arguments and required role
(`scripts/lib/webhook/make_targets.py:78-90`). The six cluster lifecycle commands are **not**
make targets — they are separate slash commands routed by the Cloudflare relay
(`workers/slack-relay/index.js:1`) to `/api/v1/cluster`, and they appear in no in-Slack listing
at all. An operator either already knows they exist or cannot discover them.

This is not a routing defect. The split is correct and must be preserved: `/cluster-*` reaches
`_run_cluster` in `scripts/lib/webhook/lifecycle.py`, which carries the running-job guard
(`:151-155`), the progress/stall timer (`:171-201`) and the Pushgateway metrics push
(`:217`). `/k3dm` reaches `/api/v1/make`, which has none of those. Moving the cluster commands
into `MAKE_TARGETS` would silently drop all three behaviours.

**Observed impact.** Asked which deployment populates the `k3dm Deployment Metrics` dashboard,
this session inferred `/k3dm cluster-up aws` from the only discoverable surface. The relay
rejected it with the usage string, because `aws` is not a `KEY=value` pair
(`workers/slack-relay/index.js:88-90`). The correct command, `/cluster-up aws`, is documented in
`docs/howto/slack-slash-commands.md` but nowhere reachable from inside Slack.

## Prior art

Two 2026-07-01 bug docs cover the adjacent defect — the **manifest** in
`docs/howto/slack-slash-commands.md` drifting from the relay allowlist — and both are resolved:

- `docs/bugs/2026-07-01-slack-manifest-drift.md`
- `docs/bugs/2026-07-01-slack-slash-command-manifest-is-out-of-sync-with-relay-code.md`

Those fixed the **doc**. This bug is about the **runtime help output**, which no prior doc covers.
Do not refile against either.

## Scope

Help text only. No routing change, no new make target, no change to `_run_cluster`, no change to
`workers/slack-relay/index.js`.

## Targets

- `scripts/lib/webhook/make_targets.py`
- `scripts/tests/bin/webhook_make_targets.py`
- `docs/howto/slack-slash-commands.md`

## Before You Start

1. `git pull origin k3d-manager-v1.39.0`
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
3. Read all three target files in full
4. Read `workers/slack-relay/index.js:1-31` — the allowlist and `COMMAND_ROLES` are the
   authoritative source for the names and roles below. Do not invent entries.

## Change 1 — `scripts/lib/webhook/make_targets.py`

Add a module-level constant immediately **after** the `MAKE_TARGETS = {...}` dict closes
(after the `}` that ends the dict, before `def parse_make_request`).

The roles are copied verbatim from `COMMAND_ROLES` in `workers/slack-relay/index.js:9-25`.

```python
# The cluster lifecycle commands are NOT make targets. They are separate slash
# commands the relay routes to /api/v1/cluster, which reaches _run_cluster --
# the only path that carries the running-job guard, the stall timer and the
# Pushgateway metrics push. They are listed here for discoverability only:
# /k3dm help is the sole self-describing surface in Slack, and an operator who
# cannot see these commands cannot find the one that records a deployment.
# Roles mirror COMMAND_ROLES in workers/slack-relay/index.js -- keep in sync.
CLUSTER_COMMANDS = (
    ("/cluster-status [provider]", "reader", "cluster + access-layer status"),
    ("/cluster-diagnose [provider|hub] <verb>", "reader", "pods, logs, apps, appsets"),
    ("/hostinger-status", "reader", "permanent app-cluster status"),
    ("/cluster-refresh [provider]", "operator", "refresh the access layer"),
    ("/cluster-up [provider]", "admin", "bring a cluster up (records deployment metrics)"),
    ("/cluster-down [provider]", "admin", "tear a cluster down (records deployment metrics)"),
    ("/cluster-resume [provider]", "admin", "resume a partially provisioned cluster"),
)
```

Then replace the final line of `make_target_help`.

**Old:**

```python
        lines.append(f"• `{' '.join(parts)}` — {spec['summary']} ({spec['min_role']})")
    return "\n".join(lines)
```

**New:**

```python
        lines.append(f"• `{' '.join(parts)}` — {spec['summary']} ({spec['min_role']})")
    cluster_lines = [
        f"• `{name}` — {summary} ({min_role})"
        for name, min_role, summary in CLUSTER_COMMANDS
        if role_allows(role, min_role)
    ]
    if cluster_lines:
        lines.append("")
        lines.append("*Cluster lifecycle* — separate slash commands, not `/k3dm` targets:")
        lines.extend(cluster_lines)
    return "\n".join(lines)
```

Note the provider argument is a **bare token**, not `KEY=value` — that is why the examples read
`[provider]` and not `[PROVIDER=…]`. Do not "normalise" them to the `/k3dm` argument style; that
would document a syntax the relay rejects.

## Change 2 — `scripts/tests/bin/webhook_make_targets.py`

Add these tests to `MakeTargetTests`, immediately after `test_help_is_role_filtered`.

```python
    def test_help_lists_cluster_lifecycle_commands(self):
        """/k3dm help is the only self-describing surface in Slack; the cluster
        commands are not make targets and appeared in no listing at all."""
        admin_help = wh.make_target_help("admin", wh._role_allows)
        self.assertIn("/cluster-up", admin_help)
        self.assertIn("/cluster-down", admin_help)
        self.assertIn("Cluster lifecycle", admin_help)

    def test_cluster_commands_are_role_filtered(self):
        reader_help = wh.make_target_help("reader", wh._role_allows)
        self.assertIn("/cluster-status", reader_help)
        self.assertNotIn("/cluster-up", reader_help)
        self.assertNotIn("/cluster-refresh", reader_help)
        self.assertIn("/cluster-refresh", wh.make_target_help("operator", wh._role_allows))

    def test_cluster_commands_are_not_make_targets(self):
        """Listing them in help must not make them runnable through /api/v1/make --
        that path has no running-job guard, no stall timer and no metrics push."""
        for _name, _role, _summary in wh.CLUSTER_COMMANDS:
            _target = _name.split()[0].lstrip("/")
            self.assertNotIn(_target, wh.MAKE_TARGETS)
            _argv, _error = wh.parse_make_request(_target, {}, False)
            self.assertIsNone(_argv)
            self.assertIn("unknown target", _error)

    def test_cluster_command_roles_match_the_relay(self):
        """COMMAND_ROLES in workers/slack-relay/index.js is authoritative. A role
        that drifts here advertises a command the relay will refuse."""
        _relay = Path(__file__).resolve().parents[3] / "workers" / "slack-relay" / "index.js"
        _text = _relay.read_text()
        for _name, _role, _summary in wh.CLUSTER_COMMANDS:
            _cmd = _name.split()[0]
            self.assertRegex(_text, re.escape(f"'{_cmd}': '{_role}'"))
```

`re` and `Path` are already imported at the top of the file — do not re-import them.

## Change 3 — `docs/howto/slack-slash-commands.md`

Add a short note in the section that lists the slash commands, recording that `/k3dm help` now
also prints the cluster lifecycle commands, and that `COMMAND_ROLES` in
`workers/slack-relay/index.js` is the authoritative source for their roles. Keep it to a short
paragraph — do not restructure the page.

## Rules

- `set -euo pipefail` conventions do not apply (Python only).
- Do NOT modify `workers/slack-relay/index.js`.
- Do NOT add any entry to `MAKE_TARGETS`.
- Do NOT modify `scripts/lib/webhook/lifecycle.py` or `bin/k3dm-webhook`.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/` — they are subtrees.
- Run `pytest scripts/tests/bin/webhook_make_targets.py -q` and paste the output.
- Run `make test-python-unit` and paste the tail.

## Definition of Done

- [ ] `CLUSTER_COMMANDS` added to `scripts/lib/webhook/make_targets.py`
- [ ] `make_target_help` appends a role-filtered cluster lifecycle section
- [ ] Four tests added to `scripts/tests/bin/webhook_make_targets.py`, all passing
- [ ] `docs/howto/slack-slash-commands.md` notes the new help output
- [ ] `pytest scripts/tests/bin/webhook_make_targets.py -q` output pasted
- [ ] `make test-python-unit` tail pasted
- [ ] Commit message exactly:
      `fix(webhook): list the cluster lifecycle commands in /k3dm help`
- [ ] Pushed to `origin/k3d-manager-v1.39.0`; report the SHA
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated; paste the lines

## What NOT to Do

- Do NOT create a PR
- Do NOT merge anything
- Do NOT commit to `main`
- Do NOT force-push
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the three listed targets plus the two memory-bank files
