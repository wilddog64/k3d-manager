# ask-docs live count and thread verification failed

Result: FAIL in production; fresh-source offline checks PASS. Suspected stale
loaded runtime; reply-route cause still unconfirmed. No restart or code change
performed by coordinator. Stop the one-at-a-time queue at this item.

## Actual operator live evidence

Operator sent the requested missing-noun count question and supplied a Slack
screenshot at17:24local. It shows Only visible to you, Searching the docs,
and this answer:

```text
The provided documentation excerpts do not contain information about how many P1 bugs are open for v1.43.5.

Sources:
docs/issues/2026-10-27-ask-docs-priority-count-misses-bug-noun.md
docs/bugs/2026-10-12-bug-dashboard-open-counts-dont-say-what-to-do.md [P3 • open]
docs/plans/v1.43.4-bug-dashboard-defaults.md
docs/bugs/2026-10-27-ask-docs-priority-count-requires-bugs-word.md [P2 • closed]
docs/bugs/2026-10-22-bug-tally-counts-implemented-and-deferred-as-open.md [P3 • closed]
```

User reports no thread reply and suspects regression. Do not call this answer
zero bugs: it is semantic fallback, not a deterministic tally. The closed bug
source annotation reflects document status and is not proof the process loaded
the fix. No screenshot exported or unrelated image content recorded.

## Bounded read-only runtime investigation

Actual filtered process output:

```text
4295 1 Sun Oct 25 17:59:40 2026 /opt/homebrew/Cellar/python@3.15/3.15.1/Frameworks/Python.framework/Versions/3.15/Resources/Python.app/Contents/MacOS/Python /Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-webhook
```

Actual fix commit timestamp:

```text
b6704d68e04da578bc060cda96e19fe0ae94e5f2
2026-10-27T19:08:03-07:00
2026-10-27T19:08:03-07:00
checkpoint: before fix-omitted-noun-priority-count-routing
```

`bin/k3dm-webhook` imports `webhook.ask_docs` at startup, and ask_docs imports
bug_count at module scope. The process predates the patch by two days. Python
keeps imported module code in memory; no hot-reload path was found. This is
strong stale-runtime evidence, not an in-process bytecode inspection or proof
that all routing symptoms share one cause. A read-only source/Git check cannot
reload the service. Need controlled operator reload then exact same live test
before declaring the implementation regressed or resolved.

Bounded recent-job lookup matched the failed answer; sanitized actual facts:

```text
job_id: 58e47ff3
output_mtime_utc: 2026-10-29T00:26:05.461254+00:00
status: success
thread_ts file: absent
channel_id file: absent
response_url file: present (value never read/displayed)
thread_source file: absent
action file: absent
metadata.json: present
reply first line: The provided documentation excerpts do not contain information about how many P1 bugs are open for v1.43.5.
```

Success here only means the worker completed its fallback answer. It does not
verify semantic correctness or thread delivery. An earlier matching Oct27job
190bacfc had a channel/thread recorded, so it is not this fresh failed request.
No auth token, response URL, secret, request body or environment dump printed.

Installedplist filtered nonsecret fields:

```text
ProgramArguments: /opt/homebrew/bin/python3 /Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-webhook
SLACK_CHANNEL_ID: C0B7ZHG2LR4
K3DM_STATUS_CHANNEL_ID: C4CAEH8HX
```

These are installed configuration, not a proven read of the current process's
environment. Existing installed interpreter differs from current template's
pinned3.14; observed only, no interpreter install/plist rewrite or causal claim.

## Reply-route findings and remaining ambiguity

Current relay sends channel_id and response_url for /ask-docs, with optional
thread_ts. Current `_run_ask_docs` starts a bot thread only when bot token and
configured default channel are present and incoming channel equals that
configured channel. Otherwise it uses response_url. A failed bot header can
also fall back. Current HTTP ask_docs handler stores response_url but not a
channel_id file unless a bot thread was successfully created. Therefore the
missing saved channel cannot establish that the relay omitted channel_id.
No matching Slack bot-post rejection/error line was found by the bounded log
filter. Absence of a log does not prove the bot call succeeded or occurred.

The existing Oct1/Oct22 ask-docs thread-followup bug covers a different entry
path: an existing job-thread followup losing its parent's routing. Do not
reopen that incident or relax the no-default-channel guard from this screenshot
alone. Asked operator for invocation form and channel; answer pending. No new
thread implementation until the actual route is established/reloaded.

## Fresh-source checks

Read-only fresh import with retrieval/model callbacks replaced by raising
sentinels, exact missing-noun question. Actual output:

```text
fresh import exact question, retrieval/model forbidden: PASS
v1.43.5: 0 open P1 bug docs of 6 — 6 fixed, 0 open, 0 with no Status line.
_Counted from docs/bugs/ at HEAD `322b4634`; release = Branch: line, else the release the doc was added in._

Sources:
<https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/scripts/bug-tally.py|scripts/bug-tally.py>
```

This proves the current checked-out matcher/answer path bypasses retrieval;
it is not a live Slack pass. Preserve source revision when comparing counts.
Existing focused tests run under unchanged tripwire:

```sh
scripts/tests/tripwire.sh pytest -p no:cacheprovider scripts/tests/bin/test_bug_count.py scripts/tests/bin/test_ask_docs.py scripts/tests/bin/test_webhook_ask_docs_thread.py -q
```

Full actual output:

```text
........................................................................ [ 82%]
...............                                                          [100%]
87 passed in 5.54s
[tripwire] blocked 2 call(s) to host tools; none reached a real binary:
      1 security	find-generic-password -s k3dm-slack-signing-secret -a k3dm -w
      1 security	find-generic-password -s k3dm-slack-role-map -a k3dm -w
```

These cover current count routing and existing-thread behavior, not all live
slash-command/header failure modes. No new test or runtime file modified.
ShellCheck N/A Python tests/documentation-only investigation.

## Recommended single next step

Operator on M4 runs the existing reload target:

```bash
make restart-webhook
```

This reloads the webhook LaunchAgent and also restarts cloud-bridge; it loads
existing committed code, rather than changing credentials or adding a fix.
Coordinator has not run it. Then repeat the exact /ask-docs count question in
the same Slack channel, provide reply and invocation/channel context. Confirm
new process starttime/PID before accepting the result. No registry/cluster/
Cloudflare/Keychain changes, provider messages or auto-recovery included.

Before proposing reload, read-only persisted metadata showed0running jobs and
29queued records; newest queuedstatus timestamp2026-10-07T17:13:49Z, older than
current process. These are historical records, not proof of live workers or
permission to delete them. No cleanup performed. Do not equate them to29active
jobs or promise interruption-free restart from metadata alone.

## Tracking

Reopen the existing priority-count bug for failed live acceptance, retaining
its offline fix SHA/test evidence. Do not start the next P2 live test until
reload/retest resolves this item. Reply-route regression remains suspected,
not proven. Both memory-bank files updated; required staged lint/audit/hooks
before commit/push; no PR or new plan. No service mutation or secret read.

## Post-reload failure: deterministic tally timeout

Operator supplied another screenshot after successful user-agent reload:

```text
Only visible to you
19:23 k3d-manager Searching the docs…
Could not count bugs — tally failed (timeout).
Sources:
scripts/bug-tally.py
```

Matched persisted job6f069edf, outputmtime2026-10-29T02:24:14.402766Z;
thread_ts/channel_idfilesabsent. This differs from prior semanticfallback:
the deterministic route now runs, but its30s subprocess budget expires. It
is a new failed acceptance symptom after picking up the fix, not success.
No inaccuratezero-count or resolvedclaim. WebhookPID43179 andbridge43185
started2026-10-28T19:22:14PDT/running asindependentlyobserved. Exact old stale
module hypothesis no longer explains this new failure. Threadroute remains
unconfirmed until invocation/channel answer or traced request.

Read-only installed/loaded configuration has no K3DM_INDEX_REF override; repo
root is currentworkspace, git andpythonresolve/opt/homebrew/bin in bothtool
andinstalledPATH. No full environment/secret output.

Local bounded profile of actualscripts/bug-tally.py atHEAD:

```text
elapsed 5.137 git_stats {'ls-tree -r': [1, 0.025991875678300858], 'branch --show-current': [1, 0.022175582125782967], 'log --diff-filter=A': [1, 0.9430924169719219], 'tag --contains': [136, 2.824000097811222], 'log --reverse': [1, 0.628549000248313]} v1.43.5_P1 {'total': 6, 'closed': 6, 'open': 0, 'unknown': 0}
```

Same proc._spawn_capture_text launched fromaPythonthread, sameinterpreter,
actualtallyCLI--json--refHEAD/cwdworkspace/timeout30:

```text
{'elapsed': 3.632, 'rc': 0, 'timed_out': False, 'output_bytes': 258198, 'valid_json': True}
```

This does not reproduce live timeout. 136 tag calls/fixedhistory are measurable
work, not established cause of the30sfailure. No speculativeoptimization,
cache, timeoutincrease, fabricated exception or code fix introduced. Corpus
has909currentbugdocs,641explicitBranchreleases/268requiringfallback. Changing
release fallback/count semantics without evidence would risk wrongcounts.
Next collect bounded nonsecret process ancestry/stage timing duringoneoperator
repeat; keeptimeoutfailclosed andP2OPEN. No live requestbycoordinator, no
service/credential/Cloudflarechange. SeparateP3root-advicefiltertests6BATS
pass; that fix doesnot repairthiscountfailure.
