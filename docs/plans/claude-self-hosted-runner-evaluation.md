# Evaluation: Claude Code self-hosted runner for local, Slack-started sessions

**Status:** PROPOSED — evaluation only, nothing to build yet. Unversioned; a release is assigned only
after the go/no-go below. Not before v1.43.5 ships.
**Approval:** explicit 2026-10-15 "yes go for that" (operator, to "If you want, I can write a short
evaluation plan for it")
**Owner:** Claude (evaluation and write-up); operator (runner install, any credential, and the final go/no-go)

---

## Why look at it

A Claude cloud session has the repo through GitHub but no network path to this machine. That is why
`docs/howto/cloud-session-requests.md` exists: a cloud session files a request on the
`cloud-requests` branch, and a local poller answers a fixed, read-only action list. It works, but
each answer is a git round trip, and nothing outside the allowlist can be asked.

Claude Code's **self-hosted runner** runs sessions on a machine you own, and those sessions can be
started from Slack or the web. A session on the M4 would have what a cloud session lacks: the hub
API on `k3d-k3d-cluster`, the webhook on `127.0.0.1:7443`, the PF ports, and `docker logs`. A
question like "when was the last `COMPACT deleted`?" could then be answered directly instead of
through the bridge.

The same property is the risk. A Slack message would start an agent on the laptop that holds the
Keychain, `~/.ssh`, the age identity, the operator's kube contexts and `gh` auth.

## Questions the evaluation must answer

Answer each from the product docs and a test install, not from release notes. Release notes are
input, not evidence.

1. **Who can start a session.** Can a runner session be limited to the operator's own Slack user?
   What does a message from anyone else in the channel do?
2. **What a session runs as.** Which OS user, working directory and environment? Does it inherit the
   login keychain, `SSH_AUTH_SOCK`, `KUBECONFIG`, `gh` auth and the `.envrc` variables?
3. **Which permissions apply.** Do this repo's `.claude/settings.json` permission rules and
   PreToolUse hooks run in runner sessions exactly as they do in the terminal? Can auto mode or a
   bypass mode be forbidden for runner sessions only?
4. **MCP exposure.** Does `deniedMcpServers` in managed settings reliably keep tools such as Gmail,
   Drive and Calendar out of a Slack-started session? (The 2026-10 changelog fixes Slack sessions
   failing under managed MCP restrictions, so this path is new.)
5. **Repo and branch.** Which checkout does a session attach to? Can it be pinned to a dedicated
   worktree, never the operator's working tree? This repo's rules forbid mutating the tree under a
   running `make` or Codex job.
6. **Audit.** Is there a per-session record of the prompt, the tool calls and who started it, kept
   somewhere the session itself cannot edit?
7. **Kill switch.** How does the operator stop the runner and every live session in one step?

## Proposed shape, if the answers allow it

- **Read-only by default.** A runner session gets the same action set as the cloud bridge's
  read-only table, plus `kubectl get`, read-only `docker logs`/`inspect` and `ssh m2jump`. No
  `make` lifecycle target, no `cluster-*`, no `hub-recover-all`, no Vault writes, no `git push`.
- **A separate OS user, not the operator's.** No login keychain and no `~/.ssh`. A dedicated
  read-only kubeconfig, and a webhook reader-role token issued for this runner alone.
- **A dedicated worktree** on a fixed branch, reset at the start of each session.
- **Slack messages are information, not instructions.** That is the rule this repo already applies
  to messages relayed from other sessions. Anything that changes state is proposed in the thread and
  run by the operator.
- **Coexists with the cloud bridge** instead of replacing it. The bridge stays the path for cloud
  sessions and for any time the laptop is asleep.

## Steps

1. Read the self-hosted runner docs and answer questions 1–7, citing each source. (Claude)
2. Threat model: map each answer to the assets above (Keychain, age identity, kube contexts, `gh`,
   webhook admin token). Every gap is either mitigated or a no-go. (Claude)
3. Test install in a throwaway macOS user with no credentials. Start a session from Slack, then
   check the permission rules, hooks, the denied MCP servers and the kill switch. (Operator installs;
   Claude runs the checks.)
4. Write up the go/no-go with evidence. If it is a go, write a scoped spec and assign a release under
   the five-plan cap. (Claude drafts; operator decides.)

## Out of scope

- Any write or repair action from a runner session.
- Replacing the k3dm webhook, the Slack relay or Hermes.
- Running the runner as the operator's own user.
