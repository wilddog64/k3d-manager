---
name: Google Antigravity
description: Google's agent-first IDE platform; browser agent used to automate ACG sandbox extension
type: reference
---

## Google Antigravity

Agent-first IDE released late 2025. VS Code fork with a three-surface architecture:

| Surface | Role |
|---|---|
| Editor | Synchronous coding + inline completions |
| Manager | Orchestration layer — spawns multiple async agents across workspaces |
| Browser | Automated browser environment — agents verify UI/UX and perform web tasks |

Official site: antigravity.google
Docs: antigravity.google/docs
Skills library: github.com/rominirani/antigravity-skills
Unofficial CLI: github.com/michaelw9999/antigravity-cli (manipulates ~/.gemini/antigravity/brain/ artifacts)

## Relevance to k3dm-mcp

Antigravity's **Browser surface** can automate the ACG sandbox "Extend" button on the ACG web UI.

- ACG sandbox credentials are short-lived
- Can be extended +4 hours via the ACG Cloud Playground UI
- Antigravity browser agent automates this extension when k3dm-mcp fires a TTL warning
- k3dm-mcp emits a structured `extend_sandbox` action; Antigravity handles the browser interaction

Used in the v0.5.x shopping-cart e2e flow: deploy EKS → run Playwright → destroy cluster.
If TTL < 60 min before a long run, trigger Antigravity extension before proceeding.
