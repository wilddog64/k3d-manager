# show-service-passwords output fixtures

Captured on m4-air.local on 2026-11-19 from commit `12a14c9d` using the Bats harness and its scratch HOME, scratch TMPDIR, fake MAKE, and stubbed `kubectl`/`curl` commands.

Command:

```sh
MAKEFILE="$TMPDIR/Makefile.pre" CAPTURE_BASELINE=1 bats --filter 'M4: stdout matches captured pre-fix fixtures byte for byte' scripts/tests/bin/makefile_show_service_passwords.bats
```
