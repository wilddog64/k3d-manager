# Jenkins Pod Readiness Wait Improvements

## Problem

The `_wait_for_jenkins_ready()` function in `scripts/plugins/jenkins.sh` was timing out even when pods were actually ready. Issues:

1. **Short timeout**: Default 5-minute timeout was insufficient for initial deployments with plugin installation
2. **No pod existence check**: Started waiting immediately without checking if pod was created
3. **Uninformative messages**: Just repeated "Waiting..." without showing progress or pod status
4. **No diagnostic output on timeout**: When it failed, no information about what went wrong

## Improvements Made

### Location
`scripts/plugins/jenkins.sh` lines 1493-1564

### Changes

1. **Increased default timeout**: 5m → 10m
   - More realistic for initial deployments with plugin installation
   - Still configurable via `JENKINS_READY_TIMEOUT` environment variable

2. **Pod existence check** (lines 1516-1531)
   - Waits up to 60 seconds for pod to be created first
   - Provides clear feedback if pod creation fails
   - Prevents wasting time checking readiness of non-existent pod

3. **Progress tracking** (lines 1539-1551)
   - Shows elapsed time
   - Displays current container readiness status (`true false false` → shows 1/3 ready)
   - Updates only when status changes or every minute (reduces log spam)
   - Counter tracks number of wait iterations

4. **Better timeout handling** (lines 1553-1558)
   - Shows total timeout duration and last known status
   - Runs `kubectl get pod` to show final pod state
   - Runs `kubectl describe pod` to show events and failure reasons
   - All diagnostic output goes to stderr

5. **Success message** (line 1563)
   - Confirms when pod is ready (provides closure in logs)

### Example Output

**Before:**
```
Waiting for Jenkins controller pod to be ready...
Waiting for Jenkins controller pod to be ready...
Waiting for Jenkins controller pod to be ready...
[repeats many times]
Timed out waiting for Jenkins controller pod to be ready
```

**After:**
```
Waiting for Jenkins controller pod to be created...
Waiting for Jenkins controller pod to be ready... (3s elapsed, status: false false false)
Waiting for Jenkins controller pod to be ready... (45s elapsed, status: true false false)
Waiting for Jenkins controller pod to be ready... (120s elapsed, status: true true false)
Waiting for Jenkins controller pod to be ready... (180s elapsed, status: true true true)
Jenkins controller pod is ready
```

**On timeout (now shows diagnostic info):**
```
Timed out after 600s waiting for Jenkins controller pod to be ready
Last known status: true false false
NAME        READY   STATUS    RESTARTS   AGE
jenkins-0   2/3     Running   0          10m
[pod describe output showing events and container states]
```

## Benefits

1. **More reliable**: 10-minute timeout handles slow plugin installations
2. **Better UX**: Users see progress and know what's happening
3. **Easier debugging**: Diagnostic output on failure shows exactly what went wrong
4. **Reduced log spam**: Status only prints when changed or every minute
5. **Fail fast**: Pod existence check catches deployment failures quickly

## Testing

To test the improvements:

```bash
# Clean deployment (should show progress and succeed)
kubectl delete namespace jenkins --ignore-not-found
./scripts/k3d-manager deploy_jenkins --enable-vault

# Should show:
# - Pod creation wait
# - Container readiness progress (false → true transitions)
# - Success message
```

## Configuration

Users can still override the timeout:

```bash
# Use 15-minute timeout
JENKINS_READY_TIMEOUT=15m ./scripts/k3d-manager deploy_jenkins --enable-vault

# Use 300-second timeout
JENKINS_READY_TIMEOUT=300s ./scripts/k3d-manager deploy_jenkins --enable-vault
```

## Files Modified

- `scripts/plugins/jenkins.sh` (lines 1493-1564) - Enhanced `_wait_for_jenkins_ready()` function
