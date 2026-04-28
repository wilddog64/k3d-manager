# Issue: lib-acg main branch protection could not be enabled from Codex session

**Date:** 2026-04-28
**Status:** Blocked by GitHub API authentication/tooling
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

Branch protection was not enabled from this session.

## Root Cause

Codex has no available write-capable GitHub API auth path for branch protection:

- GitHub connector does not expose branch protection mutation.
- Local `gh` token is invalid.
- Available environment token returns `401`.

## Recommended Follow-Up

Authenticate `gh` with a token that has administration access to `wilddog64/lib-acg`, then apply branch protection for `main`.

Suggested command shape:

```text
gh api --method PUT repos/wilddog64/lib-acg/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  --input <branch-protection-json>
```

Recommended protection policy should be confirmed before applying, but should at minimum require pull requests before merge and require the repository CI check to pass before merging to `main`.
