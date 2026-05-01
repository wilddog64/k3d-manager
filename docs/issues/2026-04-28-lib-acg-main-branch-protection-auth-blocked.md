# Issue: lib-acg main branch protection could not be enabled from Codex session

**Date:** 2026-04-28
**Status:** Resolved after GitHub CLI re-authentication
**Severity:** Medium

## What Was Attempted

After lib-acg PR #2 merged and k3d-manager pulled the subtree, the user requested enabling branch protection on `wilddog64/lib-acg` `main`.

The GitHub connector confirmed repository admin-level metadata access:

```text
repository_full_name: wilddog64/lib-acg
permissions.admin: true
default_branch: main
```

However, the installed connector exposes repository, PR, issue, review, merge, and file operations, but does not expose a branch-protection update operation.

Local GitHub CLI authentication was checked:

```text
$ gh auth status
github.com
  X Failed to log in to github.com account wilddog64 (/Users/cliang/.config/gh/hosts.yml)
  - Active account: true
  - The token in /Users/cliang/.config/gh/hosts.yml is invalid.
  - To re-authenticate, run: gh auth login -h github.com
  - To forget about this account, run: gh auth logout -h github.com -u wilddog64
```

The only token-like environment variable available in the session was tested against the GitHub API without printing its value:

```text
$ curl -sS -o /tmp/lib-acg-user.json -w '%{http_code}\n' -H "Authorization: Bearer ${HOMEBREW_GITHUB_API_TOKEN}" -H 'Accept: application/vnd.github+json' https://api.github.com/user
401
```

## Actual Behavior

Initial branch protection attempt was blocked because the session did not have a working GitHub API auth path.

## Root Cause

Codex has no available write-capable GitHub API auth path for branch protection:

- GitHub connector does not expose branch protection mutation.
- Local `gh` token is invalid.
- Available environment token returns `401`.

## Resolution

After the user re-authenticated `gh`, branch protection was applied to `wilddog64/lib-acg` `main`.

Command:

```text
$ gh api --method PUT repos/wilddog64/lib-acg/branches/main/protection -H 'Accept: application/vnd.github+json' --input -
```

Applied policy:

```text
required_pull_request_reviews.required_approving_review_count: 1
required_pull_request_reviews.dismiss_stale_reviews: true
enforce_admins.enabled: true
allow_force_pushes.enabled: false
allow_deletions.enabled: false
required_conversation_resolution.enabled: true
```

Verification:

```text
$ gh api repos/wilddog64/lib-acg/branches/main/protection --jq '{enforce_admins: .enforce_admins.enabled, required_approving_review_count: .required_pull_request_reviews.required_approving_review_count, dismiss_stale_reviews: .required_pull_request_reviews.dismiss_stale_reviews, required_conversation_resolution: .required_conversation_resolution.enabled, allow_force_pushes: .allow_force_pushes.enabled, allow_deletions: .allow_deletions.enabled}'
{"allow_deletions":false,"allow_force_pushes":false,"dismiss_stale_reviews":true,"enforce_admins":true,"required_approving_review_count":1,"required_conversation_resolution":true}
```

## Recommended Follow-Up

If lib-acg adds named required CI checks later, update branch protection to require those status checks explicitly.

Suggested command shape:

```text
gh api --method PUT repos/wilddog64/lib-acg/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  --input <branch-protection-json>
```

Do not enable an empty required-status-checks set as a substitute for real CI requirements; add concrete status check context names once stable.
