# Independent heartbeat tests

`scripts/tests/bin/test_heartbeat.py` covers zero-I/O dry-run for each role, full role/config validation, deceptive webhook URLs, reader credential selection, response schema, redirect rejection, UUID-only provider endpoints, owner-only secret files, per-check fault isolation and aggregation, failure/recovery/provider errors, maintenance and clock bounds, two-minute cadence, concurrent lock lifetime, stale lock recovery, and role-specific non-overwriting Python/scheduler rendering. Hermes and bridge marker producers are tested in their existing suites. All tests use fixture paths and fake I/O; they do not provision accounts or claim external alert delivery.

Focused command: `pytest -q scripts/tests/bin/test_heartbeat.py scripts/tests/bin/test_retrieval_probe.py scripts/tests/bin/test_cloud_bridge.py`; BATS command: `bats scripts/tests/bin/heartbeat.bats`.
