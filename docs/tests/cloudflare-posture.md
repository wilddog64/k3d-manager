# Cloudflare posture helper tests

`python3 -m pytest -q scripts/tests/bin/test_cloudflare_posture.py` exercises the helper with local fixtures and injected network/TLS seams only. It makes no live Cloudflare or public endpoint requests and requires no installed packages beyond Python's standard library and pytest in the test environment.

Coverage includes zero-access default/dry-run behavior; sanitized snapshot shapes and unknown values; fixed HTTPS GET URL, redirect/error handling, and bounded response behavior; absence of token leakage; all seven fixed hosts and four forced TLS versions; unauthenticated HTTP/HTTPS redirect status distinction; certificate validation and SNI; and classification of edge protocol rejection separately from local unsupported protocol, certificate, DNS, timeout, and unknown failures.

The helper's actual `--check` command is an explicit operator action and can contact the Cloudflare API and the seven public hostnames. Tests mock those access paths. Test success is offline evidence only and does not establish current zone settings, public edge behavior, authentication success, or LIVE-VERIFIED status.

The suite blocks real sockets and uses the actual urllib opener with injected HTTP/HTTPS handlers. It asserts redirects are not followed, proxy environment discovery is disabled, API tokens occur only on fixed HTTPS Cloudflare GETs, public requests have no Authorization or body, timeout values are passed, and public/error bodies are never read. Dry-run/help tests forbid environment lookups, credential access, file access, process execution, and opener construction.

Regression fixtures reproduce arbitrary snapshot/API value and Location path disclosure, mismatched API IDs, local low-version misclassification, and client context ValueError crashes. API cases include HTTP 403, unsuccessful envelopes, malformed JSON, missing/wrong IDs, extra fields, secret-looking text, and oversized responses. Snapshot fixtures cover accepted shapes, bounded reads, invalid types, duplicate IDs, and snapshot provenance; unknown telemetry remains unknown and report completion never means F0 passed.

Every host/protocol pair invokes the real TLS probe with a real local SSLContext and fake sockets. Tests assert both actual minimum and maximum versions, SNI, hostname/certificate validation, negotiated-version observations, and timeout. Failure fixtures exercise structured peer protocol-version alerts separately from local configuration, no-protocol/no-cipher, ambiguous handshake, certificate, DNS, and timeout errors. No TLS failure text is emitted.
