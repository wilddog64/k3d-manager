# Bug: /ask claude spawns infinite bash processes — fork bomb via #!/usr/bin/env bash shebang

**Branch:** `k3d-manager-v1.6.3`
**Files:** `bin/k3dm-ask-bash`

---

## Problem

Running `/ask claude` (or any `/ask` command) causes hundreds of `.ask-sandbox/bash`
processes to spawn until the system is overwhelmed.

**Root cause:** `bin/k3dm-webhook` prepends `.ask-sandbox/` to `PATH` before invoking
the Claude agent subprocess (line 1813):

```python
"PATH": f"{sandbox_bin}:{os.environ.get('PATH', '')}",
```

`bin/k3dm-ask-bash` had a `#!/usr/bin/env bash` shebang. When the OS executes the
script, `env` resolves `bash` via the modified `PATH` — finds `.ask-sandbox/bash`
(a symlink back to `k3dm-ask-bash`) — and re-executes the same script, which again
calls `env bash`, creating infinite recursion.

---

## Reproduction

1. Start the webhook (`make restart-webhook`)
2. Send `/ask claude` in Slack
3. Run `ps aux | grep ask-sandbox` — hundreds of processes appear immediately

---

## Fix

### Change 1 — `bin/k3dm-ask-bash`: use absolute bash path in shebang

**Exact old line (line 1):**

```bash
#!/usr/bin/env bash
```

**Exact new line:**

```bash
#!/bin/bash
```

Absolute path bypasses `PATH` lookup entirely, so prepending `.ask-sandbox/` to `PATH`
has no effect on the shebang resolution.

Note: `exec /bin/bash "$@"` at the end of the script was already correct for the same
reason — this fix aligns the shebang with the existing pattern.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-ask-bash` | Change shebang from `#!/usr/bin/env bash` to `#!/bin/bash` |

---

## Definition of Done

- [x] `bin/k3dm-ask-bash` line 1 is `#!/bin/bash`
- [x] Committed and pushed to `k3d-manager-v1.6.3` — SHA `f1a1dcff`
- [x] Runaway processes killed with `pkill -f k3dm-ask-bash`
- [x] Webhook restarted with `make restart-webhook`

---

## What NOT to Do

- Do NOT use `#!/usr/bin/env bash` in any script that is symlinked into a directory
  prepended to `PATH` by its caller — this pattern always risks fork bombs
- Do NOT use `#!/usr/bin/env <interpreter>` in sandbox wrapper scripts generally;
  use absolute paths (`#!/bin/bash`, `#!/usr/bin/python3`) instead
