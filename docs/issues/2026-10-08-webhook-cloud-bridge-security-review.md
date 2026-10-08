# Webhook and cloud-bridge security review

**Date:** 2026-10-08
**Status:** PARTIAL — two offline defects reproduced; live configuration not checked
**Branch:** k3d-manager-v1.42.0
**Reviewed revision:** 6e54ca66bddf47973eff57216d290b5df821b529
**Environment:** cloud Linux workspace /workspace/scratch/f76985e49dec, not operator laptop

## Scope and results

Read current webhook server, auth/policy, Make/cloud action registries, bridge, relay,
AI agent module, Bash wrapper, Slack rendering, tunnel configuration and prior security
audit/Phase 1 hardening plan. No live exploitation, Slack message, bridge task, deployment,
restart or configuration change was performed.

Filed:
- [Slash-command caller authorization](../bugs/2026-10-08-slack-slash-commands-trust-command-role.md)
- [Bash shell-string path scope](../bugs/2026-10-08-ask-bash-shell-string-bypasses-path-scope.md)

Original offline probe output, verbatim:

```text
Relayed cluster-down role, caller mapped reader: admin admin policy permits: True
Relayed k3dm role, caller mapped reader: reader
Sandbox out-of-scope synthetic canary read: exit 0 output HARMLESS_CANARY
```

## Commands used

The cloud execution tool ran python -c with a script that AST-extracted the policy functions
from connector-fetched source, stubbed Slack lookup to reader, then used subprocess.run:

```python
subprocess.run(
    ["/bin/bash", str(wrapper), "-c", "cat " + str(canary)],
    text=True, capture_output=True,
)
```

wrapper was a temporary exact copy of bin/k3dm-ask-bash, and canary contained only
HARMLESS_CANARY. Both were under a TemporaryDirectory in the cloud workspace. No shell
command was sent through cloud-bridge. The following readable reproduction runs from a
local repository checkout and intentionally reads only a file it creates:

```bash
python3 - <<'PY'
import ast
import os
import pathlib
import shlex
import subprocess
import tempfile

repo = pathlib.Path.cwd()
tree = ast.parse((repo / "scripts/lib/webhook/policy.py").read_text())
constants = {
    "_ROLE_LEVELS", "_ROLE_DEFAULT", "_ROLE_CAPABILITIES",
    "CLOUD_RUNNER_TARGETS", "CLOUD_RUNNER_LIFECYCLE",
}
functions = {
    "_normalize_role", "_normalize_actor_role", "_request_role",
    "_effective_make_role", "_role_allows",
}
nodes = []
for node in tree.body:
    if isinstance(node, ast.Assign):
        if any(isinstance(t, ast.Name) and t.id in constants for t in node.targets):
            nodes.append(node)
    elif isinstance(node, ast.AnnAssign):
        if isinstance(node.target, ast.Name) and node.target.id in constants:
            nodes.append(node)
    elif isinstance(node, ast.FunctionDef) and node.name in functions:
        nodes.append(node)
ns = {}
exec(compile(ast.Module(body=nodes, type_ignores=[]), "<policy>", "exec"), ns)
ns["_slack_user_role"] = lambda uid: "reader"
headers = {"X-K3DM-Role": "admin"}
role = ns["_request_role"](headers, "admin")
print("Relayed cluster-down role, caller mapped reader:", role,
      "admin policy permits:", ns["_role_allows"](role, "admin"))
print("Relayed k3dm role, caller mapped reader:",
      ns["_effective_make_role"](headers, {"slack_user_id": "TEST_READER"}, "admin"))

with tempfile.TemporaryDirectory(dir=repo) as directory:
    root = pathlib.Path(directory)
    canary = root / "canary"
    canary.write_text("HARMLESS_CANARY")
    # Point declared repository scopes at empty siblings so the canary is outside them.
    env = dict(os.environ, K3DM_FIX_MODE="0",
               K3DM_REPO_ROOT=str(root / "allowed-repo"),
               K3DM_SHOPPING_CARTS_ROOT=str(root / "allowed-apps"))
    result = subprocess.run(
        ["/bin/bash", str(repo / "bin/k3dm-ask-bash"),
         "-c", "cat " + shlex.quote(str(canary))],
        env=env, text=True, capture_output=True,
    )
    print("Sandbox out-of-scope synthetic canary read: exit", result.returncode,
          "output", result.stdout.strip())
PY
```

This readable reproduction adjusts the declared scopes for portability. The original probe
used the wrapper defaults and an outside /workspace canary. Both isolate the same argv seam.
Policy extraction avoids Keychain reads and imports with startup side effects. No workers
are invoked. This is evidence of policy/wrapper behavior, not a live compromise.

## Existing protection confirmed in source

Loopback listener, bearer comparison, Slack signatures/replay window, event caller allowlist,
token-bound role ceilings, cloud-runner capabilities, bounded bridge argument allowlists,
and Slack callback URL host checking exist. September fix-mode role gating and callback
allowlist fixes are present. Do not reopen those fixed bugs as if absent.

## Additional boundaries and unverified settings

- Bridge requested_by is request data, not verified actor identity. Repository/branch write
  permission is its current submission boundary. Allowlisted tests and fixed AWS sandbox
  lifecycle actions are possible; arbitrary commands/URLs remain disallowed.
- Existing submitter-authentication plan covers that future boundary:
  [v1.44.0 plan](../plans/v1.44.0-cloud-request-submitter-authentication.md).
- Cloudflare Access policies, deployed token binding, firewall/listeners, agent OS permissions,
  actual sandbox activation and runtime versions were not verified.
- Public tunnel hostname does not itself prove Access policy protection. Verify machine
  authentication between relay and webhook without breaking legitimate Slack events.
- No evidence of an intrusion was obtained; no numerical compromise probability can be inferred.

## Follow-up

Fix the two canonical bugs, then verify role denial before worker invocation and confinement
through the real agent tool path. Check live relay-only Access policy, dedicated OS identity
and credential scope. Documentation checks and pre-commit audit apply to this filing;
BATS/ShellCheck runtime checks are not applicable because no runtime file was changed.
