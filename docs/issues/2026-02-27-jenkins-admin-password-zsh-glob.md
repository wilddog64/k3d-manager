# Jenkins admin password contains `*` – zsh globbing breaks curl commands

**Date:** 2026-02-27
**Status:** INFO / Documentation

## Summary

When following the troubleshooting workflow, running commands such as:

```bash
curl -sk -u jenkins-admin:*** http://127.0.0.1:8081/job/linux-agent-ad-hoc/lastBuild/consoleText
```

fails immediately in zsh with:

```
zsh: no matches found: jenkins-admin:***
```

The cluster seeds `jenkins-admin` with a random password that may contain `*` and `?`. In zsh,
unquoted arguments containing these characters are interpreted as glob patterns before `curl`
executes, so the shell errors out before the HTTP request runs.

## Workaround / Fix

Always quote the `-u` argument, or better yet, construct it via shell variables so the password is
exported with quoting handled automatically:

```bash
ADMIN_USER=$(kubectl -n jenkins get secret jenkins-admin -o jsonpath='{.data.jenkins-admin-user}' | base64 -d)
ADMIN_PASS=$(kubectl -n jenkins get secret jenkins-admin -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)
curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" http://127.0.0.1:8081/api/json
```

If typing manually, wrap the credential in single quotes to avoid globbing:

```bash
curl -sk -u 'jenkins-admin:tS[M):FY[5x_Qi6.w5:?{}e&' http://127.0.0.1:8081/api/json
```

## Action

Documented here so future runbooks mention quoting. No code changes required.
