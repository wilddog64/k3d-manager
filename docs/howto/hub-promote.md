# Promoting changes to the live hub

The hub reads the `deploy/hub` branch. Release and feature branches do not
reach the running hub until an operator promotes a commit.

## First promote (bootstrap)

Before switching the ApplicationSets to `deploy/hub`, run `make appsets-check`
on the currently deployed release branch. The pre-change check identifies the
release ref the hub reads. Promote that branch's current head so the new
`deploy/hub` ref points to the same content:

```sh
make hub-promote REF=<currently-deployed-release-branch>
make appsets-reapply
make appsets-check
make platform-ops
```

The content the hub reads must not change during this ref switch. The first
check confirms the old release ref; after reapplying, the second check confirms
`deploy/hub`.

## Promote

Promote a commit that is reachable from an `origin` branch and has completed
successfully in GitHub Actions:

```sh
make hub-promote REF=k3d-manager-v1.43.15
```

The command prints the old and new hub revisions and up to 30 intervening
commit subjects. Type `promote` at its terminal prompt to update the branch and
record an annotated `hub-promote/<UTC timestamp>` tag. Then check the rendered
ApplicationSets and apply platform resources:

```sh
make appsets-check
make platform-ops
```

If GitHub checks are unavailable during an outage, `BREAK_GLASS=1` skips only
the check-run gate. The commit must still be on `origin`, and the terminal
confirmation and promotion record are still required:

```sh
make hub-promote REF=<commit-ish> BREAK_GLASS=1
```

## Roll back and inspect

`make hub-rollback` uses the promotion tags as a stack: after promoting A, B and
C, successive rollbacks move to B and then A. When you want to move forward
again, promote that commit explicitly with `make hub-promote REF=<commit-ish>`.

`make hub-promote-status` prints the current hub SHA, the last three promotion
tags, and the current release branch's ahead count. It does not change refs.

`make appsets-reapply` pins both ApplicationSet stages to `deploy/hub`, even
when run from a feature or release checkout. Use `APPSETS_STAGE=hub` to apply
only the hub stage.

`make platform-ops` fetches `origin/deploy/hub`, extracts that commit into a
temporary directory, and runs the platform-ops deploy from the extracted tree.
The temporary tree is removed after success or failure.
