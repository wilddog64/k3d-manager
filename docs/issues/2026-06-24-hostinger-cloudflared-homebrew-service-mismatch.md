# Issue: Hostinger `make refresh` hit a stale Homebrew `cloudflared` service instead of the repo-managed tunnel

**Date:** 2026-06-24  
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`  
**Area:** `scripts/lib/providers/k3s-hostinger.sh`, Cloudflare tunnel launchd wiring

## What was tested

I checked the active Cloudflare tunnel service after `make refresh CLUSTER_PROVIDER=k3s-hostinger` failed to expose `argocd.3ai-talk.org`.

## Actual output

The machine was running Homebrew's `cloudflared` LaunchAgent in an error loop:

```text
cloudflared error 1        cliang ~/Library/LaunchAgents/homebrew.mxcl.cloudflared.plist
```

`launchctl` showed the same service with no tunnel arguments:

```text
gui/501/homebrew.mxcl.cloudflared = {
  path = /Users/cliang/Library/LaunchAgents/homebrew.mxcl.cloudflared.plist
  state = spawn scheduled
  program = /opt/homebrew/opt/cloudflared/bin/cloudflared
  arguments = {
    /opt/homebrew/opt/cloudflared/bin/cloudflared
  }
  last exit code = 1
}
```

The cloudflared log repeated the startup hint instead of running a tunnel:

```text
use `cloudflared tunnel run` to start tunnel bb7ece59-8680-4310-9437-232f862e2773
```

The repo-managed tunnel plist was not present at the expected path:

```text
/Users/cliang/Library/LaunchAgents/com.k3d-manager.cloudflare-tunnel.plist
```

## Root cause

`make refresh` assumed the Cloudflare tunnel was already managed by the repo's launchd label, but this machine had drifted to the Homebrew-managed `homebrew.mxcl.cloudflared` service. That service starts the binary without the repo's `tunnel run --config ~/.cloudflared/config.yml` arguments, so it never reaches the configured ingress map.

## Recommended follow-up

- Keep the Hostinger refresh path provider-agnostic by stopping a stale Homebrew `cloudflared` service when present.
- Recreate and bootstrap the repo-managed `com.k3d-manager.cloudflare-tunnel` LaunchAgent from `scripts/etc/cloudflared/config.yml`.
- Keep the existing Hostinger-specific path intact so `make refresh CLUSTER_PROVIDER=k3s-hostinger` still works after switching providers.
