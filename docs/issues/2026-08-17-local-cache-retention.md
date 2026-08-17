# Local cache retention and control-plane responsiveness

## Findings

The host filesystem was at 70% (`/dev/disk3s1s1`, 320G used of 461G). The largest
safe, repo-owned cache was `~/.cache/packer`, including an old ISO of about 2.35G;
15 stale `~/.cache/port` marker files were also present. OrbStack's 92G image/volume
store and Codex runtimes were not removed because they are not k3d-manager-owned.

The old Packer ISO and stale markers were removed manually after confirming they
were older than the retention window and not open by another process. Filesystem
usage fell to 318G used / 144G available (69%).

## Permanent prevention

`bin/k3dm-cleanup`, already scheduled daily at 03:00 by
`com.k3d-manager.cleanup`, now removes only unreferenced `*.iso`/`*.lock` files
older than 30 days from the exact Packer cache directory and marker files older
than 7 days from the exact port cache directory. The cleanup remains idempotent;
retention windows are configurable for tests or operators. OrbStack images,
volumes, Codex runtimes, and active logs remain out of scope.

## Verification

The new BATS regression creates old and recent artifacts under temporary HOME and
confirms only the old files are removed. Live cleanup is not run by the test suite.
