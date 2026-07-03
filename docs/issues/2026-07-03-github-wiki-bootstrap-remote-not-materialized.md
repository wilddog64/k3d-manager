# GitHub wiki bootstrap blocked because `.wiki.git` remote is not materialized

## What was attempted

Prepared an initial operator wiki for `wilddog64/k3d-manager` with these pages:

- `Home`
- `Architecture`
- `Operations`
- `Observability`
- `Slack Commands`
- `Troubleshooting`
- `_Sidebar`

The content was staged in a temporary local wiki git repo at:

```text
/private/tmp/k3d-manager-wiki
```

## Actual output

Repo metadata confirms the repo has wiki enabled:

```text
$ gh repo view --json nameWithOwner,url,description,hasWikiEnabled,defaultBranchRef
{"defaultBranchRef":{"name":"main"},"description":"","hasWikiEnabled":true,"nameWithOwner":"wilddog64/k3d-manager","url":"https://github.com/wilddog64/k3d-manager"}
```

But the wiki web endpoint still redirects back to the repo root:

```text
$ curl -Ik https://github.com/wilddog64/k3d-manager/wiki
HTTP/2 302
location: https://github.com/wilddog64/k3d-manager
```

SSH wiki clone/push fails because the wiki repo does not exist:

```text
$ git clone git@github.com:wilddog64/k3d-manager.wiki.git /tmp/k3d-manager-wiki
Cloning into '/tmp/k3d-manager-wiki'...
ERROR: Repository not found.
fatal: Could not read from remote repository.
```

```text
$ git -C /private/tmp/k3d-manager-wiki push -u origin master
ERROR: Repository not found.
fatal: Could not read from remote repository.
```

Unauthenticated HTTPS also reports the wiki git remote as missing:

```text
$ git ls-remote https://github.com/wilddog64/k3d-manager.wiki.git
remote: Repository not found.
fatal: repository 'https://github.com/wilddog64/k3d-manager.wiki.git/' not found
```

Toggling the repo wiki setting off and back on via `gh repo edit` did not materialize the backend.

## Root cause

GitHub reports `has_wiki=true`, but the backing wiki repository has not been created yet. The normal `.wiki.git` remote remains unavailable, and the available CLI/API tools in this environment do not provide a direct "create first wiki page" endpoint.

In practice, this was a GitHub bootstrap condition where the first wiki page had to be created through the GitHub web UI before the `.wiki.git` remote existed.

## Resolution

The repo owner created the first placeholder `Home` page in the GitHub web UI. After that:

```text
$ git ls-remote git@github.com:wilddog64/k3d-manager.wiki.git
64f615da26fededfd12def105c5f95b6a77d93b3	HEAD
64f615da26fededfd12def105c5f95b6a77d93b3	refs/heads/master
```

The prepared starter wiki was then rebased on top of the UI-created `Home` page and pushed successfully:

```text
$ git -C /private/tmp/k3d-manager-wiki push -u origin master
To github.com:wilddog64/k3d-manager.wiki.git
   25c08f4..64f615d  master -> master
branch 'master' set up to track 'origin/master' by rebasing.
```

A fresh verification clone showed the published pages:

```text
Architecture.md
Home.md
Observability.md
Operations.md
Slack-Commands.md
Troubleshooting.md
_Sidebar.md
```

## Follow-up

No further bootstrap action is required. Future wiki edits can now use the normal wiki git remote:

```bash
git clone git@github.com:wilddog64/k3d-manager.wiki.git
```
