# ACG credential test aborted before reclaiming stale CDP listeners

## Symptom

`make credential-test PROVIDER=aws` exited immediately while probing `127.0.0.1:9222`, and the
managed browser later logged:

```text
ERROR:net/socket/socket_posix.cc:175] bind() failed: Address already in use (48)
DevTools listening on ws://[::1]:9222/devtools/browser/...
```

At the time of investigation, two Chrome listeners existed:

```text
Google 12976 ... TCP 127.0.0.1:9222 (LISTEN)
Google 91089 ... TCP [::1]:9222 (LISTEN)
```

The IPv4 probe failed while an IPv6 listener remained. The launcher then attempted another browser,
which could not bind the port.

## Root cause

`_browser_launch` only reclaimed a listener when the HTTP probe succeeded but Playwright could not
drive the browser. A failed IPv4 probe skipped that branch. In addition, the nonzero probe needed to
be captured explicitly so `set -e` could not abort before recovery.

## Fix

The upstream `lib-foundation` fix adds `_cdp_port_has_listener`, checks all IPv4/IPv6 listeners with
`lsof` after a failed probe, reclaims the port, and explicitly captures the probe exit status. It is
synced into this repository from upstream commits `f6bb7bb` and `c7f7b37`.

## Verification

With an isolated writable `HOME`, the focused suite passes:

```text
1..5
ok 1 _browser_launch: reuses the CDP browser and runs the session check when it is healthy
ok 2 _browser_launch: reclaims an undriveable CDP browser then relaunches the managed Chromium
ok 3 _browser_launch: launches the managed Chromium then runs the session check
ok 4 _browser_launch: reclaims an IPv6-only listener when the IPv4 CDP probe fails
ok 5 _browser_launch: K3DM_ACG_SKIP_SESSION_CHECK=1 still bypasses the session check end-to-end
```

Shellcheck and the agent-rigor audit passed. The live credential target remains blocked by the local
Chrome/9222 session state and does not constitute a successful end-to-end credential extraction.
