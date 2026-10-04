# Bug: Step 10g.5 reports "Keycloak reverse tunnel setup failed" on every `make up` rerun

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN. Spec ready for Codex.
**Severity:** low. The warning is a false alarm while the earlier tunnel lives. A half-dead
earlier tunnel is never replaced, which would leave JWT auth from the app cluster broken.

## Evidence (2026-10-04, reused sandbox stack)

- `make up` printed `Keycloak reverse tunnel setup failed — JWT auth from app cluster may be unavailable`.
- A local `ssh -f -N -o ExitOnForwardFailure=yes ... -R 127.0.0.1:18080:127.0.0.1:80 ubuntu`
  (PID 27102, started 13:41 by the previous `make up`) was still running.
- On `ubuntu`: `127.0.0.1:18080` is LISTEN, and a curl through it returns `200`. The tunnel works.
- A second identical `ssh -R` reproduces the failure: `Error: remote port forwarding failed for
  listen port 18080`, rc 255.

## Root cause

Step 10g.5 starts the reverse tunnel unconditionally. `ExitOnForwardFailure=yes` makes the new
ssh exit when the remote port is already bound, so every rerun against a reused stack warns.
The step never checks whether a working tunnel already exists, and never removes a stale one.

## Fix (Codex)

Target files: `bin/cluster-up`, `scripts/tests/bin/cluster_up.bats`. Nothing else.

### F1. New helper in `bin/cluster-up`

Insert directly **above** `function _acg_ldap_bind_pass() {`:

```bash
function _acg_keycloak_reverse_tunnel_up() {
  local code
  code=$(ssh -o ConnectTimeout=10 ubuntu "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:18080/" 2>/dev/null || true)
  [[ -n "${code}" && "${code}" != "000" ]]
}

```

### F2. Step 10g.5

Old:

```bash
  ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -R 127.0.0.1:18080:127.0.0.1:80 ubuntu 2>/dev/null || \
    _warn "[acg-up] Keycloak reverse tunnel setup failed — JWT auth from app cluster may be unavailable"
```

New:

```bash
  if _acg_keycloak_reverse_tunnel_up; then
    _info "[acg-up] Keycloak reverse tunnel already active on ubuntu:18080 — skipping"
  else
    pkill -f -- '-R 127.0.0.1:18080:127.0.0.1:80 ubuntu' 2>/dev/null || true
    ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
      -R 127.0.0.1:18080:127.0.0.1:80 ubuntu 2>/dev/null || \
      _warn "[acg-up] Keycloak reverse tunnel setup failed — JWT auth from app cluster may be unavailable"
  fi
```

Leave the rest of the step (sysctl, iptables, CoreDNS) unchanged.

## Gates (offline; stubs only; no live cluster, no real ssh)

- **BATS `cluster_up.bats`, behavior:** extract the helper with
  `sed -n '/function _acg_keycloak_reverse_tunnel_up/,/^}/p' bin/cluster-up`. Use an `ssh` stub on
  `PATH` that prints `${STUB_CODE}` and exits `${STUB_RC:-0}`.
  - `STUB_CODE=404` → helper returns 0.
  - `STUB_CODE=000 STUB_RC=7` → helper returns non-zero.
  - `STUB_CODE=` (empty), `STUB_RC=255` → helper returns non-zero.
  - Use `run` and assert `$status`; do not use a bare `! cmd` mid-test.
- **BATS `cluster_up.bats`, source:** the 10g.5 block
  (`sed -n "/Step 10g.5\/14/,/Step 10e\/14/p" bin/cluster-up`) contains
  `_acg_keycloak_reverse_tunnel_up`, `already active on ubuntu:18080` and `pkill -f`, and
  `_acg_keycloak_reverse_tunnel_up` appears before `ssh -f -N` in it.
- **Mutation:** in the helper, change `!= "000"` to `!= "999"` (snapshot with `cp`, then restore
  and `cmp`; never `git checkout`). The `000` behavior test must go red.
- `shellcheck bin/cluster-up` adds no new warnings compared with HEAD.
  `bats scripts/tests/bin/cluster_up.bats` is all green.
- `git diff --stat` shows only the two target files.

## Definition of Done

- [ ] F1–F2 applied exactly as written.
- [ ] Gates pass; paste the BATS summary, the shellcheck comparison and the mutation result.
- [ ] Commit message, verbatim:
      `fix(cluster-up): reuse a live Keycloak reverse tunnel and replace a stale one on rerun`
- [ ] Commit trailers, consecutive with no blank line between them:
      `Co-Authored-By: Codex <noreply@openai.com>`
      `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- [ ] Push to `origin/k3d-manager-v1.41.0` and report the SHA. If `.git/index.lock` is denied,
      stop after the edits and the gates, and report that.

## What NOT to Do

- Do NOT create a PR. Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the two targets. Do NOT commit to `main`.
- Do NOT run real `ssh`, `pkill` or anything against a live host or cluster.

## Live verification (Claude, next `make up`)

- A rerun on a reused stack prints `Keycloak reverse tunnel already active on ubuntu:18080 — skipping`.
- `ssh ubuntu curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/` is not `000`.
