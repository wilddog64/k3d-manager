# Hostinger node outage — evidence review

**Reviewed:** 2026-10-20
**Scope:** Offline review of repository records only. No SSH, Hostinger panel/API, live cluster queries, or infrastructure changes were performed.
**Related bug:** `docs/bugs/2026-10-17-hostinger-node-unresponsive-then-rebooted.md`

## Established facts

- The public frontend returned HTTP 502 from 17:46 to 18:11 UTC on 2026-10-17. Other listed public endpoints remained reachable, consistent with the Hostinger origin being unavailable while the shared Cloudflare tunnel stayed up.
- Hostinger's recorded boot time was 18:10:52 UTC. All node pods restarted between 18:11:20 and 18:12:26 UTC.
- The previous-boot journal records `qemu-ga: guest-shutdown called` at 17:46:15 UTC, followed by `systemd-logind: System is powering down (hypervisor initiated shutdown)` and an orderly `poweroff.target`. The journal resumes after the next boot at 18:12:02 UTC.
- The reviewed journal contained no guest-initiated shutdown request, kernel OOM, hung-task warning, or soft-lockup line. This supports a hypervisor-initiated power-off; it does not identify who or what requested it.
- The Hostinger Prometheus sample gap from about 17:46 to 18:14 UTC and the reboot time align with the VM being powered off. The earlier description of a node hang is superseded by the journal evidence.
- A separate same-day read-only investigation found 252 CNI reservation files, with 207 not associated with a live sandbox. The associated bug record says stale host-local reservations persisted across the reboot. This is evidence of a separate pod IPAM problem, not evidence about who initiated the power-off.
- The Vault-after-reboot issue was separately fixed and live-verified. It establishes a reboot consequence that was observed at the time, not a cause of this shutdown.
- The 2026-10-20 multi-service incident is recorded as having no reboot during that incident window. Its API-path timeouts do not establish a recurrence of this 2026-10-17 event.

## Assessment and hypotheses

The outage was a period when the VM was powered off, rather than a guest that remained running but unresponsive. The journal attributes the orderly shutdown to the hypervisor. The initiating actor remains unknown.

Two possibilities remain: an operator-initiated stop/restart through hPanel, or a Hostinger-initiated maintenance/auto-recovery action. The repository contains no hPanel activity-log evidence that distinguishes them. Memory pressure was a plausible earlier hypothesis based on low available memory and major-fault bursts, but the reviewed journal has no OOM or hang evidence, and those metrics do not establish a shutdown cause.

## Evidence still needed from the operator

Provide the Hostinger hPanel VPS activity/event log covering **2026-10-17 17:45–18:11 UTC** (10:45–11:11 PDT), including the event timestamp, action, actor/source if shown, and result. A screenshot or exported log covering the full interval is sufficient if it shows whether the VPS was stopped/restarted manually or by Hostinger maintenance/auto-recovery. If the panel has no matching entry, provide that interval's log view or an explicit no-event result; the initiator would then remain unconfirmed.

The previous-boot journal has already been read and its material result recorded in the related bug. No further guest journal command is needed to answer who initiated the power-off; only the provider/operator activity record can resolve that question.

## Conclusion

The best-supported description is **hypervisor-initiated orderly VM power-off at 17:46:15 UTC, followed by boot at 18:10:52 UTC**. The incident was not shown to be a memory-pressure hang. Do not attribute the shutdown to the operator or Hostinger until the hPanel activity evidence is available.
