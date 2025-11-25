# SMB CSI Driver Integration with Mac SMB Server

**Date:** 2025-11-24
**Status:** Planned
**Priority:** Medium (Infrastructure Enhancement)
**Effort:** 3-4 hours

---

## Overview

Deploy SMB CSI driver to enable shared storage for Jenkins agents using Mac M2/M4 as the SMB server. This provides ReadWriteMany storage for shared workspaces, build artifacts, and caching.

---

## Objectives

1. **Configure Mac as SMB Server** (manual setup on macOS)
2. **Deploy SMB CSI Driver** to k3s cluster
3. **Create StorageClass** for SMB volumes
4. **Test SMB Connectivity** from pods
5. **Integrate with Jenkins Agents** (optional shared volumes)
6. **Document Usage** and troubleshooting

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Mac M2/M4 (10.211.55.1)                                 │
│ - macOS File Sharing (SMB/Samba)                        │
│ - Shared folder: ~/jenkins-shared                       │
│ - Credentials: Mac username/password                    │
└─────────────────────────────────────────────────────────┘
                          │
                          │ SMB Protocol (port 445/139)
                          │
┌─────────────────────────▼─────────────────────────────┐
│ k3s Cluster (Ubuntu VM - 10.211.55.14)                │
│                                                        │
│  ┌──────────────────────────────────────────────┐    │
│  │ SMB CSI Driver (kube-system namespace)       │    │
│  │ - csi-smb-controller                         │    │
│  │ - csi-smb-node (DaemonSet on all nodes)     │    │
│  └──────────────────────────────────────────────┘    │
│                          │                             │
│  ┌──────────────────────▼───────────────────────┐    │
│  │ StorageClass: smb                            │    │
│  │ - provisioner: smb.csi.k8s.io                │    │
│  │ - source: //10.211.55.1/jenkins-shared       │    │
│  └──────────────────────────────────────────────┘    │
│                          │                             │
│  ┌──────────────────────▼───────────────────────┐    │
│  │ PersistentVolumeClaim: jenkins-smb-workspace │    │
│  │ - accessModes: ReadWriteMany                 │    │
│  │ - storage: 10Gi                              │    │
│  └──────────────────────────────────────────────┘    │
│                          │                             │
│         ┌────────────────┴────────────────┐           │
│         │                                  │           │
│  ┌──────▼──────┐                  ┌───────▼──────┐   │
│  │ Jenkins Pod │                  │ Agent Pod 1  │   │
│  │ /mnt/shared │                  │ /mnt/shared  │   │
│  └─────────────┘                  └──────────────┘   │
└────────────────────────────────────────────────────────┘
```

---

## Part 1: Mac SMB Server Setup

### Prerequisites

- Mac M2/M4 with macOS
- User account with admin privileges
- Network connectivity from Ubuntu VM (10.211.55.1 ↔ 10.211.55.14)

### Manual Steps (on Mac)

#### Step 1: Create Shared Folder

```bash
# On Mac terminal
mkdir -p ~/jenkins-shared
chmod 755 ~/jenkins-shared
echo "SMB share ready" > ~/jenkins-shared/README.txt
```

#### Step 2: Enable File Sharing

1. **System Settings** → **General** → **Sharing**
2. Turn on **File Sharing**
3. Click **+** under Shared Folders
4. Add `~/jenkins-shared` folder
5. Set permissions: **Everyone: Read & Write** (or specific user)

#### Step 3: Enable SMB Protocol

1. Still in Sharing settings, click **ⓘ** (info button) next to File Sharing
2. Enable **Share files and folders using SMB**
3. Check the box next to your username
4. Enter your password when prompted (this enables SMB authentication)

#### Step 4: Verify SMB Service

```bash
# On Mac terminal - check if SMB is running
sudo launchctl list | grep smb

# Expected output:
# -	0	com.apple.smbd

# Check firewall (should allow SMB)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

#### Step 5: Note Connection Details

```bash
# Share path format
SMB_SERVER="10.211.55.1"
SMB_SHARE="jenkins-shared"
SMB_PATH="//10.211.55.1/jenkins-shared"

# Credentials
SMB_USERNAME="your-mac-username"  # Your Mac account name
SMB_PASSWORD="your-mac-password"  # Your Mac login password
```

---

## Part 2: SMB CSI Driver Deployment

### Phase 1: Create Plugin (Est: 1 hour)

**File:** `scripts/plugins/smb-csi.sh`

```bash
#!/usr/bin/env bash
# SMB CSI Driver plugin

function deploy_smb_csi() {
    _info "[smb-csi] Deploying SMB CSI driver"

    # Source configuration
    local smb_vars="$SCRIPT_DIR/etc/smb-csi/vars.sh"
    if [[ -f "$smb_vars" ]]; then
        source "$smb_vars"
    else
        _warn "[smb-csi] Configuration not found: $smb_vars"
    fi

    local namespace="${SMB_CSI_NAMESPACE:-kube-system}"
    local release="${SMB_CSI_RELEASE:-csi-driver-smb}"

    # Add SMB CSI Helm repository
    _info "[smb-csi] Adding Helm repository..."
    _helm repo add csi-driver-smb https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts 2>/dev/null || true
    _helm repo update

    # Deploy SMB CSI driver
    _info "[smb-csi] Installing SMB CSI driver..."
    _helm upgrade --install "$release" csi-driver-smb/csi-driver-smb \
        --namespace "$namespace" \
        --create-namespace \
        --set controller.replicas=1 \
        --set linux.enabled=true \
        --set windows.enabled=false \
        --wait \
        --timeout=5m

    _info "[smb-csi] Waiting for CSI driver pods..."
    _kubectl wait --for=condition=ready pod \
        -n "$namespace" \
        -l app=csi-smb-controller \
        --timeout=120s

    _kubectl wait --for=condition=ready pod \
        -n "$namespace" \
        -l app=csi-smb-node \
        --timeout=120s

    _info "[smb-csi] ✓ SMB CSI driver deployed successfully"
}

function create_smb_secret() {
    local namespace="${1:?namespace required}"
    local secret_name="${2:-smb-credentials}"

    # Check for required environment variables
    if [[ -z "${SMB_USERNAME:-}" ]] || [[ -z "${SMB_PASSWORD:-}" ]]; then
        _err "[smb-csi] SMB_USERNAME and SMB_PASSWORD must be set"
        _info "[smb-csi] Example:"
        _info "[smb-csi]   export SMB_USERNAME='your-mac-username'"
        _info "[smb-csi]   export SMB_PASSWORD='your-mac-password'"
        return 1
    fi

    _info "[smb-csi] Creating SMB credentials secret in namespace: $namespace"

    _kubectl create secret generic "$secret_name" \
        --namespace="$namespace" \
        --from-literal=username="$SMB_USERNAME" \
        --from-literal=password="$SMB_PASSWORD" \
        --dry-run=client -o yaml | _kubectl apply -f -

    _info "[smb-csi] ✓ SMB credentials secret created: $secret_name"
}

function deploy_smb_storageclass() {
    local template="$SCRIPT_DIR/etc/smb-csi/storage-class.yaml.tmpl"

    if [[ ! -r "$template" ]]; then
        _err "[smb-csi] Template not found: $template"
        return 1
    fi

    _info "[smb-csi] Deploying SMB StorageClass..."
    local rendered
    rendered=$(mktemp -t smb-storageclass.XXXXXX.yaml)

    envsubst < "$template" > "$rendered"
    _kubectl apply -f "$rendered"
    rm -f "$rendered"

    _info "[smb-csi] ✓ SMB StorageClass deployed"
}

function test_smb_mount() {
    local namespace="${1:-default}"

    _info "[smb-csi] Testing SMB mount with temporary pod..."

    # Create test PVC
    local test_pvc="smb-test-pvc"
    cat <<EOF | _kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $test_pvc
  namespace: $namespace
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ${SMB_STORAGE_CLASS_NAME:-smb}
  resources:
    requests:
      storage: 1Gi
EOF

    # Wait for PVC to bind
    _kubectl wait --for=jsonpath='{.status.phase}'=Bound \
        pvc/$test_pvc -n "$namespace" --timeout=60s

    # Create test pod
    _kubectl run smb-test \
        --namespace="$namespace" \
        --image=busybox \
        --restart=Never \
        --overrides='{
          "spec": {
            "containers": [{
              "name": "smb-test",
              "image": "busybox",
              "command": ["sh", "-c", "echo test > /mnt/smb/test.txt && cat /mnt/smb/test.txt && sleep 10"],
              "volumeMounts": [{
                "name": "smb-volume",
                "mountPath": "/mnt/smb"
              }]
            }],
            "volumes": [{
              "name": "smb-volume",
              "persistentVolumeClaim": {
                "claimName": "'$test_pvc'"
              }
            }]
          }
        }' \
        --wait=false

    # Wait for pod to complete
    sleep 5
    _kubectl logs -n "$namespace" smb-test --tail=10

    # Cleanup
    _kubectl delete pod -n "$namespace" smb-test --wait=false
    _kubectl delete pvc -n "$namespace" $test_pvc

    _info "[smb-csi] ✓ SMB mount test completed"
}
```

### Phase 2: Configuration Files (Est: 30 min)

**File:** `scripts/etc/smb-csi/vars.sh`

```bash
#!/usr/bin/env bash
# SMB CSI Configuration

# Mac SMB Server connection
export SMB_SERVER="${SMB_SERVER:-10.211.55.1}"           # Mac IP address
export SMB_SHARE="${SMB_SHARE:-jenkins-shared}"          # Share name from Mac
export SMB_USERNAME="${SMB_USERNAME:-}"                  # Mac username (set via environment)
export SMB_PASSWORD="${SMB_PASSWORD:-}"                  # Mac password (set via environment)

# Full UNC path
export SMB_SOURCE="//${SMB_SERVER}/${SMB_SHARE}"

# CSI driver settings
export SMB_CSI_NAMESPACE="${SMB_CSI_NAMESPACE:-kube-system}"
export SMB_CSI_RELEASE="${SMB_CSI_RELEASE:-csi-driver-smb}"

# Storage class
export SMB_STORAGE_CLASS_NAME="${SMB_STORAGE_CLASS_NAME:-smb}"

# Reclaim policy
export SMB_RECLAIM_POLICY="${SMB_RECLAIM_POLICY:-Retain}"  # Retain or Delete
```

**File:** `scripts/etc/smb-csi/storage-class.yaml.tmpl`

```yaml
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${SMB_STORAGE_CLASS_NAME}
provisioner: smb.csi.k8s.io
parameters:
  source: "${SMB_SOURCE}"
  csi.storage.k8s.io/node-stage-secret-name: "smb-credentials"
  csi.storage.k8s.io/node-stage-secret-namespace: "${SMB_CSI_NAMESPACE}"
reclaimPolicy: ${SMB_RECLAIM_POLICY}
volumeBindingMode: Immediate
mountOptions:
  - dir_mode=0777
  - file_mode=0666
  - vers=3.0
```

**File:** `scripts/etc/smb-csi/jenkins-smb-pvc.yaml.tmpl`

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-smb-workspace
  namespace: ${JENKINS_NAMESPACE}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ${SMB_STORAGE_CLASS_NAME}
  resources:
    requests:
      storage: 10Gi
```

---

## Part 3: Testing Strategy

### Test 1: Connectivity from Ubuntu VM

**On Ubuntu VM:**

```bash
# Install SMB client tools (requires sudo password)
sudo apt-get update
sudo apt-get install -y cifs-utils smbclient

# Test connection
smbclient //10.211.55.1/jenkins-shared -U your-mac-username
# Enter password when prompted
# Should see: smb: \>

# List files
smb: \> ls
# Should see README.txt

# Exit
smb: \> exit
```

### Test 2: Mount from VM

```bash
# Create mount point
sudo mkdir -p /mnt/mac-smb

# Test mount
sudo mount -t cifs //10.211.55.1/jenkins-shared /mnt/mac-smb \
  -o username=your-mac-username,password=your-mac-password,vers=3.0

# Verify
ls -la /mnt/mac-smb/
cat /mnt/mac-smb/README.txt

# Unmount
sudo umount /mnt/mac-smb
```

### Test 3: SMB CSI Driver Deployment

```bash
# Deploy SMB CSI driver
./scripts/k3d-manager deploy_smb_csi

# Verify pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-smb

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# csi-smb-controller-xxxxxxxxxx-xxxxx   3/3     Running   0          1m
# csi-smb-node-xxxxx                    3/3     Running   0          1m
```

### Test 4: Create SMB Credentials Secret

```bash
# Set credentials
export SMB_USERNAME="your-mac-username"
export SMB_PASSWORD="your-mac-password"

# Create secret in kube-system
./scripts/k3d-manager create_smb_secret kube-system

# Verify
kubectl get secret -n kube-system smb-credentials
```

### Test 5: Deploy StorageClass

```bash
# Deploy StorageClass
./scripts/k3d-manager deploy_smb_storageclass

# Verify
kubectl get storageclass smb
kubectl describe storageclass smb
```

### Test 6: Test Pod with SMB Volume

```bash
# Run automated test
./scripts/k3d-manager test_smb_mount default

# Or manual test
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-smb-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: smb
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-smb-pod
  namespace: default
spec:
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "echo 'Hello from k3s' > /mnt/smb/test.txt && cat /mnt/smb/test.txt && sleep 3600"]
    volumeMounts:
    - name: smb-volume
      mountPath: /mnt/smb
  volumes:
  - name: smb-volume
    persistentVolumeClaim:
      claimName: test-smb-pvc
EOF

# Check pod logs
kubectl logs test-smb-pod

# Verify file on Mac
cat ~/jenkins-shared/test.txt
# Should show: Hello from k3s

# Cleanup
kubectl delete pod test-smb-pod
kubectl delete pvc test-smb-pvc
```

---

## Part 4: Jenkins Integration (Optional)

### Update Jenkins Agent Templates

**File:** `scripts/etc/jenkins/values-ldap.yaml.tmpl` (add to agent template)

```yaml
# In JCasC kubernetes cloud template
volumes:
  - persistentVolumeClaim:
      claimName: "jenkins-smb-workspace"
      mountPath: "/mnt/shared"
      readOnly: false
```

### Create Jenkins SMB PVC

```bash
# Create secret in jenkins namespace
./scripts/k3d-manager create_smb_secret jenkins

# Deploy PVC
envsubst < scripts/etc/smb-csi/jenkins-smb-pvc.yaml.tmpl | kubectl apply -f -

# Verify
kubectl get pvc -n jenkins jenkins-smb-workspace
```

---

## Deployment Workflow

```bash
# Prerequisites: Mac file sharing enabled, credentials known

# Step 1: Test connectivity from VM (optional)
smbclient //10.211.55.1/jenkins-shared -U your-username

# Step 2: Deploy SMB CSI driver
./scripts/k3d-manager deploy_smb_csi

# Step 3: Create credentials secret
export SMB_USERNAME="your-mac-username"
export SMB_PASSWORD="your-mac-password"
./scripts/k3d-manager create_smb_secret kube-system

# Step 4: Deploy StorageClass
./scripts/k3d-manager deploy_smb_storageclass

# Step 5: Test mount
./scripts/k3d-manager test_smb_mount default

# Step 6: (Optional) Create Jenkins PVC
./scripts/k3d-manager create_smb_secret jenkins
kubectl apply -f scripts/etc/smb-csi/jenkins-smb-pvc.yaml.tmpl
```

---

## Files to Create

### New Files

```
scripts/plugins/smb-csi.sh                          # SMB CSI plugin
scripts/etc/smb-csi/vars.sh                         # Configuration
scripts/etc/smb-csi/storage-class.yaml.tmpl         # StorageClass template
scripts/etc/smb-csi/jenkins-smb-pvc.yaml.tmpl       # Jenkins PVC template
docs/howto/mac-smb-server-setup.md                 # Mac setup guide
docs/howto/smb-csi-usage.md                        # Usage guide
```

---

## Success Criteria

- ✅ Mac file sharing enabled and accessible from VM
- ✅ SMB CSI driver pods running in kube-system
- ✅ SMB StorageClass created
- ✅ Test PVC binds successfully
- ✅ Test pod can read/write to SMB share
- ✅ Files visible on Mac filesystem
- ✅ Multiple pods can mount same PVC (ReadWriteMany)
- ⚠️ Jenkins integration (optional)

---

## Troubleshooting

### Issue 1: Cannot Connect to SMB from VM

**Symptoms:**
```
smbclient: Connection refused
```

**Solutions:**
1. Check Mac firewall: System Settings → Network → Firewall Options
2. Verify SMB is running: `sudo launchctl list | grep smb`
3. Check IP address: `ifconfig | grep 10.211`
4. Ping test: `ping 10.211.55.1`

### Issue 2: Authentication Failed

**Symptoms:**
```
NT_STATUS_LOGON_FAILURE
```

**Solutions:**
1. Verify username matches Mac account name
2. Check password is correct
3. Re-enable SMB for user in Sharing settings
4. Try short username (before @domain)

### Issue 3: CSI Driver Pods Not Starting

**Symptoms:**
```
kubectl get pods -n kube-system | grep smb
# Pods in CrashLoopBackOff
```

**Solutions:**
1. Check logs: `kubectl logs -n kube-system <pod-name>`
2. Verify Helm chart version compatibility
3. Check node OS: `kubectl get nodes -o wide` (must be Linux)

### Issue 4: PVC Stays Pending

**Symptoms:**
```
kubectl get pvc
# STATUS: Pending
```

**Solutions:**
1. Check PVC events: `kubectl describe pvc <pvc-name>`
2. Verify StorageClass exists: `kubectl get sc`
3. Check secret exists: `kubectl get secret smb-credentials`
4. Test SMB connectivity from node

### Issue 5: Permission Denied in Pod

**Symptoms:**
```
sh: can't create /mnt/smb/test.txt: Permission denied
```

**Solutions:**
1. Check mountOptions in StorageClass (should have `dir_mode=0777`)
2. Verify Mac share permissions (Everyone: Read & Write)
3. Check pod securityContext (may need fsGroup)

---

## Security Considerations

1. **Credentials Management:**
   - SMB password stored in Kubernetes Secret
   - Secret should be in same namespace as PVC
   - Consider rotating Mac password periodically

2. **Network Security:**
   - SMB traffic is unencrypted over Parallels network
   - Mac firewall should allow only VM IP (10.211.55.14)
   - Don't expose Mac SMB to public networks

3. **Access Control:**
   - Use specific Mac user account for SMB (not admin)
   - Set minimal permissions on Mac share
   - Use Kubernetes RBAC to control PVC access

---

## Performance Considerations

- SMB over Parallels network has low latency (~1ms)
- Sequential read/write: ~500-800 MB/s (Parallels network limit)
- Not suitable for high-IOPS databases
- Good for: build artifacts, logs, shared workspace

---

## References

- [SMB CSI Driver GitHub](https://github.com/kubernetes-csi/csi-driver-smb)
- [macOS File Sharing Documentation](https://support.apple.com/guide/mac-help/share-files-folders-mac-users-mh17131/)
- [Kubernetes CSI Documentation](https://kubernetes-csi.github.io/docs/)
- [CIFS/SMB Mount Options](https://linux.die.net/man/8/mount.cifs)
