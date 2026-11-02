# Role gate verification environment

The initial focused BATS run encountered a sandbox loopback restriction:

```text
not ok 72 acg-up Vault port cleanup kills the listener but not a connected client such as an ssh -R tunnel
# (from function `_start_vault_port_fixture' in file scripts/tests/bin/cluster_up.bats, line 1108,
#  in test file scripts/tests/bin/cluster_up.bats, line 1123)
#   `_start_vault_port_fixture' failed
# Traceback (most recent call last):
#   File "<string>", line 2, in <module>
#     s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",0)); s.listen(4)
#                                                                               ~~~~~~^^^^^^^^^^^^^^^^^
# PermissionError: [Errno 1] Operation not permitted
# cat: /tmp/bats-run-RQTg81/test/72/port: No such file or directory
```

The test needs loopback socket access. Rerun the focused suites with that access. Live E2 and E3 require the operator's M4 and M5 respectively and were not attempted.

The initial ShellCheck command also reported an existing warning, subsequently corrected:

```text
In bin/k3dm-machine-setup line 65:
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
                      ^----^ SC2088 (warning): Tilde does not expand in quotes. Use $HOME.
```

The rerun with loopback access passed all 157 cases; the complete TAP output is at `/private/tmp/k3dm-role-gates-final` for this session.
