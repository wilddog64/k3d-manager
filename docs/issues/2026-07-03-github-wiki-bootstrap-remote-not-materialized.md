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

In practice, this looks like a GitHub bootstrap condition where the first wiki page must be created through the GitHub web UI before the `.wiki.git` remote exists.

## Recommended follow-up

1. Open the repo wiki in the GitHub web UI and create a single placeholder page manually.
2. Retry:

```bash
git -C /private/tmp/k3d-manager-wiki push -u origin master
```

3. Once the first web-created page materializes the wiki backend, push the prepared wiki content from `/private/tmp/k3d-manager-wiki`.
