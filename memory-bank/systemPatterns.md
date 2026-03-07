# System Patterns – k3d-manager

## 1) Dispatcher + Lazy Plugin Loading

- `scripts/k3d-manager` is the sole entry point; it sources core libraries unconditionally
  and loads plugins **only when a function from that plugin is first invoked**.
- Benefit: fast startup; unused plugins never load.
- Convention: plugin files must not execute anything at source time (no side effects).

## 2) Configuration-Driven Strategy Pattern

Three environment variables select the active implementation at runtime:

| Variable | Selects | Default |
|---|---|---|
| `CLUSTER_PROVIDER` | Cluster backend | Auto-detects OrbStack on macOS when running, otherwise `k3d` |
| `DIRECTORY_SERVICE_PROVIDER` | Auth backend | `openldap` |
| `SECRET_BACKEND` | Secret backend | `vault` |

Consumer code calls a generic interface function; the abstraction layer dispatches to the
provider-specific implementation. Adding a new provider requires a single new file — no
changes to consumers.

## 3) Provider Interface Contracts

### Directory Service (`DIRECTORY_SERVICE_PROVIDER`)
All providers in `scripts/lib/dirservices/<provider>.sh` must implement:

| Function | Purpose |
|---|---|
| `_dirservice_<p>_init` | Deploy (OpenLDAP) or validate connectivity (AD) |
| `_dirservice_<p>_generate_jcasc` | Emit Jenkins JCasC `securityRealm` YAML |
| `_dirservice_<p>_validate_config` | Check reachability / credentials |
| `_dirservice_<p>_create_credentials` | Store service-account creds in Vault |
| `_dirservice_<p>_get_groups` | Query group membership for a user |
| `dirservice_smoke_test_login` | Validate end-user login works |

### Secret Backend (`SECRET_BACKEND`)
All backends in `scripts/lib/secret_backends/<backend>.sh` must implement:

| Function | Purpose |
|---|---|
| `<backend>_init` | Initialize / authenticate backend |
| `<backend>_create_secret` | Write a secret |
| `<backend>_create_secret_store` | Create ESO SecretStore resource |
| `<backend>_create_external_secret` | Create ESO ExternalSecret resource |
| `<backend>_wait_for_secret` | Block until K8s Secret is synced |

Supported: `vault` (complete). Planned: `azure`, `aws`, `gcp`.

### Cluster Provider (`CLUSTER_PROVIDER`)
Providers live under `scripts/lib/providers/<provider>.sh`.
Supported: `orbstack` (macOS, auto-detected when `orb` is running), `k3d` (Docker runtime), `k3s` (Linux/systemd).

## 4) ESO Secret Flow

```
Vault (K8s auth enabled)
  └─► ESO SecretStore (references Vault via K8s service account token)
       └─► ExternalSecret (per service, maps Vault path → K8s secret key)
            └─► Kubernetes Secret (auto-synced by ESO)
                 └─► Service Pod (mounts secret as env or volume)
```

Each service plugin creates its own ExternalSecret resources.
Vault policies must allow each service's service account to read its secrets path.

## 5) Jenkins Certificate Rotation Pattern

```
deploy_jenkins
  └─► Vault PKI issues leaf cert (jenkins.dev.local.me, default 30-day TTL)
       └─► Stored as K8s Secret in istio-system
            └─► jenkins-cert-rotator CronJob (runs every 12h by default)
                 ├─► Checks cert expiry vs. JENKINS_CERT_ROTATOR_RENEW_BEFORE threshold
                 ├─► If renewal needed: request new cert from Vault PKI
                 ├─► Update K8s secret in istio-system
                 ├─► Revoke old cert in Vault
                 └─► Rolling restart of Jenkins pods
```

## 6) Jenkins Deployment Modes

| Command | Status | Notes |
|---|---|---|
| `deploy_jenkins` | **BROKEN** | Policy creation always runs; `jenkins-admin` Vault secret absent |
| `deploy_jenkins --enable-vault` | WORKING | Baseline with Vault PKI TLS |
| `deploy_jenkins --enable-vault --enable-ldap` | WORKING | + OpenLDAP standard schema |
| `deploy_jenkins --enable-vault --enable-ad` | WORKING | + OpenLDAP with AD schema |
| `deploy_jenkins --enable-vault --enable-ad-prod` | WORKING* | + real AD (requires `AD_DOMAIN`) |

## 7) JCasC Authorization Format

Always use the **flat `permissions:` list** format for the Jenkins matrix-auth plugin:

```yaml
authorizationStrategy:
  projectMatrix:
    permissions:
      - "Overall/Read:authenticated"
      - "Overall/Administer:user:admin"
      - "Overall/Administer:group:Jenkins Admins"
```

Do NOT use the nested `entries:` format — causes silent parsing failures.

## 8) Active Directory Integration Pattern

- AD is always an **external service** (never deployed in-cluster).
- `_dirservice_activedirectory_init` validates connectivity (DNS + LDAP port probe).
- **Local testing path**: `deploy_ad` — OpenLDAP with `bootstrap-ad-schema.ldif`. Test users: `alice` (admin), `bob` (developer), `charlie` (read-only). All password: `password`.
- **Production path**: set `AD_DOMAIN`, use `--enable-ad-prod`. `TOKENGROUPS` strategy is faster for nested group resolution.
- `AD_TEST_MODE=1` bypasses connectivity checks for unit testing.

## 9) `_run_command` Privilege Escalation Pattern

Never call `sudo` directly. Always route through `_run_command`:

```bash
_run_command --prefer-sudo -- apt-get install -y jq   # sudo if available
_run_command --require-sudo -- mkdir /etc/myapp        # fail if no sudo
_run_command --probe 'config current-context' -- kubectl get nodes
_run_command --quiet -- might-fail                     # suppress stderr
```

`_args_have_sensitive_flag` detects `--password`, `--token`, `--username` and
automatically disables `ENABLE_TRACE` for that command.

## 10) Idempotency Mandate

Every public function must be safe to run more than once:
- "resource already exists" → skip, not error.
- "helm release already deployed" → upgrade, not re-install.
- "Vault already initialized" → skip init, read existing unseal keys.

## 11) Cross-Agent Documentation Pattern

`memory-bank/` is the collaboration substrate across AI agent sessions.
- `projectbrief.md` — immutable project scope and goals.
- `techContext.md` — technologies, paths, key files.
- `systemPatterns.md` — architecture and design decisions.
- `activeContext.md` — current branch, open items, decisions in flight.
- `progress.md` — done / pending tracker; update at session end.

`activeContext.md` must capture **what changed AND why decisions were made**.

## 12) Agent Role Boundaries

| Agent | Owns | Never does |
|---|---|---|
| **Codex** | Production code, security vulnerability fixes | Cluster ops, test authorship |
| **Gemini** | BATS test authorship, integration tests, cluster verification, red team | Production code changes |
| **Claude** | memory-bank instructional writes, PR management, issue routing | Takes action without owner go-ahead |

**Gemini test ownership:**
- BATS unit tests (`scripts/tests/`) — written after Codex delivers production code
- Integration tests (`test_vault`, `test_eso`, `test_istio`, etc.) — owned and maintained by Gemini; only Gemini has live cluster access to validate them
- Red team tests — adversarial, bounded to existing security controls

**Gemini red team scope:**
- Test `_copilot_prompt_guard`, `_safe_path`, stdin injection, trace isolation
- Attempt credential leakage via proc/cmdline, PATH poisoning, prompt bypass
- Report findings as structured report in memory-bank — never modify production code
- Claude reviews findings and routes fixes to Codex

## 12) Test Strategy Pattern

- Avoid mock-heavy orchestration tests that assert internal call sequences.
- Keep BATS for pure logic (deterministic, offline, no cluster required).
- Use live-cluster E2E smoke tests for integration confidence.

```bash
./scripts/k3d-manager test smoke
./scripts/k3d-manager test smoke jenkins
```

## 13) Agent Boundary Security

Every agent handoff (Claude → Codex, Claude → Gemini, memory-bank reads) is treated
as a network perimeter crossing. Rules:

- **No credentials in task specs or reports.** Actual credential values, cluster
  addresses, kubeconfig paths, and tokens must never appear in `docs/plans/`,
  `memory-bank/`, or agent output. Reference env var names only (`$VAULT_ADDR`,
  `$KUBECONFIG`, etc.). Live values stay on the owner's machine.
- **memory-bank and docs/plans/ are Instruction Code.** Any agent write to these
  files must be reviewed by Claude before the next agent reads them — they are a
  prompt injection surface.
- **Minimize context to sub-agents.** Task specs include only what the agent needs
  for the specific task — not full project history, not cluster state, not credentials.
- **Validate agent output before acting.** Claude reviews every Codex/Gemini diff
  before commit. `_agent_lint` (when implemented) automates architectural validation.

## 14) Red-Team Defensive Patterns

- **PATH Sanitization**: `_safe_path` validates `PATH` before any copilot/agent invocation. Rejects world-writable dirs (sticky-bit is NOT an exemption) and relative/empty entries. Uses glob-safe `IFS=':' read -r -a` array split.
- **Secret Injection via stdin**: Token + payload piped into pod's bash via stdin; extracted with `while IFS="=" read -r key value` loop. Token never appears in `kubectl exec` args or `/proc/*/cmdline`.
- **Prompt Guard**: `_copilot_prompt_guard` checks 8 forbidden shell fragments before any copilot invocation.
- **Trace Isolation**: `ENABLE_TRACE`/`DEBUG` auto-disabled by `_args_have_sensitive_flag` for commands with `--password`, `--token`, `--username`.
- **AI Gate**: `K3DM_ENABLE_AI=1` must be explicitly set; all copilot invocations route through `_k3d_manager_copilot`.

## 15) Agent Commit & Communication Protocol

Agents (Codex, Gemini) **self-commit their own work** as a sign-off. Claude does not
re-commit on their behalf.

**Memory-bank is the two-way communication channel:**
- Agents write to memory-bank to report completion — Claude reads this to detect issues.
- Claude writes to memory-bank to instruct next steps — agents read this to act.

**PR review routing** — after Claude opens a PR, issues are routed by scope:
- Small/isolated → Claude fixes directly in the branch
- Logic/test fix → back to Codex via memory-bank task
- Cluster verification → Gemini via memory-bank task

**Claude's review gate remains**: Claude reads every agent memory-bank update before
writing the next task. This is where inaccuracies, overclaiming, and stale entries are
caught — not by blocking agent writes.

## 14) Agent Rigor Protocol

`scripts/lib/agent_rigor.sh` — requires `system.sh` sourced first (dependency guard via `declare -f _err`).

- `_agent_checkpoint` — commits the current working state with a spec-derived message before any surgical operation. Prevents partial-fix loss.
- Pattern: spec → checkpoint → implement → verify → Claude review → commit.
