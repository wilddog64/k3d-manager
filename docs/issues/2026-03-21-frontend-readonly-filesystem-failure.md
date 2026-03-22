# Issue: Frontend Pod Fails on Start - Read-Only Filesystem (2026-03-21)

## Summary

The `frontend` pod is in a `CrashLoopBackOff` state. Investigation shows this is not a regression of the previously fixed `emptyDir` volume issue, but a new problem related to filesystem permissions.

## Evidence

Logs from the `frontend` container show the NGINX entrypoint script fails when trying to configure the server:

```
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
10-listen-on-ipv6-by-default.sh: info: can not modify /etc/nginx/conf.d/default.conf (read-only file system?)
```

This error indicates that the container's root filesystem is mounted as read-only. The NGINX image's default startup script requires write access to `/etc/nginx/conf.d/` to create the final server configuration.

The pod's graceful shutdown signals suggest this configuration failure leads to a failed readiness/liveness probe, causing Kubernetes to terminate and restart the pod in a loop.

## Next Steps

The `frontend` deployment manifest in the `shopping-cart-infra` repository needs to be reviewed. The `securityContext` for the container likely has `readOnlyRootFilesystem: true` set.

To fix this, one of two approaches can be taken:
1.  Set `readOnlyRootFilesystem: false`.
2.  Keep the read-only root and add a writable `emptyDir` volume mounted specifically at `/etc/nginx/conf.d/`.

Approach #2 is generally preferred for better security.
