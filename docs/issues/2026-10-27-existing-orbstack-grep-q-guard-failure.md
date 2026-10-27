# Existing OrbStack upgrade pipeline fails the repository grep-q guard

During six-bug batch regression, `./scripts/k3d-manager test all` reported:

```text
not ok 130 grep-q guard: no non-allowlisted pipeline retains -q
# (in test file scripts/tests/lib/grep_q_pipe_guard.bats, line 13)
#   `[ "$status" -eq 1 ]' failed
```

Running the guard's search directly returned:

```text
bin/k3dm-orbstack-upgrade:168:forecast_ok=0; curl -fsS "$PUSHGATEWAY_URL/metrics" | grep -q '^k3dm_release_forecast' && forecast_ok=1
```

Confirmed present at pre-batch record `adf2af4e`; last file commit:

```text
2a729c11 feat(orbstack): coordinated upgrade with preflight, recovery and report
```

`grep -q` may close the producer pipe early. Recommended scoped follow-up:
consume the producer fully and redirect grep output instead; run the guard
and OrbStack focused suite. This is outside the six selected bug scopes and
was not modified. Full curated run output is retained with the batch evidence.
