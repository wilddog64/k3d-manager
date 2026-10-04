# Bug: restoring a rebuilt hub's credentials takes six manual steps and fails silently without the Keychain

**Branch:** `k3d-manager-v1.41.0`
**Filed:** 2026-10-03, Claude
**Status:** FIXED in `fb71deb4` — `make hub-recover` / `make hub-restore`.
**Severity:** Medium. After the 2026-10-03 hub loss, `make hub-up` rebuilt the cluster, but restoring its credentials took six commands. They also failed repeatedly when run from Claude Code's `!` prompt.
**Files:**
- `bin/hub-restore` (new)
- `scripts/lib/cloudflare_tunnel.sh` (new)
- `bin/cluster-up` (tunnel block only)
- `Makefile`
- `scripts/tests/bin/hub_restore.bats` (new)
- `docs/howto/hub-rebuild-from-gitops-vault.md`
- `CHANGELOG.md`

## What happened

The operator asked: *"we should have a better make <target> to execute hub recovery"*.

**`make hub-up` stops too early.** It brings back the cluster, Vault, LDAP and ArgoCD. Everything that comes from the Keychain then had to be run by hand:
1. `make alertmanager-secret` or `make restore-google-app-password`, then `make observability`;
2. `make signing-restore`;
3. `./scripts/k3d-manager hub_recovery_reconcile --confirm`;
4. `make platform-ops` (webhook-token Secret sync);
5. `launchctl kickstart` of the Grafana port-forward;
6. a hand-written `com.k3d-manager.cloudflare-tunnel` plist. Without it `grafana.3ai-talk.org` returned 530. `cluster-down` removes that agent with the hub, and only a sandbox `make up` puts it back.

**Every Keychain step fails without a GUI session.** That covers Claude Code's `!` prompt, `nohup` and ssh. The failure arrives mid-run, step by step:
- `alertmanager-secret`: "unresolved: gmail_from … gmail_app_pw … sms_gateway", even though all three items are present;
- `signing-restore`: "no Keychain backup";
- `hub_recovery_reconcile`: `User interaction is not allowed`.

Nothing checks up front that the Keychain is readable, so the operator ran the whole list twice before the cause was clear.

**A root-owned folder blocks both agents.** `~/.local/share/k3d-manager/logs` was root-owned, so the Grafana port-forward exited 78 (see `2026-10-03-root-owned-state-logs-dir-kills-grafana-port-forward.md`). Nothing reported it.

**`make alertmanager-secret` never backs up the app password.** It saves `gmail_from` and `sms_gateway` to the Keychain, but `gmail_app_pw` only goes to Vault. A password typed at its prompt is lost with the hub.

## Fix

### R1 — `bin/hub-restore` (new, `set -euo pipefail`)

Model it on `bin/hub-up`: same lib-foundation sourcing, `_hub_name` / `_hub_context`, and `K3DM_DISPATCHER`. Add `K3DM_MAKE` (default `make`) so tests can stub make.

**Preflight.** Every check runs before any step; on any failure, exit 2 before step 1.
- **P1 — interactive terminal.** Require `[[ -t 0 ]]`. If it fails, `_err "[hub-restore] needs an interactive terminal with Keychain access — run it from Terminal.app/iTerm, not Claude Code '!', nohup or ssh"`.
- **P2 — Keychain readable.** Probe with `security show-keychain-info` (this distinguishes a locked or non-GUI keychain; see the memory note on `User interaction is not allowed`). If it fails, give the same guidance and add `security unlock-keychain`.
  - **Never read a secret value in preflight.**
  - `HUB_RESTORE_SKIP_PREFLIGHT=1` bypasses P1/P2, for tests only. Document that it is test-only.
- **P3 — hub context.** `kubectl config current-context` must equal `${_hub_context}`. Use the same message as hub-up's U4 guard.
- **P4 — no root-owned folders.** `find "${_ACG_STATE_BASE:-$HOME/.local/share/k3d-manager}" -maxdepth 3 -type d -user root`. Folders only: root-owned *files* written by the root LaunchDaemons are normal. If any are found, list them and print the exact `sudo chown -R "$(id -un)":staff <dir>` per folder. Never run sudo.

**Steps.** Each step logs `[hub-restore] Step N/8 — <name>` before it runs.
- **A failure does not stop the run.** Every step is independent; record `PASS` / `FAIL` / `SKIP` and keep going.
- **At the end, print a summary table.** Exit 1 if any step FAILed, otherwise 0.

1. **Vault port-forward.** If `curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:18200/v1/sys/health` is not `200`, run `${K3DM_MAKE} install-vault-port-forward`.
2. **Alertmanager credentials.** Run `${K3DM_MAKE} restore-google-app-password` (Keychain → Vault).
3. **Observability.** Run `${K3DM_MAKE} observability`.
4. **Signing key.** Run `${K3DM_MAKE} signing-restore CONTEXT=${_hub_context}`.
   - If its output contains `no Keychain backup`, mark the step **SKIP**, not FAIL, with: `signing key has no backup — decide before running signing_init (a new key invalidates existing signatures)`.
   - **Never call `signing_init`.**
5. **Hub reconcile.** Run `"${_dispatcher}" hub_recovery_reconcile --confirm`.
6. **Platform ops.** Run `${K3DM_MAKE} platform-ops`.
7. **Local agents:**
   - `${K3DM_MAKE} install-hub-pushgateway-port-forward`;
   - `launchctl kickstart -k "gui/$(id -u)/com.k3d-manager.grafana-port-forward"`, only if that label is in `launchctl list`;
   - `_ensure_cloudflare_tunnel_agent` (R2).
8. **Verify.** Report each check on its own line; any failure makes the step FAIL.
   - Vault `:18200` health returns 200;
   - Grafana `http://127.0.0.1:3001/api/health` returns 200;
   - `kubectl --context ${_hub_context} -n monitoring get secret alertmanager-smtp-secret` exists. **Never print its data:** existence only, with stdout to `/dev/null`;
   - `launchctl list` shows `com.k3d-manager.cloudflare-tunnel` with a PID.

### R2 — `scripts/lib/cloudflare_tunnel.sh` (new)

Move the named-tunnel LaunchAgent block from `bin/cluster-up` (around lines 1834–1890) into `_ensure_cloudflare_tunnel_agent <state_dir>`. That block covers plist render, diff-skip, bootout/bootstrap and the launchctl log.
- **No behaviour change.** Keep the same label, plist content, log path `<state_dir>/logs/cloudflare-tunnel.log`, the "unchanged — skipping reinstall" path and the messages, with the `[acg-up]` prefix replaced by a caller-supplied prefix.
- **Return 0 with a WARN, without installing,** when `cloudflared` is not on `PATH` or `~/.cloudflared/config.yml` is absent.
- **`bin/cluster-up`** sources the new file and calls the function where the block was.
- **`bin/hub-restore`** calls it with `"$(_acg_provider_state_dir k3s-aws)"`, so the plist is byte-identical to the one a sandbox `make up` writes and is then skipped as unchanged.
- **Never read** `~/.cloudflared/*.json` or `cert.pem`. The function only checks whether `config.yml` exists.

### R3 — `Makefile`

- **`hub-restore:`** `@bin/hub-restore`. Add it to `.PHONY` and to `make help`: `make hub-restore   Restore Keychain-backed hub credentials + local agents (run in Terminal.app)`.
- **`hub-recover:`** runs P1–P2 first (`bin/hub-restore --preflight-only`, which exits after the preflight), then `$(MAKE) --no-print-directory hub-up`, then `bin/hub-restore`. A non-GUI shell is therefore rejected before the long rebuild, not after it. P3 and P4 are skipped in `--preflight-only` mode, because the hub may not exist yet. Add it to `.PHONY` and `make help`: `make hub-recover   Full hub DR: hub-up + hub-restore (run in Terminal.app)`.
- **`alertmanager-secret`:** after the existing `sms_gateway` Keychain backup line, add the same `security add-generic-password -U -a "$$USER" -s k3dm-alertmanager-gmail-app-password -w "$$_pw" 2>/dev/null && echo "[alertmanager-secret] gmail_app_pw backed up to Keychain"`. Do not echo the value.
- **`restore-google-app-password`:** the item existed, yet this target said "not in Keychain"
  (2026-10-03). The cause was either an empty stored value or an access denial hidden by
  `2>/dev/null`. Change the missing-value error so it tells the two apart, without ever printing
  the value:
  - read stderr into a variable rather than `/dev/null`;
  - if `security find-generic-password -a "$$USER" -s k3dm-alertmanager-gmail-app-password`
    succeeds (attributes only, no `-w`) but `-w` returns empty, say
    `item exists but is EMPTY — re-create it with: make alertmanager-secret`;
  - otherwise print the captured `security` error line.
  - Gate: a parsed recipe-text check for the new attributes-only probe.

### R4 — docs

- **`docs/howto/hub-rebuild-from-gitops-vault.md`:** add a "One command" section near the top:
  - `make hub-recover` in Terminal.app;
  - what it restores;
  - what it does not restore: the signing key without a backup, Prometheus history, Alertmanager silences, the vector index, and old ArgoCD/Vault tokens such as Hermes's ArgoCD token;
  - why `!`, `nohup` and ssh fail.
- **`CHANGELOG.md` `[Unreleased]` → `### Added`:** `make hub-restore` / `make hub-recover`. **`### Fixed`:** the app-password Keychain backup.

## Gates (offline; paste actual output)

**Harness:** temp `HOME`. Stub `make` via `K3DM_MAKE`, plus `security`, `kubectl`, `launchctl`, `curl`, `cloudflared` and `id` on `PATH="<stubs>:/usr/bin:/bin"`. Each stub appends its argv to a call log; `K3DM_DISPATCHER` is a stub. **Never** run the real make, dispatcher, launchctl, security or kubectl.

1. **No TTY:** `bin/hub-restore </dev/null` exits 2, says `Terminal.app`, and the make call log is empty.
2. **Keychain unreadable:** the `security` stub fails `show-keychain-info` → exit 2, empty make log.
3. **Wrong context:** current-context is `ubuntu-hostinger` → exit 2, both context names in the output, empty make log.
4. **Root-owned folder:** stub `find` (or point `_ACG_STATE_BASE` at a fixture and stub the ownership check) so one folder is reported → exit 2, output contains `sudo chown -R` and that path, empty make log.
5. **Happy path** (`HUB_RESTORE_SKIP_PREFLIGHT=1`, all stubs succeed):
   - the make log shows `restore-google-app-password`, `observability`, `signing-restore`, `platform-ops`, `install-hub-pushgateway-port-forward`, in that order;
   - the dispatcher log shows `hub_recovery_reconcile --confirm`;
   - the output has a summary with 8 rows and exit 0.
6. **Keep going:**
   - the `observability` stub fails → steps 4–8 still run, the summary marks step 3 FAIL, exit 1;
   - the `signing-restore` stub prints `no Vault key and no Keychain backup` and exits 1 → step 4 is SKIP, exit 0 if all else passes, and the dispatcher log has no `signing_init`.
7. **Tunnel extraction is byte-identical:**
   - render the plist through `_ensure_cloudflare_tunnel_agent` with a fixed `HOME` / state dir / `cloudflared` path;
   - render the pre-extraction block, from the `git show HEAD:bin/cluster-up` text, with the same inputs;
   - `cmp` the two.
8. **`alertmanager-secret` backs up the app password:** use a parsed recipe-text check. Assert the tokens `add-generic-password`, `k3dm-alertmanager-gmail-app-password` and `$$_pw`, and that no `echo` prints `$$_pw`. Do NOT run the target.
9. **`hub-recover` order:** from the parsed recipe text, `--preflight-only` comes before `hub-up`, which comes before `bin/hub-restore`. `make help` lists both new targets. `make help` is safe to run; never use `make -n` on these.
10. **Mutations.** For each one, `cp` a snapshot, mutate, show red, restore from the snapshot, and show `cmp`. Never use `git checkout`.
    - (a) delete the P1 TTY check → gate 1 red;
    - (b) make a step failure abort the run → gate 6 red;
    - (c) map `no Keychain backup` to FAIL → gate 6 red.
11. **Other checks:**
    - `shellcheck bin/hub-restore scripts/lib/cloudflare_tunnel.sh bin/cluster-up` (no new codes vs HEAD);
    - `bats scripts/tests/bin/hub_restore.bats scripts/tests/bin/hub_up.bats`;
    - the existing cluster-up BATS that cover the tunnel block are still green;
    - `python3 scripts/check-doc-links.py`.
12. **Scope:** `git diff --stat` shows only the files named above.

## Definition of Done

- [ ] R1–R4 complete; gates 1–12 pass, with output pasted.
- [ ] Commit message, exactly (trailers on consecutive lines):

  ```
  feat(make): make hub-recover / hub-restore restore a rebuilt hub's Keychain-backed state in one run

  Co-Authored-By: Codex <noreply@openai.com>
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`. If `.git` writes are denied, say so and leave the changes uncommitted, **unstaged** (do not `git add`).

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, or use `--no-verify`.
- Do NOT edit `memory-bank/`, `scripts/lib/foundation/` or `scripts/lib/acg/`.
- Do NOT read or print any Keychain value, Vault secret, Kubernetes Secret data, `~/.cloudflared/*.json` or `cert.pem`.
- Do NOT call `signing_init` or `sudo` anywhere in the new code.
- Do NOT run anything live: no real make target, dispatcher, launchctl, security, kubectl, k3d or Docker.
- Do NOT change what any existing make target does, except the one `alertmanager-secret` backup line.

## Follow-up found live (Claude, 2026-10-03 12:45) — NOT in the current Codex run; brief after it lands

`hub_recovery_reconcile` fails at `_hub_recovery_replay_identity_hook` with
`applications.argoproj.io "shopping-cart-identity" not found`.

**The hub-only path never creates the hub's identity stack.**
- The `shopping-cart-identity` Application (Keycloak + LDAP from `shopping-cart-infra`) is applied
  to the hub only by `bin/cluster-up` Step 10c, a sandbox `make up`.
- Its Vault inputs are seeded only by `deploy_shopping_cart_data` (sandbox Step 10b):
  `keycloak/admin`, `keycloak/clients`, `keycloak/smoke-user` and `ldap/admin`.
- Claude applied the same Application by hand at 12:40. ESO then failed with "Secret does not exist"
  on all four paths (404, not 403), and `postgres-keycloak` was stuck in `CreateContainerConfigError`.

**The hub's public origins are also sandbox-path only.** The local agents behind them are installed
only by `bin/cluster-up`:
- `argocd.3ai-talk.org` → `127.0.0.1:8080` (the argocd-port-forward agent, missing);
- `keycloak.3ai-talk.org` → `127.0.0.1:8880` (the keycloak-port-forward agent, missing);
- `frontend.3ai-talk.org` → the sandbox frontend, so it is legitimately down while the sandbox is
  down.

These fired `PublicEndpointDown` (critical, `cluster=hub`) as SMS once Alertmanager was restored.
Claude added a 6 h silence, `84a19233`.

**Direction:** `hub-up` / `hub-restore` should own every *hub* component:
- the identity Application;
- the identity Vault seeding, split out of `deploy_shopping_cart_data`;
- the ArgoCD and Keycloak port-forward agents.

The sandbox path keeps only sandbox things. Gate: after a stubbed `make hub-recover`, nothing
hub-side is left for a sandbox `make up` to create.

### Follow-up F2 — embeddings key Vault copy (found 2026-10-03, about 19:40Z) — FIXED (see commit below)

The hub rebuild lost `secret/embeddings/gemini`. The Hermes LaunchAgent cannot read the keychain
item, so it falls through to that Vault copy. As a result, every 8-minute tick logs
`vectordb index failed: index-docs: 0 of 100 documents were committed`, and the VectorDB Health
dashboard shows rows=0 against a corpus of 1802 with "Last run result: failed".
**Correction (2026-10-03):** do not read the keychain. `gemini-cli-api-key`'s ACL trusts only the
Gemini CLI, and `security -w` returns rc 36 with **no stderr and empty output**. A copy step built on
it wrote `api_key: ""` to Vault live. Instead, `bin/hub-restore` prompts with `read -rs`, refuses an
empty value (SKIP), and writes it with the stdin-only pattern in `docs/guides/vector-store.md`.
Gate: an empty prompt makes no `vault kv put` call.

### F2 — fix (spec, for Codex)

Add an **Embeddings key** step to `bin/hub-restore`, directly after *Hub reconcile*. At that point
Vault is up and the root token Secret exists.

1. **Step bookkeeping:**
   - insert `"Embeddings key"` into `_step_names` after `"Hub reconcile"`;
   - renumber the later `_step_start` calls;
   - replace every hard-coded `/8` and the `{1..8}` summary loop with the array length
     (`${#_step_names[@]}`), so adding a step never needs a second edit.
2. **Present check:** test only the length of the value.
   - Pipe the root token from `secret/vault-root` (`-n secrets`, `--context "${_hub_context}"`) into
     `kubectl exec -i vault-0 -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv get
     -mount=secret -field=api_key embeddings/gemini 2>/dev/null | wc -c'`.
   - A count greater than 1 means present → `_info "[hub-restore] embeddings key present in Vault"`
     and PASS.
   - The value itself must never reach a variable, stdout or a log.
3. **Absent, stdin is a TTY:** use an injectable `_hub_restore_stdin_is_tty` helper (`[[ -t 0 ]]`) so
   BATS can override it.
   - Prompt with `read -rs -p "Gemini embeddings API key (Enter to skip): " _gemini_key`, then print
     a newline.
   - **Empty input:** SKIP, with `_info` naming `docs/guides/vector-store.md` for the manual command.
   - **Otherwise:** write with the stdin-only pattern, `{ printf '%s\n' "$root_token";
     GEMINI_KEY="$_gemini_key" jq -n '{api_key: env.GEMINI_KEY}'; } | kubectl ... exec -i vault-0
     -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv put -mount=secret
     embeddings/gemini -'`. Run it under `_no_trace` if available in this script, otherwise with
     `set +x` scoped around it.
   - Then `unset _gemini_key`. Re-run the length check from 2: PASS if it is greater than 1, FAIL
     otherwise.
4. **Absent, no TTY:** SKIP, with `_info` "embeddings key missing from Vault — run make hub-restore in
   a terminal, or see docs/guides/vector-store.md".
5. **Never read the keychain** for this key (see the correction above). Do not add any
   `security find-generic-password` call.
6. **Docs:** in the `docs/howto/hub-rebuild-from-gitops-vault.md` hub-restore step list, add the
   Embeddings key step (one line).

**Gates (offline; stub `kubectl`, `jq` real, `make` and `curl` stubbed as in `hub_restore.bats`):**
- present (`wc -c` stub prints `40`): no prompt and no `kv put`; step PASS.
- absent + TTY + empty input: no `kv put`; step SKIP; the overall exit is unaffected by SKIP.
- absent + TTY + key `test-key-123`: exactly one `kv put`. The string `test-key-123` does not appear in
  the kubectl stub's **argv** log or in the script output; it appears only in the captured stdin.
- absent + no TTY: no prompt, no `kv put`; step SKIP.
- the summary prints 9 rows.
- Mutation:
  - remove the empty-input guard → the empty-input test goes red;
  - hard-code `/8` back → the 9-row test goes red;
  - restore from a `cp` snapshot and confirm with `cmp`. Never use `git checkout`.
- shellcheck has no new warnings; `hub_restore.bats` and `makefile_signing_restore.bats` are green.
- `git diff --stat` shows only `bin/hub-restore`, `scripts/tests/bin/hub_restore.bats` and the howto.

**Commit message (exact):**

```
fix(hub-restore): restore the embeddings key to Vault from a hidden prompt so the Hermes index tick stops failing after a rebuild

Co-Authored-By: Codex <noreply@openai.com>
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

## Follow-up F2b (2026-10-03, live): the root-owned preflight flags root daemons' own lock folders

On the first live run in Terminal.app, `make hub-restore` stopped with exit 2. It listed
`k3s-aws/logs/keycloak-browser-http.log.lock` and `k3s-hostinger/logs/keycloak-browser-http.log.lock`.
Those are `LOCK_DIR`s that the **root** `keycloak-browser-http` LaunchDaemon wrapper creates with
`mkdir`. Being root-owned is correct for them, and they are not the defect the check exists for
(a root-owned **logs** folder that a user agent cannot write to).

**Fix (Codex):** in `bin/hub-restore`, exclude lock folders from the scan:

```bash
  _root_owned_dirs="$(find "${_state_base}" -maxdepth 3 -type d -user root ! -name '*.lock' 2>/dev/null || true)"
```

**Gates:**
- In `scripts/tests/bin/hub_restore.bats`, the `find` stub must now honour the filter. Make the
  stub print the root-owned path only when its argv has no `! -name *.lock`, or assert the argv.
  The test then shows that a root-owned `*.lock` folder no longer fails the run and that a
  root-owned `logs` folder still does.
- Mutation: removing `! -name '*.lock'` turns the new test red. Restore from a `cp` snapshot
  and check with `cmp`.
- `hub_restore.bats` and `makefile_signing_restore.bats` pass, shellcheck adds no new warnings,
  and only those two files change.

## Follow-up F2c (2026-10-03, live): Verify races the Grafana restart from step 8

The first full live run (Terminal.app, 17:37 PDT) passed steps 1–8, then failed 9/9 Verify. Read
straight afterwards, all four checks pass: Vault 200, Grafana 200, the SMTP Secret is present and
the tunnel has a PID. The cause is a race. Step 8 runs `launchctl kickstart -k` on
`com.k3d-manager.grafana-port-forward` (last exit -15; `grafana-pf.log` restarted at 17:37:30), and
step 9 probes `:3001` straight away, before the new port-forward is listening.

**Fix (Codex):** in `bin/hub-restore` step 9, retry the Grafana probe up to 15 times, one second
apart, before marking it FAIL:

```bash
_grafana_ok=0
for _grafana_try in $(seq 1 15); do
  if [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:3001/api/health 2>/dev/null || true)" == "200" ]]; then
    _grafana_ok=1; break
  fi
  sleep 1
done
if (( _grafana_ok )); then
  _info "[hub-restore] Grafana health: PASS"
else
  _info "[hub-restore] Grafana health: FAIL"; _verify_ok=0
fi
```

**Gates:**
- BATS: a `curl` stub returns `000` for its first 2 Grafana calls and then `200`. Verify passes,
  and the stub records 3 Grafana calls.
  - Stub `sleep` as a no-op on PATH.
  - Keep the `curl` stub's default `200` for every other test.
- A second BATS test: a stub that always returns `000` for Grafana makes Verify FAIL after 15 calls.
- Mutation: going back to a single probe turns the first test red. Restore from a `cp` snapshot
  and check with `cmp`.
- `hub_restore.bats` and `makefile_signing_restore.bats` pass, shellcheck adds no new warnings,
  and only those two files change.
