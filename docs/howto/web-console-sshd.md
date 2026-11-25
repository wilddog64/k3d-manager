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

## Revoking an Individual Certificate (RevokedKeys)

To revoke a specific compromised user certificate without stopping the console sshd daemon (see parent [`docs/bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md`](../bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md), section B7):

Update the Key Revocation List (KRL) as root:
```bash
sudo ssh-keygen -k -u -f /etc/k3dm-web-console/revoked_keys /path/to/compromised-cert.pub
```

Running `ssh-keygen -k -u` against a certificate revokes that specific certificate only. For a lost or stolen private key, revoke the key itself by listing its plain public key (the `.pub` file of the key, not the `-cert.pub`); revoking the public key ensures that any newly re-issued certificate using that same key is also refused.

Audit or check revocation status with `-Q`:
```bash
ssh-keygen -Q -f /etc/k3dm-web-console/revoked_keys /path/to/cert.pub
```
Reports `REVOKED` (exit code 1) if the key or certificate is revoked, or `ok` (exit code 0) if allowed. Listing the CA public key in `revoked_keys` revokes every certificate signed by that CA.

**Contrast with the whole-console revoked marker:**
The whole-console revoke (`make revoke-web-console-sshd`) creates `/etc/k3dm-web-console/revoked`, which halts the launchd service and stops all console logins. In contrast, `/etc/k3dm-web-console/revoked_keys` is an OpenSSH KRL configured via `RevokedKeys` in `sshd_config`; it denies access only to revoked certificates while sshd continues serving valid connections.

**Persistence:**
`/etc/k3dm-web-console/revoked_keys` is created as an empty KRL (mode 0644, root:wheel) during initial installation if absent. It is never overwritten on reinstall and survives non-purge uninstall (`make uninstall-web-console-sshd`). It is removed only when uninstalled with `PURGE=1` (`make uninstall-web-console-sshd PURGE=1`).

## Upgrade Order for v1.45.1

The v1.45.1 release adds the `RevokedKeys` directive and escalating TOTP recovery. Upgrades must follow a four-step order (see parent [`docs/bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md`](../bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md), section "Upgrade order"):

1. **Promote:** Operator runs `make hub-deploy REF=<v1.45.1 tag>`.
   Promote updates the `deploy/hub` checkout without running root installer commands. The running console sshd retains its installed v1.45.0 configuration, so **login keeps working**. During this window, `make web-console-sshd-check` reports:
   - C1 FAIL: `_wc_files_healthy` requires `/etc/k3dm-web-console/revoked_keys`.
   - C2 FAIL: `_wc_check_config` detects that installed `sshd_config` lacks `RevokedKeys`.
   These failures are expected until step 2.
2. **Install sshd (operator at home, root/sudo):**
   ```bash
   make install-web-console-sshd
   ```
   Creates the empty KRL `/etc/k3dm-web-console/revoked_keys` (0644, root:wheel) and activates the new `sshd_config` containing `RevokedKeys`. Reinstalling part A while part C is installed is safe when the port matches. C1 and C2 checks pass after this step.
3. **Install TOTP gate and regenerate recovery codes (operator at home, root/sudo):**
   ```bash
   make install-web-console-totp
   sudo /Library/PrivilegedHelperTools/k3dm-web-console/totpctl recovery-regen
   ```
   Installs the updated `totpd`, `gate`, and `totpctl` (enabling escalating lockouts, decay, and recovery codes). Then regenerate the initial set of 10 recovery codes (existing enrolments have 0 recovery codes until regenerated). Confirm with `yes` and a valid 6-digit TOTP code, then store the 10 printed recovery codes securely off the travel device.
4. **Verification:** Claude verifies L1 (read-only); operator verifies L2.
