# Copilot PR #112 Review Findings — v1.23.0

**PR:** [#112](https://github.com/wilddog64/k3d-manager/pull/112) — v1.23.0 CVE remediation observability + self-verification
**Date:** 2026-08-09
**Reviewer:** Copilot — 3 inline findings, all confirmed and fixed.

---

## Finding 1 — `Makefile:363,373` — Vault root token exposed on `curl` argv

**Copilot:** `show-service-passwords` passed the Vault root token directly on the `curl`
command line (`-H "X-Vault-Token: …"`), exposing it in process listings while the command
runs. The repo already uses a temp-header-file pattern (`scripts/plugins/observability.sh`)
to avoid leaking the token via argv.

**Root cause:** two new `curl` calls (Grafana + Prometheus credential lookups) inlined the
token into the header argument instead of reading it from a file — a secret-hygiene violation
(CLAUDE.md: "Vault tokens must never appear in script arguments visible in shell history or
CI logs").

**Fix — before:**
```makefile
_grafana=$$(curl -sf -H "X-Vault-Token: $$_vault_tok" \
  "http://127.0.0.1:18200/v1/secret/data/observability/grafana" ...
```
**after (both call sites):**
```makefile
_vault_hdr=$$(mktemp); printf 'X-Vault-Token: %s\n' "$$_vault_tok" > "$$_vault_hdr"; \
_grafana=$$(curl -sf -H "@$$_vault_hdr" \
  "http://127.0.0.1:18200/v1/secret/data/observability/grafana" ... ); \
rm -f "$$_vault_hdr"; \
```
Matches the `curl -H "@${_vault_hdr}"` pattern already used four times in `observability.sh`.

---

## Finding 2 — `vulnerability-inventory-exporter.yaml:243` — read-only root FS breaks cert-based scraping

**Copilot:** the exporter container sets `readOnlyRootFilesystem: true`, but the embedded
`exporter.py` writes client cert/key material via `tempfile.NamedTemporaryFile(delete=False)`.
Without a writable `/tmp`, that path fails at runtime (breaking app-cluster scraping when
`bearerToken` isn't present).

**Root cause:** the cert-based app-cluster auth branch (`context.load_cert_chain(...)`) needs
to materialize cert/key to disk; `tempfile` defaults to `/tmp`, which is read-only under the
hardened `securityContext`. Only exercised on the no-bearerToken path, so it passed the
bearer-token live test but would fail on a cert-configured app cluster.

**Fix:** add a writable `emptyDir` for `/tmp`, keeping `readOnlyRootFilesystem: true`:
```yaml
volumeMounts:
  - { name: tmp, mountPath: /tmp }
volumes:
  - { name: tmp, emptyDir: {} }
```

---

## Finding 3 — `vault.sh:2114` — unquoted `mount_path` in `sh -lc` command string

**Copilot:** `_vault_exec` runs the command string via `sh -lc`, so interpolating
`${mount_path}` unquoted into `vault secrets enable -path=${mount_path} …` lets shell
metacharacters in `mount`/`mount_path` alter the executed command. The helper is reusable and
should treat inputs as unsafe.

**Root cause:** the command string was built with plain interpolation instead of shell-safe
quoting before crossing the `sh -lc` boundary — a shell-injection surface (CLAUDE.md OWASP
A03) even though current callers pass constants.

**Fix — before:**
```bash
_vault_exec "$ns" "vault secrets enable -path=${mount_path} kv-v2" "$release"
```
**after:**
```bash
local enable_cmd
printf -v enable_cmd 'vault secrets enable -path=%q kv-v2' "$mount_path"
...
_vault_exec "$ns" "$enable_cmd" "$release"
```
`printf %q` emits a shell-safe token that survives re-parsing by `sh -lc`.

---

## Process notes

- **Secret-on-argv is a recurring class.** The temp-header-file pattern is the house standard
  (`observability.sh`); any new `curl` against Vault must use `-H "@<file>"`, never an inline
  token. Consider a spec/review rule: grep new diffs for `X-Vault-Token: ` inline in argv.
- **`readOnlyRootFilesystem: true` implies a writable `/tmp` audit.** Any container that hardens
  the root FS must be checked for `tempfile`/scratch writes and given an `emptyDir` for them.
- **Command strings crossing `sh -lc` must be built with `printf %q`.** `_vault_exec` /
  `_vault_exec_stream` re-parse their argument through a shell; interpolate variables with `%q`
  (matching the `printf -v role_cmd '…%s…'` sites that already quote with `""`).
