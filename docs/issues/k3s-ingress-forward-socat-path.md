# Issue: k3s Ingress Forwarding Service Fails with Homebrew-Installed socat

**Date:** 2025-12-02
**Component:** k3s ingress port forwarding
**Severity:** High (blocks port forwarding functionality)
**Status:** Fixed

## Summary

The k3s ingress forwarding systemd service failed to start because it used a hardcoded path to the `socat` binary (`/usr/bin/socat`), which doesn't match the actual installation path when socat is installed via Homebrew on Linux (`/home/linuxbrew/.linuxbrew/bin/socat`).

## Symptoms

When running `./scripts/k3d-manager status_ingress_forward`, the output showed:

```
● k3s-ingress-forward.service - k3s Ingress Gateway HTTPS Port Forwarding
     Loaded: loaded (/etc/systemd/system/k3s-ingress-forward.service; enabled; preset: enabled)
     Active: activating (auto-restart) (Result: exit-code)
    Process: 246799 ExecStart=/usr/bin/socat TCP-LISTEN:443,fork,reuseaddr TCP:10.211.55.14:32653 (code=exited, status=203/EXEC)

WARN: Status: ENABLED but not running
WARN: Port 443 not listening
```

**Key indicators:**
- Service status: `activating (auto-restart)`
- Exit code: `status=203/EXEC`
- Service enabled but not running
- Port 443 not listening
- Connection timeout when testing from client machine: `nc -vzw3 jenkins.dev.local.me 443`

## Root Cause

### systemd Exit Code 203/EXEC

systemd exit code 203 (`EXEC`) means: **"The actual process execution failed (specifically, the execve(2) system call)"**

This occurs when:
- The binary specified in `ExecStart` doesn't exist at the specified path
- The binary is not executable
- There's a path resolution issue

### Path Mismatch

Different package managers install binaries in different locations:

| Package Manager | socat Installation Path |
|----------------|------------------------|
| apt-get (Debian/Ubuntu) | `/usr/bin/socat` |
| Homebrew on Linux | `/home/linuxbrew/.linuxbrew/bin/socat` |
| Homebrew on macOS | `/usr/local/bin/socat` or `/opt/homebrew/bin/socat` |
| Manual install | Can be anywhere in `$PATH` |

The systemd service template hardcoded `/usr/bin/socat`:

```ini
# scripts/etc/k3s/ingress-forward.service.tmpl (BEFORE FIX)
[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:443,fork,reuseaddr TCP:10.211.55.14:32653
```

When socat was installed via Homebrew, systemd couldn't find it at `/usr/bin/socat`, resulting in the `203/EXEC` error.

## Environment Details

**System:** Parallels Ubuntu VM on M2 Mac
**Package Manager:** Homebrew on Linux
**socat Location:** `/home/linuxbrew/.linuxbrew/bin/socat`
**Kubernetes:** k3s (native Linux)

## Solution

### Code Changes

**1. Detect socat path dynamically** (`scripts/lib/providers/k3s.sh`)

```bash
# Check prerequisites and get socat path
local socat_path
if ! socat_path=$(command -v socat 2>/dev/null); then
   _warn "socat is not installed"
   _info "Installing socat..."
   _run_command --prefer-sudo -- apt-get update -qq
   _run_command --prefer-sudo -- apt-get install -y socat
   socat_path=$(command -v socat 2>/dev/null)
fi

if [[ -z "$socat_path" ]]; then
   _err "Failed to locate socat after installation"
   return 1
fi

# Export for template substitution
export SOCAT_PATH="${socat_path}"
```

**2. Update systemd template** (`scripts/etc/k3s/ingress-forward.service.tmpl`)

```ini
# BEFORE (hardcoded path)
ExecStart=/usr/bin/socat TCP-LISTEN:${HTTPS_PORT},fork,reuseaddr TCP:${INGRESS_TARGET_IP}:${INGRESS_TARGET_HTTPS_PORT}

# AFTER (dynamic path)
ExecStart=${SOCAT_PATH} TCP-LISTEN:${HTTPS_PORT},fork,reuseaddr TCP:${INGRESS_TARGET_IP}:${INGRESS_TARGET_HTTPS_PORT}
```

**3. Add path to diagnostic output**

```bash
_info "Detected configuration:"
_info "  socat path: $socat_path"
_info "  Istio HTTPS NodePort: $istio_https_nodeport"
_info "  Node IP: $node_ip"
_info "  External HTTPS Port: ${K3S_INGRESS_FORWARD_HTTPS_PORT}"
```

### Verification

After the fix, the generated service file correctly uses the detected path:

```bash
$ ./scripts/k3d-manager setup_ingress_forward
INFO: Setting up k3s ingress port forwarding...
INFO: Detected configuration:
INFO:   socat path: /home/linuxbrew/.linuxbrew/bin/socat
INFO:   Istio HTTPS NodePort: 32653
INFO:   Node IP: 10.211.55.14
INFO:   External HTTPS Port: 443
```

Generated `/etc/systemd/system/k3s-ingress-forward.service`:
```ini
ExecStart=/home/linuxbrew/.linuxbrew/bin/socat TCP-LISTEN:443,fork,reuseaddr TCP:10.211.55.14:32653
```

Service status after fix:
```
● k3s-ingress-forward.service - k3s Ingress Gateway HTTPS Port Forwarding
     Loaded: loaded (/etc/systemd/system/k3s-ingress-forward.service; enabled)
     Active: active (running)
```

Port test from client:
```bash
$ nc -vzw3 jenkins.dev.local.me 443
jenkins.dev.local.me [10.211.55.14] 443 (https): succeeded!
```

## Prevention

This fix makes the solution portable across different installation methods:
- ✅ Works with apt-get installed socat
- ✅ Works with Homebrew installed socat
- ✅ Works with manually installed socat (as long as it's in `$PATH`)
- ✅ Validates socat is found before generating service
- ✅ Reports detected path in diagnostic output

## Related Files

**Modified:**
- `scripts/lib/providers/k3s.sh` - Added dynamic socat path detection
- `scripts/etc/k3s/ingress-forward.service.tmpl` - Use `${SOCAT_PATH}` variable

**Documentation:**
- `docs/architecture/ingress-port-forwarding.md` - Architecture guide
- `README.md` - User-facing documentation
- `CLAUDE.md` - Developer notes

## Lessons Learned

1. **Never hardcode binary paths in systemd services** - Use `command -v` to detect actual location
2. **Test on different installation methods** - apt, Homebrew, manual, etc.
3. **Use systemd exit codes for debugging** - Code 203 = executable not found
4. **Add diagnostic output** - Display detected paths to aid troubleshooting
5. **Validate prerequisites** - Check binary exists before generating configuration

## Additional Notes

### Why Homebrew on Linux?

Some users prefer Homebrew on Linux for:
- Consistent package management across macOS and Linux
- Access to newer software versions than distribution repositories
- User-space installations (no sudo required for most operations)
- Easier development environment setup

### Alternative Solutions Considered

1. **Use absolute path from apt** - Not portable to Homebrew users
2. **Require apt-only installation** - Limits user choice unnecessarily
3. **Add Homebrew bin to systemd PATH** - More complex, affects other services
4. **Detect and warn about Homebrew** - User-hostile, doesn't solve the problem

The chosen solution (dynamic path detection) is the most robust and user-friendly approach.

## References

- systemd exit codes: `man systemd.exec` (search for EXIT STATUS)
- socat documentation: https://www.dest-unreach.org/socat/
- Homebrew on Linux: https://docs.brew.sh/Homebrew-on-Linux
- Ingress forwarding architecture: [docs/architecture/ingress-port-forwarding.md](../architecture/ingress-port-forwarding.md)
