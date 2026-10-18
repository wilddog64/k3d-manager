# Copilot findings — shopping-cart-infra PR #115 (product image slug tag)

**Date:** 2026-10-18

## Finding

`scripts/tests/bin/minio-image-art.bats`: the marker loop runs `missing 1 2`, but only the `2` case
set `MC_MARKER`. The `1` iteration repeated the missing-marker case, so the refresh path for a
non-empty older version was never tested.

## Fix

shopping-cart-infra `2ba6108`: every case except `missing` sets `MC_MARKER="${marker}"`.

## Root cause / process note

Codex's test and red check both passed, because the missing-marker case also triggers a refresh.
A table-driven test needs each row to vary the input it names. When reviewing one, check that the
loop variable actually reaches the stub.
