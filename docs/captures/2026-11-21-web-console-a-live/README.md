# Web console part A live E11–E14, 2026-11-21 (m5-air)

Host m5-air (macOS 26.5.1), OpenSSH_10.2p1, checkout 74ff9a6f (contains the sudo fix 0f39c31a); installed blobs
bin 6a60abcf, lib cf0b1fc6. Operator ran every root step at the m5 terminal (tmux pane on m4 over ssh); Claude ran the
read-only reads and an unprivileged helper (`~/wc-live.sh`, throwaway CA `SHA256:2oFWfnIc…`, keys deleted afterwards).
Login and home redacted to `<login>` and `~`. Spec: `docs/plans/v1.45.0-web-console-a-console-sshd.md`.

| Item | Files | Result |
|---|---|---|
| E11 | `e11.txt`, `readback.txt` | install one sudo authentication (one mistyped try), check C1–C7, C10 PASS, C8 WARN, C9 INFO; one `127.0.0.1.42722 LISTEN` owned by `sshd:10271` = launchctl pid, uid 0; root:wheel, no ACL; log 0600; fresh LAN Remote Login from m4 worked. |
| E12 | `e12.txt`, `server.log`, `readback.txt` | good certificate accepted and held; `-L`, `-D`, `-W` refused (client `administratively prohibited`, server `refused local port forward`); stream-local refused (server `refused streamlocal port forward`, as P6; client says `connect failed`); `-R` client `remote forward failure`, server silent; sftp `subsystem not found`; `-A -tt` request sent, only the forced command ran, server silent; password: no attempt possible (publickey only); plain key, wrong CA, wrong principal (`name is not a listed principal`), expired (`Certificate invalid: expired`) refused. X11 and tunnel by read-back (`x11forwarding no`, `permittunnel no`). Enabled control: P6, `docs/captures/2026-11-19-web-console/c17b-enabled.txt`. The first `e12` run's W, sftp and four credential rows (`rc=0`, empty) are a helper bug (perl exec of a shell function); the `E12b` rerun rows are the evidence. |
| E13 | (2026-11-19) `../2026-11-19-web-console/c11-login1.txt`, `c12-unpriv.txt` | marker ZDOTDIR: marker present; empty zdotdir: absent, entry logs ZDOTDIR and parent `sshd-session @notty` (uid 501). |
| E14 | `e14-pre.txt`, `e14-post.txt`, `e14-final.txt` | held client 23756 (port 51982, server side `sshd-session:23760` uid 501) cut; revoke rc 0, `port 42722 (installed)`; after 10 s no live row, fresh connect refused, no plist, `launchd.plist.revoked` and `revoked` present, `launchctl print` rc 113 `Could not find service` (P2 shape); Claude's held m4→m5 Remote Login ran a command at 15:04:05Z, the operator's m4→m5 pane kept working, m4 `tmux has-session -t =work` ok (m5 runs no tmux server, hence `rc=1` in the files); second revoke rc 0; uninstall PURGE=1 rc 0; nothing left, no `.prev`. |
