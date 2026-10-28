# October26 webhook offsite incident — historical cause follow-up

**Status:** OPEN investigation — current service recovered, not an active outage
**Date:** 2026-10-28
**Original incident:** [webhook offsite unresponsiveness](../bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md)

The October26 approximately07:20PDT offsite interruption was not reproduced.
Retained bridge SSH connect-to-github.com:22 Undefinederror0 lines correlate
with the incident window but do not identify a cause. A distinct no-agent SSH
auth gap was reproduced and fixed; it does not prove it caused this interruption.
Contemporaneous original launchd/process/listener/local-HTTP evidence is absent,
so cannot retrospectively establish m4outage, handlercrash or tunnel/networkcause.

Current operator local doctor11:44:33Z onOct28 was authenticatedhealthy/all_oktrue,
with listener7443 and no recoveryrecommended. After separate operator bridge
reload, request20261028T114826Z-health completed11:49:51Z HTTP200/statusok/all_oktrue,
21checksok. EarlierSlackjob a13d5831delivered. Full actual outputs are in
[batch evidence](2026-10-28-three-bug-luna-batch-verification.md); current-state
recovery and unknown historical cause remain distinct.

No new implementation task is warranted without a reproduced defect or fresh
failure evidence. On recurrence capture UTC timestamp and bounded redacted
make webhook-doctor JSON first; do not dump credentials/env/rawlaunchctl/logs.
If credentialaccess or timeoutwithlistener is inconclusive, inspect that context
before recovery. If localHTTPhealthy, investigateexternalpath without restarting
webhook. If localjob/handlerconfirmedunhealthy, atmostone operator recovery,
then localHTTPandcompletedexternalreply evidence; stoponfailure, no restartloops.
If host unavailable, use independentmonitoring ratherthan infer outagecause.
[Heartbeat monitoring follow-up](../bugs/2026-10-26-independent-heartbeat-healthchecks-monitoring.md)
remains separate. Record any actual recurrence as a new actionable bug and link it.

This is a documentation-only split of the causal question. No new live commands,
service change, credential access or screenshot export performed for this follow-up.
