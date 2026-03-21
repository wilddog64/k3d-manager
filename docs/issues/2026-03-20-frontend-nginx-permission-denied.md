# Issue: frontend CrashLoopBackOff due to Nginx Permission Denied

**Date:** 2026-03-20
**Status:** OPEN
**Component:** `shopping-cart-frontend`

## Symptoms

The `frontend` pod on the Ubuntu k3s cluster is in `CrashLoopBackOff`. Logs show:
```
2026/03/21 00:56:07 [emerg] 1#1: mkdir() "/var/cache/nginx/client_temp" failed (13: Permission denied)
nginx: [emerg] mkdir() "/var/cache/nginx/client_temp" failed (13: Permission denied)
```

## Root Cause

The container is likely running as a non-root user (e.g., UID 101), but the Nginx configuration or the base image expects root privileges to create directories in `/var/cache/nginx`.

## Mitigation

- Update the Dockerfile or SecurityContext to ensure the user has write access to `/var/cache/nginx`.
- Or, configure Nginx to use a writable directory for temporary files (e.g., `/tmp`).
