# Slack find-similar-docs live verification failed

**Date:** 2026-10-21
**Related bug:** `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md`

## Attempted

The operator ran the Slack `/k3dm find-similar-docs` command with a natural-language `Q` value, twice, after the offline fix was landed.

## Actual output

The operator screenshot showed these two repeated response sequences (message text transcribed verbatim; the screenshot clips the target name):

```text
Queuing make find-similar-docs…
⚠️ invalid value for Q

Queuing make find-similar-docs…
⚠️ invalid value for Q
```

## Findings and limits

The live attempt failed. In the landed source, the relay acknowledgment is `Request received for make …; validating…`, not `Queuing make …`; the backend `Q` validation accepts printable ASCII, including apostrophes. The screenshot's acknowledgment is not enough to identify which component generated it or prove that the relay is stale. It also does not show the exact submitted query.

## Release-branch trace

Deployment baseline for this investigation is `k3d-manager-v1.43.5`, not `main`. The inspected checkout contains both fixes (`74d79eac`, `997587d6`) and the current source path is internally consistent:

- `workers/slack-relay/index.js:parseK3dm` preserves unkeyed words as part of free-text `Q`; its slash-command response is `Request received for make …; validating…`.
- For thread replies, `bin/k3dm-webhook:_handle_thread_command` uses `shlex.split`, so `Q="what's recent e2e-remote issues"` becomes one argument; the Slack quote characters are syntax and the apostrophe remains part of the value.
- Both entrypoints send the target/args to the webhook's `/api/v1/make` handler, which calls `parse_make_request` and enforces target, role, required/optional key, and Q validation before starting the job.
- `scripts/lib/webhook/make_targets.py` accepts printable ASCII for `Q`, including apostrophes, with a 200-character maximum.
- `scripts/lib/webhook/lifecycle.py:_make_target_argv` base64-encodes `Q` before passing it across Make's recipe boundary.
- `Makefile` target `find-similar-docs` decodes `Q_B64` and passes the result to `scripts/find-similar-docs.py` as one argv value after `--`.
- `make deploy-worker` runs Wrangler from the checkout's `workers/slack-relay` directory and performs a smoke request. It deploys that local worker source.
- `make restart-webhook` kickstarts the local `com.k3d-manager.webhook` LaunchAgent, then invokes `restart-cloud-bridge`. The webhook launchd plist uses the checkout's `bin/k3dm-webhook` and repository root; the restart is needed to reload changed Python files.

No remaining code defect was found in the current slash-command Q parsing, validation, or Make transport path. The screenshot's `Queuing make …` acknowledgment and `invalid value for Q` error conflict with current relay/backend behavior, so an older or mixed rollout is a plausible explanation. The screenshot does not identify the responding component or show the exact query, so this is not proof that rollout/restart was skipped. No endpoint in the inspected source exposes the active worker or webhook source revision; runtime revisions remain unconfirmed.

### Read-only rollout checks

The current `/api/v1/health` response contains service names, health booleans, and details only (`bin/k3dm-webhook`, health route); it has no build, Git, or source revision field. A successful health response confirms reachability, not which checkout is serving requests. On the webhook host, these read-only commands establish the LaunchAgent's configured executable/repository path and compare that checkout with the required release commits:

```sh
launchctl print "gui/$(id -u)/com.k3d-manager.webhook"
plutil -p "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
git -C /path/from/the/launchd/ProgramArguments/repository rev-parse --show-toplevel
git -C /path/from/the/launchd/ProgramArguments/repository rev-parse --abbrev-ref HEAD
git -C /path/from/the/launchd/ProgramArguments/repository rev-parse HEAD
git -C /path/from/the/launchd/ProgramArguments/repository merge-base --is-ancestor 74d79eac HEAD
git -C /path/from/the/launchd/ProgramArguments/repository merge-base --is-ancestor 997587d6 HEAD
git -C /path/from/the/launchd/ProgramArguments/repository status --short --branch
```

Use the repository path found in the plist rather than assuming the interactive shell's current directory. These checks identify the configured checkout and its current source, but cannot prove that an already running process loaded that source after its last restart. The health route does not report a process build revision.

For the relay, inspect the Cloudflare Worker deployment history for `k3dm-slack-relay` (**Workers & Pages → k3dm-slack-relay → Deployments**) or use the read-only Wrangler command from this checkout:

```sh
cd workers/slack-relay
npx --yes wrangler deployments list
```

Deployment history can identify active version IDs, traffic allocation, and deployment time. The current Worker source does not expose its Git commit or an application version endpoint, so a version ID alone cannot prove that `74d79eac`/`997587d6` source was deployed. Correlate the active deployment time with rollout records/operator evidence; do not infer a stale Worker from the initial Slack acknowledgment.

If rollout is needed, run the documented commands from the confirmed release checkout. `make deploy-worker` deploys the source under that checkout's `workers/slack-relay` and performs its smoke request. `make restart-webhook` kickstarts the webhook LaunchAgent and also the cloud bridge when installed. These commands mutate deployment state and are for the operator only; they were not run during this investigation.

## Follow-up

On the deployment host, check out and update `k3d-manager-v1.43.5` through commit `997587d6` (including `74d79eac`), then run these commands from that checkout, in order:

```sh
git rev-parse --abbrev-ref HEAD
git merge-base --is-ancestor 74d79eac HEAD && git merge-base --is-ancestor 997587d6 HEAD
make deploy-worker
make restart-webhook
```

The first two commands confirm the release branch and that both fix commits are ancestors of the checkout. `make deploy-worker` publishes the local checkout's Cloudflare Worker source and runs its smoke request. `make restart-webhook` reloads the checkout's webhook through launchd and restarts the cloud bridge if its LaunchAgent is installed. These are the required rollout actions; repository state alone cannot establish whether they were previously run for this incident.

Then invoke `/k3dm find-similar-docs Q="what's recent e2e-remote issues"` in Slack. Confirm the request passes validation, the job completes, and retrieval receives the exact unchanged query. Record that both components were rolled out from the release checkout and attach the successful job/result evidence. Keep the canonical bug OPEN until this live check passes; the initial acknowledgment is not acceptance evidence.

## Investigation checks

## Successful live verification — 2026-10-21

The operator later supplied a Slack screenshot showing:

```text
✅ make find-similar-docs Q=what's recent e2e-remote issues succeeded — job 08ae7d06
Prior art for: "what's recent e2e-remote issues"
```

The response includes relevant prior-art results. This supersedes the earlier failed live attempts for acceptance: the exact query was accepted and retrieval returned results. The canonical bug is now LIVE-VERIFIED. The screenshot does not identify the deployed source revision, so none is inferred.

```text
check-doc-links: 2288 file(s) OK
1..8
ok 1 slack commands doc lists the cluster-status slash commands
ok 2 slack commands doc manifest matches the relay command set
ok 3 slack commands doc gives a concrete example for each command
ok 4 slack commands doc fix mode names the real FIX_CONTEXT override
ok 5 slack relay allowlist includes cluster-status and hostinger-status
ok 6 slack relay assigns remote-operator roles to cluster commands
ok 7 slack relay forwards remote-operator metadata headers
ok 8 slack relay parses cluster-diagnose payloads
```

The combined BATS run failed in its localhost HTTP cases. Actual output included:

```text
1..76
not ok 2 POST with wrong token returns 401
#   `[ "$status" -eq 0 ]' failed
not ok 20 Slack ignores signed unknown and user-less commands without creating anchors
#   `response="$(_slack_event '{"event":{"type":"message","user":"U-unknown","text":"/cluster-status","ts":"1"}}')"' failed with status 7
not ok 43 POST /cluster with response_url stored in job dir
#   `"${_WEBHOOK_URL}/api/v1/cluster")' failed with status 7
ok 49 Level 1: POST queues job and GET /status returns job output # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 51 Level 2: POST current chart version returns success without running make up # skip set K3DM_WEBHOOK_LEVEL2=1 to enable (requires cluster)
ok 52 Level 3: tunnel rejects wrong token with 401 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
```

The same 76-case command was repeated with `--jobs 1` and failed on the same category of localhost cases. A separate run of `bats --print-output-on-failure scripts/tests/lib/webhook.bats` passed all 68 cases; six live/cluster-gated cases were skipped by their documented environment guards. The slash-command suite passed 8/8 above. The contrasting result suggests a local HTTP test harness/port issue, but its root cause was not established. `git diff --check` and `_agent_audit` exited 0. No ShellCheck target applies because this documentation-only change touched no shell files.

## Redispatched investigation task

**Task:** Codex investigation `01a160e6-0c57-7dd1-a894-3d20546d63b1`

Treat the current release branch as the intended deployment source. Inspect the Slack relay and webhook code paths, identify safe read-only ways to establish which release-branch revisions are active (or state if runtime revision cannot be queried), and document the component-specific rollout/restart steps and live acceptance check. Determine whether any remaining parser/validation defect exists in the landed code. Do not deploy, restart services, change deployment triggers, or duplicate an already-correct implementation.

**Files:**

- `docs/issues/2026-10-21-slack-find-similar-docs-live-verification-failed.md`
- `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md` (read-only reference)
- `.github/workflows/deploy-worker.yml` (read-only reference; supplementary, not the release-branch deployment baseline)
- `docs/architecture/webhook-server.md` (read-only reference)
