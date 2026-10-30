# Hub recovery tests cannot recursively copy an existing workspace socket

Curated batch regression output:

```text
not ok 1261 recover B4-20: refused preflight prevents hub-recover
# (in test file scripts/tests/plugins/hub_data.bats, line 929)
#   `cp -R "$PWD" "$copy"' failed
# cp: cannot create special file '/tmp/bats-run-SPTKOs/test/1261/root/repo/-e': Operation not permitted
not ok 1274 recover B4-22: teardown failure prevents rebuild and resume
# (in test file scripts/tests/plugins/hub_data.bats, line 1095)
#   `chmod +x "$script"; cp -R "$PWD" "$copy"; cp "$script" "$copy/scripts/k3d-manager"' failed
# cp: cannot create special file '/tmp/bats-run-SPTKOs/test/1274/root/repo/-e': Operation not permitted
```

Read-only workspace observation:

```text
srwx------ 1 cliang staff 0 Oct 26 15:19 ./-e
```

The source workspace already contains a Unix socket named -e, predating this
batch. These unchanged tests recursively copy the whole workspace including
that socket. No evidence of a production hub recovery failure. Recommended
separate follow-up: use a controlled tracked-file fixture rather than copying
arbitrary operator workspace state. Did not delete the socket or modify the
out-of-scope recovery suite. Full suite failures remain reported honestly.

The final run also failed B4-21 (test1272) and B4-23 (test1275) on the same socket-copy operation. All four full failures are captured in [the batch output](../assets/2026-10-27-six-bug-curated-tests.txt).
