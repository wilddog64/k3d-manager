# Install and stop the console sshd on macOS

The console sshd accepts an SSH user certificate signed by the installed CA for the operator's login. It listens on IPv4 loopback. Part A gives no remote access alone. The forced command prints `console gate not installed` and exits 1 on every login until part C supplies the gate. D1 leaves Remote Login as it is. The hub sync reports a machine change when the launchd template changes.

Run the installer from a plain terminal as the operator, using a clean, committed checkout. Set `CA_FILE` to the CA **public** key. Check the three printed fingerprint fields (bits, SHA256 fingerprint and key type) against your CA before relying on the daemon.

```sh
make install-web-console-sshd CA_FILE=/path/to/test-ca.pub
make web-console-sshd-check
```

The default port is 42722. To change it, set `WEB_CONSOLE_SSH_PORT` to a free decimal port in 1024–49151. An empty value, 2022, 2200–2299, 8022, 10222, 22222 and 32222 are refused. Install keeps the selected port or reports the reason it cannot use it. Uninstall part C before changing its port. Without a new CA the installer keeps the installed CA and prints its fingerprint. Without any CA it installs the files, parks the plist and returns 3. Run `bin/k3dm-web-console-sshd install --dry-run` to inspect the proposed configuration.

The gate runs through the operator's login shell, which must be `/bin/zsh`. The sshd sets `ZDOTDIR` to the empty, root-owned `/etc/k3dm-web-console/zdotdir` and disables the user SSH rc file. Install refuses if a system zshenv, its compiled copy, or the system sshrc exists.

The local check reports PASS for verified settings, FAIL for an unsafe or missing setting, WARN for an accepted or indeterminate setting and INFO for the Remote Login socket observation. A FAIL makes the command exit 1. Use `bin/k3dm-web-console-sshd check --strict` to count WARN as FAIL. Supply additional tunnel configuration files with repeated `--cloudflared-config PATH` arguments.

Run `make revoke-web-console-sshd` for an emergency stop. It records the revoke, parks the plist and stops the daemon and its identified console sessions. Exit 1 may identify an ambiguous socket owner that it did not signal. A pre-authentication connection can survive until the 30-second login grace period ends. Check again and rerun revoke. Rerun revoke after any interrupted install.

**R-REVOKE-CODE.** Revoke runs checkout code using the operator's sudo ticket. Independently inspect `netstat -anv -p tcp` for live sockets with local address `127.0.0.1.<port>`, confirm `launchctl print system/com.k3d-manager.web-console-sshd` reports the service missing and check `ls /Library/LaunchDaemons` for the absence of the console plist. Confirm a held console connection closed and a fresh one is refused. When part B is installed, revoke its route and verify removal in the Cloudflare dashboard from another device.

To restore the daemon after revoke, use `make install-web-console-sshd AFTER_REVOKE=1`. To remove it, run `make uninstall-web-console-sshd`. Add `PURGE=1` to remove the host key pair and the CA, including a throwaway test CA. Remove part C first if installed.

- **R-INSTALL.** The operator owns the checkout and watches the install. Compare the printed blob IDs with the remote tree to check the sources independently.
- **R-SUDO.** The default per-terminal sudo ticket stays usable during install and for its remaining lifetime. A process running as the operator on that terminal can use it. Run `sudo -k` afterwards to invalidate it.
- **R-CONFIG.** A process running as the operator can edit the tunnel configurations that C7 reads. Verify the route inventory through part B.
- **R-REPARENT.** A process that daemonizes before the stop snapshot can survive, including a detached tmux server. Revoke checks sockets and session descendants.
- **R-PORT-GAP.** While the daemon is down another local process can bind the console port. Part B stops the tunnel first.
