# k3s Cluster Instability Due to System Clock Skew

**Date**: 2026-01-26
**Status**: ✅ RESOLVED (via cluster rebuild)

## Problem

The k3s cluster became completely unstable with the API server intermittently unavailable. The service was in a restart loop with 1108+ restarts recorded.

### Symptoms

1. `kubectl` commands failing with connection refused errors
2. k3s service cycling between `active (running)` and `activating (auto-restart)`
3. API server returning `ServiceUnavailable` errors
4. 12,500+ pods accumulated (12,152 in `ContainerStatusUnknown` state)
5. Orphan `containerd-shim` processes persisting after service stops
6. Heavy swap usage (1.8GB/2GB)

### Error Messages

```
Error from server (ServiceUnavailable): the server is currently unable to handle the request
```

```
tls: failed to verify certificate: x509: certificate has expired or is not yet valid:
current time 2121-03-14T05:49:57-07:00 is after 2035-12-01T00:23:34Z
```

```
k3s.service: Found left-over process XXXX (containerd-shim) in control group while starting unit
```

## Root Cause

The system clock had jumped to year **2121** (nearly 100 years in the future), causing:

1. **Certificate validation failures** - k3s internal certificates (valid until 2035) appeared expired
2. **etcd corruption** - Repeated failed starts corrupted the cluster state
3. **Massive pod accumulation** - Each restart cycle created new pods while old ones remained in unknown states
4. **NTP was disabled** - System clock was not synchronized, allowing drift

### Likely Trigger: Parallels Desktop Upgrade

The clock skew was likely caused by a **recent Parallels Desktop upgrade**. Common causes include:

1. **Parallels Tools reset** - Time sync settings may revert to defaults during upgrade
2. **VM suspension during upgrade** - Clock can jump significantly if VM was suspended/resumed
3. **Kernel module changes** - New Parallels Tools may not properly sync time until guest reboot
4. **Host time drift** - If Mac host was rebooted or slept during the upgrade process

**Verification:**
```bash
# On Mac host - check Parallels time sync
prlsrvctl info | grep -i time

# In the VM - check current sync status
timedatectl status
```

**Fix for Parallels:**
1. VM menu → Configuration → Options → More Options
2. Ensure "Synchronize with host time" is enabled
3. Reboot the VM after Parallels Tools upgrade

### Timeline

| Time | Event |
|------|-------|
| Unknown | System clock jumped to year 2121 |
| Unknown | k3s certificates failed validation (expired in "past") |
| Unknown | k3s entered restart loop (1108+ restarts) |
| 2026-01-26 | Clock corrected, but cluster remained unstable |
| 2026-01-26 | Attempted fix via TLS regeneration - partial success |
| 2026-01-26 | Full cluster rebuild required |

## Attempted Fixes

### Fix Attempt 1: TLS Certificate Regeneration

Created `bin/fix-k3s.sh` script to:
1. Stop k3s service
2. Kill orphan containerd-shim processes
3. Enable NTP synchronization
4. Delete `/var/lib/rancher/k3s/server/tls` for regeneration
5. Restart k3s

**Result**: Partial success - cluster came up briefly but remained unstable due to corrupted etcd data and 12,000+ stale pods overwhelming the API server.

### Fix Attempt 2: Full Cluster Rebuild

```bash
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager destroy_cluster
sudo pkill -9 containerd-shim
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster -f
```

**Result**: Success - clean cluster deployed

## Resolution

Full cluster rebuild was required. The etcd database had accumulated too much corrupted state from 1108+ restart cycles to recover.

## Prevention

### 1. Enable NTP Synchronization

Ensure NTP is always enabled on k3s nodes:

```bash
sudo timedatectl set-ntp true
sudo systemctl enable --now systemd-timesyncd
```

Verify with:
```bash
timedatectl status | grep -E "NTP|synchronized"
# Should show:
# System clock synchronized: yes
# NTP service: active
```

### 2. Monitor System Time

Add monitoring/alerting for:
- NTP sync status
- Clock drift from reference time
- k3s service restart count

### 3. VM Time Sync (for virtualized environments)

If running k3s in a VM (Parallels, VMware, VirtualBox):
- Enable VM time synchronization with host
- For Parallels: Ensure "Synchronize with host" is enabled in VM settings

### 4. After Parallels Desktop Upgrades

After upgrading Parallels Desktop:
1. **Reboot the VM** - Ensures new Parallels Tools kernel modules load properly
2. **Verify time sync** - Run `timedatectl status` and confirm clock is synchronized
3. **Check k3s before use** - Run `systemctl status k3s` and verify no restart loops
4. **If clock is wrong** - Fix immediately with `sudo timedatectl set-ntp true` before starting k3s

### 5. Regular Health Checks

Monitor k3s service restart count:
```bash
systemctl show k3s --property=NRestarts
```

Alert if restart count exceeds threshold (e.g., >10 in 24 hours).

## Files Created

- `bin/fix-k3s.sh` - Recovery script for future similar issues (useful for partial failures)

## Lessons Learned

1. **Clock skew is catastrophic for Kubernetes** - Certificate validation fails immediately
2. **etcd can become irrecoverable** - After many restart cycles, rebuild may be faster than repair
3. **NTP must be mandatory** - Add to deployment prerequisites checklist
4. **VM environments need extra attention** - Host-guest time sync is critical
5. **After Parallels upgrades** - Always verify time sync and reboot VM before running k8s workloads

## Related Documentation

- [k3s Requirements](https://docs.k3s.io/installation/requirements)
- [Kubernetes Certificate Management](https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/)

## Diagnostic Commands

```bash
# Check system time and NTP status
timedatectl status

# Check k3s service status and restart count
systemctl status k3s
systemctl show k3s --property=NRestarts

# Check for orphan containerd processes
pgrep -a containerd-shim

# Check certificate dates
openssl x509 -in /var/lib/rancher/k3s/server/tls/server-ca.crt -noout -dates

# Check pod accumulation
kubectl get pods -A --no-headers | wc -l
kubectl get pods -A --no-headers | awk '{print $4}' | sort | uniq -c
```
