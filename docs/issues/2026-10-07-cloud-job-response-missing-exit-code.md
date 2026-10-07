# Cloud job response omitted the Make exit code

## Observed behavior

Cloud job `470f0304` reported `body.status: failed`, but the response did not include the numeric
Make exit code in either the response body or the summary artifact. The response did include six
failure entries, source locations, a bounded final tail, and credential redaction.

## Root cause

The webhook persisted terminal status and logs but did not persist the Make return code. The
`/api/v1/status/{job_id}` response therefore had no exit-code field for cloud-bridge to relay.

## Fix and verification

Make jobs now persist `exit_code`, and the status API includes it as an integer. Existing summary
artifact fields remain unchanged. A focused lifecycle regression test verifies persistence; the
next cloud request must confirm the field is returned to the requestor.
