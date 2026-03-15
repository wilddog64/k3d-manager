# Copilot Code Review Process

Applies to: k3d-manager, k3dm-mcp, shopping-cart-* repos, lib-foundation.

---

## When to Request a Copilot Review

- Every PR that touches `.sh` files, Go, Python, Java, or TypeScript source code.
- Every PR that adds or modifies GitHub Actions workflows.
- Skip for doc-only PRs (markdown, YAML config with no logic, `memory-bank/` updates).

---

## How to Request

GitHub Copilot review is **not automatic** on GitHub Pro — it must be manually requested.

```bash
gh pr edit <number> --add-reviewer copilot-pull-request-reviewer[bot]
```

Or via the GitHub UI: Reviewers → search "copilot" → select
`copilot-pull-request-reviewer`.

Re-trigger after new commits by commenting `@copilot review` on the PR.

---

## Severity Levels

| Level | Meaning | Merge gate |
|---|---|---|
| **P1** | Correctness or security bug — data loss, broken functionality, credential exposure | Block merge |
| **P2** | Latent bug — works today, breaks under plausible conditions (wrong OS, edge input, env variation) | Fix before merge when feasible; document if deferred |
| **Nit** | Style, consistency, docs — no functional impact | Fix opportunistically |

---

## Handling Findings

### For every finding:

1. **Read it critically.** Copilot is a first-pass screener, not an authority. Some findings
   are wrong or inapplicable — evaluate each one.

2. **Fix or explicitly reject.** Do not leave a finding silently unaddressed.
   - If fixing: commit the fix, reply to the thread with the commit SHA and a one-line
     explanation of what changed and why.
   - If rejecting: reply with the reason (e.g., "intentional design decision because X").

3. **Resolve the thread** after replying.

4. **Never mark a finding as resolved without a reply.** The reply is the record.

### Thread resolution command (GraphQL):

```bash
gh api graphql -f query='mutation {
  resolveReviewThread(input: {threadId: "<PRRT_...>"}) {
    thread { isResolved }
  }
}'
```

Get thread IDs:

```bash
gh api graphql -f query='{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: N) {
      reviewThreads(first: 30) {
        nodes { id isResolved comments(first:1) { nodes { body } } }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false) | .id'
```

---

## Documenting the Review

After all findings are addressed and threads resolved, create a review record:

1. Copy `docs/guides/copilot-review-template.md` to
   `docs/issues/YYYY-MM-DD-<feature>-copilot-review.md`.
2. Fill in all sections — header, quick summary, finding index, findings, lessons.
3. Commit the doc to the feature branch before merge.

**Naming convention:** `YYYY-MM-DD-<feature>-copilot-review.md`
Example: `2026-03-15-vcluster-copilot-review-findings.md`

The Lessons section is the most valuable part — write takeaways that a future agent or
engineer can apply without reading the full finding detail.

---

## Pre-Merge Checklist

Before merging any PR:

- [ ] Copilot review requested
- [ ] All P1 findings fixed
- [ ] All P2 findings fixed or explicitly documented as deferred with rationale
- [ ] All threads replied to and resolved
- [ ] Review record committed to `docs/issues/`

---

## Common Finding Patterns (accumulated across reviews)

These are bugs Copilot reliably catches. Write defensively against them upfront.

| Pattern | What to check |
|---|---|
| Shared namespace + `--delete-namespace` | Is this namespace shared? If yes, omit the flag. |
| `chmod 600` after file creation | Use `_write_sensitive_file` (umask 077 before create). |
| `uname -m` not checked on binary downloads | Always detect arch; never hardcode `amd64`. |
| `brew` with `--prefer-sudo` | Homebrew must run as current user. Never sudo brew. |
| Inner bash function definitions | Bash is global — use `__` prefix or move to file scope. |
| KUBECONFIG multi-file chain | Test with `KUBECONFIG=/a:/b` — never assume single file. |
| Substring match on user-supplied names | Use exact column parse or `=` comparison, not `*name*`. |
| DNS-label validation missing | Validate with `^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$` before path construction. |
| `@main` or `@latest` in Actions steps | Always pin to a version tag (`@v4`). |
| Floating image tags in Helm values | Always pin chart and image versions explicitly. |
