# Full pytest blocked by sandbox localhost-bind restrictions

**Date:** 2026-10-07
**Task:** ask-docs ISO-date redaction false-positive fix
**Scope:** verification only; unrelated to the changed redaction code

## Attempted command

```text
make test-pytest
```

## Actual output

```text
=================================== FAILURES ===================================
_____________ test_network_blocks_non_loopback_and_allows_loopback _____________

    def test_network_blocks_non_loopback_and_allows_loopback():
        if os.environ.get("K3DM_HERMETIC") == "report":
            pytest.skip("enforce-only guard assertion")
        with pytest.raises(RuntimeError, match=r"network"):
            socket.create_connection(("192.0.2.1", 80), timeout=0.1)
        listener = socket.socket()
>       listener.bind(("127.0.0.1", 0))
E       PermissionError: [Errno 1] Operation not permitted

scripts/tests/bin/test_hermetic_guard.py:63: PermissionError
_____________ test_push_to_local_throwaway_server_receives_payload __________

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x1073e3a80>

    def test_push_to_local_throwaway_server_receives_payload(monkeypatch):
        received = []
    
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
    
            def do_POST(self):
                received.append(self.rfile.read(int(self.headers["Content-Length"])).decode())
                self.send_response(200)
                self.end_headers()
    
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
E       PermissionError: [Errno 1] Operation not permitted

scripts/tests/bin/test_k3dm_test_metrics.py:128: PermissionError
============= 2 failed, 690 passed, 2 skipped in 95.28s (0:01:35) ==============
make: *** [test-pytest] Error 1
```

## Root cause and follow-up

The execution sandbox denies localhost socket binding, so these pre-existing network tests
cannot complete in the default environment. The changed ask-docs suite passed independently
(31/31). Rerun the full pytest gate in an environment that permits loopback sockets before
release verification; do not change unrelated tests for this task.
