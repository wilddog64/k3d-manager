# Full `make test-all` fails on stale webhook thread mock

**Date:** 2026-10-07  
**Command:** `make test-all` from tmux pane `20261004195335:2.1`  
**Result:** 2,531 total cases, 1 failed

## What passed

The previously reported cloud failures did not recur:

```text
1..1386
...
ok 972 hub snapshot: capture emits the restore layout
ok 973 hub snapshot: tree names satisfy hub recovery claim tree
ok 974 hub snapshot: node placement comes from the PV
ok 976 hub snapshot: capture probes no remote free space
ok 983 hub snapshot: staging directory is 0700
ok 1386 every rule keeps string labels and its own annotations
```

The 332-case `scripts/tests/bin` suite also passed.

## Actual failure

```text
FAILED scripts/tests/bin/test_webhook_ask_docs_thread.py::test_ask_docs_thread_runs_without_channel_and_replies_in_parent_thread

E TypeError: test_ask_docs_thread_runs_without_channel_and_replies_in_parent_thread.<locals>.<lambda>() got an unexpected keyword argument 'channel_id'

bin/k3dm-webhook:1170: in _notify_job
    ts = _post_slack_bot(text, thread_ts=thread_ts, channel_id=channel_id)
```

Final result:

```text
============= 1 failed, 717 passed, 2 skipped in 95.28s (0:01:35) ==============
[k3dm-test-metrics] 2531 cases, 1 failed
[k3dm-test-metrics] metrics push skipped (non-fatal): <urlopen error [Errno 61] Connection refused>
make: *** [test-all] Error 2
```

## Root cause assessment

This is a test regression in `scripts/tests/bin/test_webhook_ask_docs_thread.py`. The
webhook implementation now passes `channel_id` to `_post_slack_bot`, but the test's lambda
stub has not been updated to accept that keyword. The failure is deterministic and is not a
Slack or webhook-service outage.

The Pushgateway connection refusal was non-fatal and did not cause the pytest failure.

## Recommended fix

Update the test stub to accept `channel_id` and assert the expected channel/thread routing,
then rerun the focused webhook-thread test and the complete `make test-all`.
