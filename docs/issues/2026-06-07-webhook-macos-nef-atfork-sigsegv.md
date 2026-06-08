# Issue: macOS NEF atfork SIGSEGV in bin/k3dm-webhook

**Branch:** `k3d-manager-v1.6.3`
**Date:** 2026-06-07
**Commits:** `3ecaeaaa`, `24fd731a`, `a9078e6f`, `b3b48c2d`
**Files:** `bin/k3dm-webhook`

---

## Symptom

`bin/k3dm-webhook` crashed with `KERN_INVALID_ADDRESS (SIGSEGV, rc=-11)` every time a
Slack command triggered a job (e.g. `acg-up`, `acg-down`). Crash reports showed:

```
Thread 0  nw_settings_child_has_forked
          NEFlowDirectorDestroy
          _os_log_preferences_refresh
```

Parent PID matched the LaunchAgent process. All Slack commands returned "Something went
wrong." No Python exception — the child process was killed by the kernel before any
Python code ran.

---

## Root Cause

macOS Network Extension Framework (NEF) registers an `atfork` handler during process
initialization. The handler tries to destroy flow director state in the forked child
process. If the parent has ever performed HTTPS activity (loading NEF's routing tables),
the child receives a pointer that is only valid in the parent's address space →
`KERN_INVALID_ADDRESS` → SIGSEGV.

**The trigger chain:**

1. `import ssl` and `import urllib.request` at Python module top level load NEF as a
   side effect of TLS/socket initialization — before `__main__` runs.
2. Any subsequent `fork()` in the process (from `subprocess.Popen`, `os.fork()`, etc.)
   triggers the atfork handler in the child → crash.
3. `subprocess.Popen` with `stdout=subprocess.PIPE` **always** uses `fork()` in CPython,
   even without `preexec_fn`. The posix_spawn branch in CPython is only taken when the
   pipe setup is trivial (`c2pwrite == -1 or STDOUT_FILENO`); capturing stdout via a pipe
   unconditionally forces the `fork()` path.

The webhook was affected in two places:
- **Job execution** (`_run_cluster`, `_run_cluster_resume`): `subprocess.Popen` with
  `stdout=PIPE` forked on every job launch.
- **k8s context initialization** (`_init_k8s_ctx`): called `subprocess.run(["kubectl",
  "config", "view", ...])` to parse kubeconfig, also forking.

Moving the k8s init to startup (commit `3ecaeaaa`) was not sufficient — `import ssl` at
module top had already loaded NEF before startup ran, so the fork still crashed.

---

## Fix

Three independent changes, all to `bin/k3dm-webhook`:

### 1 — File-based kubeconfig parser (commit `24fd731a`)

Replaced `subprocess.run(["kubectl", "config", "view"])` with a pure Python line-by-line
state machine that reads the kubeconfig file directly. No subprocess, no fork. The parsed
server URL and SSL context are cached in module-level globals `_k3d_server` and
`_k3d_ssl_ctx` at startup and reused by the ESO health check path.

### 2 — `os.posix_spawn` for job execution (commit `a9078e6f`)

Replaced `subprocess.Popen(stdout=PIPE)` + `_drain()` with `os.posix_spawn()`. Python
3.8+ exposes `os.posix_spawn()` which calls the `posix_spawn(2)` syscall directly — no
`fork()`, no atfork handlers triggered. Output is redirected to a file via
`POSIX_SPAWN_OPEN` / `POSIX_SPAWN_DUP2` file actions instead of a pipe.

Helper added:
```python
def _posix_spawn_job(cmd, output_path, cwd=None, env=None):
    _file_actions = [
        (os.POSIX_SPAWN_OPEN, 1, str(output_path), os.O_WRONLY|os.O_CREAT|os.O_APPEND, 0o600),
        (os.POSIX_SPAWN_DUP2, 1, 2),
    ]
    if cwd:
        cmd = ["/bin/bash", "-c", f"cd {shlex.quote(str(cwd))} && " + " ".join(shlex.quote(str(c)) for c in cmd)]
    exe = cmd[0]
    if not os.path.isabs(exe):
        exe = shutil.which(exe) or exe
    return os.posix_spawn(exe, cmd, dict(os.environ) if env is None else dict(env),
                          file_actions=_file_actions, setsid=True)
```

### 3 — `shlex.quote` typo fix (commit `b3b48c2d`)

`_posix_spawn_job` initially imported `shutil as _sh` and called `_sh.quote()`.
`shutil` has no `quote` attribute — that is `shlex.quote`. Fixed by importing
`shlex as _shlex` and using `_shlex.quote()`.

---

## Why Moving to Startup Wasn't Enough

`import ssl` at module top level is the trigger. By the time Python reaches the
`if __name__ == "__main__":` block (where startup init runs), NEF is already loaded.
The fix must eliminate the `fork()` entirely — not just call it earlier.

---

## Verification

After all three commits:
```bash
curl -s -H "X-Webhook-Token: <token>" http://127.0.0.1:7443/api/v1/health | python3 -m json.tool
# ESO ClusterSecretStore: Ready=True, 5/5 synced — no SIGSEGV, no crash dialog
```

Direct API trigger of `acg-up` job completed steps 1/12 → 2/12 without crashing.

---

## Related

- `docs/bugs/v1.6.0-bugfix-webhook-python39-sigsegv.md` — earlier SIGSEGV from wrong
  Python interpreter (3.9 vs 3.13); separate root cause.
- CPython issue: `subprocess.Popen` posix_spawn conditions — `Modules/_posixsubprocess.c`,
  `_Py_can_use_posix_spawn()`.
- Apple Feedback: macOS NEF atfork handler dereferences parent-only pointer in child.
