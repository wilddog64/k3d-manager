# Bug: `make help` does not list `dr-drill` / `dr-drill-publish` or say which Mac each runs on

**Status:** OPEN — capture
**Priority:** P3
**Introduced by:** `82c1d9c8` (v1.43.14, `bin/dr-drill-publish` with the `m2jump` default)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** `docs/bugs/2026-11-04-dr-drill-publish-opaque-m2-ssh-auth-failure.md` (exact-slug glob; `make find-similar-docs` unavailable: vector store context `k3d-k3d-cluster` missing) — read, different root cause (stale key on the peer, not the wrong host)
**Filed:** 2026-11-28
**Detected by:** operator, running `make dr-drill-publish` on m2 right after `make dr-drill` passed there
**Branch:** `k3d-manager-v1.47.0`

## Evidence

On m2-air, 2026-11-28, after a successful `make dr-drill`:

```
make dr-drill-publish
ssh: Could not resolve hostname m2jump: nodename nor servname provided, or not known
make: *** [dr-drill-publish] Error 255
```

`bin/dr-drill-publish:5` defaults `DR_DRILL_HOST="${K3DM_DR_DRILL_HOST:-m2jump}"`: it runs on the operator's Mac (m4 or
m5), fetches the newest result from m2 over SSH, and pushes it to `k3dm-hub-data` with that Mac's GitHub key. `m2jump`
is defined only in the operator Macs' `~/.ssh/config`. The same command run from m4 succeeded at once (`results`
`f0bccdb`, `20261128T133233Z.json`).

`make help` (`Makefile:2394`) lists neither `dr-drill` nor `dr-drill-publish`, so nothing tells the operator that the
drill runs on m2 and the publish on m4/m5.

## Fix (proposed, small)

Add two lines to `make help`:

- `make dr-drill          Run the DR drill (on m2)`
- `make dr-drill-publish  Publish m2's newest drill result (on m4/m5; fetches from m2jump)`

Optional, if the operator wants it: `bin/dr-drill-publish` prints `run this on m4 or m5, not on m2` when `m2jump` does not
resolve (`ssh -G m2jump` returns the alias itself as the hostname) instead of the raw SSH error.
