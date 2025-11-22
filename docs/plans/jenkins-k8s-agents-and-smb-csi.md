# Jenkins Kubernetes Agents and SMB CSI Integration Plan

**Date:** 2025-11-21
**Status:** Planned
**Priority:** High (Infrastructure Enhancement)
**Effort:** ~6-8 hours

---

## Overview

Implement dynamic Jenkins agent provisioning using the Kubernetes plugin with support for both Linux and Windows Nano Server agents. Additionally, integrate SMB CSI driver for shared storage across agents.

---

## Objectives

1. **Configure Kubernetes Plugin** for dynamic agent provisioning
2. **Create Linux Agent Pod Template** (Alpine/Ubuntu-based)
3. **Create Windows Nano Agent Pod Template** (if k3d/k3s supports Windows nodes)
4. **Deploy SMB CSI Driver** for shared storage (build artifacts, workspace sharing)
5. **Create Test Jobs** to validate both agent types
6. **Document Usage** and operational procedures

---

## Part 1: Jenkins Kubernetes Agents

### Current State

- ✅ Kubernetes plugin already installed (`values-ldap.yaml.tmpl:35`)
- ✅ Jenkins ServiceAccount exists (`jenkins-admin`)
- ❌ No pod templates configured
- ❌ No RBAC for pod/exec permissions
- ❌ No test jobs created

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Jenkins Controller (jenkins namespace)                  │
│ - Kubernetes Plugin enabled                             │
│ - ServiceAccount: jenkins-admin                         │
└─────────────────────────────────────────────────────────┘
                          │
                          ├─> Creates agent pods dynamically
                          │
        ┌─────────────────┴─────────────────┐
        │                                     │
┌───────▼──────────┐              ┌─────────▼──────────┐
│ Linux Agent Pod  │              │ Windows Agent Pod  │
│ - Alpine/Ubuntu  │              │ - Nano Server      │
│ - JNLP container │              │ - JNLP container   │
│ - Build tools    │              │ - PowerShell       │
└──────────────────┘              └────────────────────┘
```

### Implementation Plan

#### Phase 1: RBAC Configuration (Est: 30 min)

**File:** `scripts/etc/jenkins/agent-rbac.yaml.tmpl`

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-agent-manager
  namespace: ${JENKINS_NAMESPACE}
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-agent-manager
  namespace: ${JENKINS_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: jenkins-agent-manager
subjects:
  - kind: ServiceAccount
    name: jenkins-admin
    namespace: ${JENKINS_NAMESPACE}
```

**Integration:**
- Add to `scripts/plugins/jenkins.sh` in `deploy_jenkins()` function
- Deploy via `kubectl apply -f`

#### Phase 2: JCasC Kubernetes Cloud Configuration (Est: 1-2 hours)

**File:** `scripts/etc/jenkins/values-ldap.yaml.tmpl` (add to JCasC section)

```yaml
JCasC:
  configScripts:
    # ... existing configs ...

    02-kubernetes-agents: |
      jenkins:
        clouds:
          - kubernetes:
              name: "kubernetes"
              serverUrl: "https://kubernetes.default"
              namespace: "${JENKINS_NAMESPACE}"
              jenkinsUrl: "http://jenkins.${JENKINS_NAMESPACE}.svc.cluster.local:8080"
              jenkinsTunnel: "jenkins-agent.${JENKINS_NAMESPACE}.svc.cluster.local:50000"
              containerCapStr: "10"
              maxRequestsPerHostStr: "32"
              retentionTimeout: 5
              connectTimeout: 10
              readTimeout: 20

              templates:
                # Linux Agent Template
                - name: "linux-agent"
                  label: "linux docker kubectl"
                  nodeUsageMode: NORMAL
                  containers:
                    - name: "jnlp"
                      image: "jenkins/inbound-agent:latest-alpine"
                      alwaysPullImage: false
                      workingDir: "/home/jenkins/agent"
                      command: ""
                      args: ""
                      ttyEnabled: true
                      resourceRequestCpu: "500m"
                      resourceRequestMemory: "512Mi"
                      resourceLimitCpu: "1000m"
                      resourceLimitMemory: "1Gi"
                    - name: "docker"
                      image: "docker:dind"
                      privileged: true
                      alwaysPullImage: false
                      workingDir: "/home/jenkins/agent"
                      ttyEnabled: true
                      resourceRequestCpu: "500m"
                      resourceRequestMemory: "512Mi"
                      resourceLimitCpu: "1000m"
                      resourceLimitMemory: "1Gi"
                  volumes:
                    - emptyDirVolume:
                        memory: false
                        mountPath: "/var/lib/docker"
                  yaml: |
                    apiVersion: v1
                    kind: Pod
                    metadata:
                      labels:
                        jenkins-agent: "linux"
                    spec:
                      serviceAccountName: jenkins-admin
                      securityContext:
                        fsGroup: 1000

                # Windows Nano Agent Template (if Windows nodes available)
                - name: "windows-agent"
                  label: "windows powershell"
                  nodeUsageMode: NORMAL
                  nodeSelector: "kubernetes.io/os=windows"
                  containers:
                    - name: "jnlp"
                      image: "jenkins/inbound-agent:windowsservercore-ltsc2022"
                      alwaysPullImage: false
                      workingDir: "C:\\Users\\jenkins\\agent"
                      command: ""
                      args: ""
                      ttyEnabled: true
                      resourceRequestCpu: "1000m"
                      resourceRequestMemory: "1Gi"
                      resourceLimitCpu: "2000m"
                      resourceLimitMemory: "2Gi"
                  yaml: |
                    apiVersion: v1
                    kind: Pod
                    metadata:
                      labels:
                        jenkins-agent: "windows"
                    spec:
                      serviceAccountName: jenkins-admin
                      nodeSelector:
                        kubernetes.io/os: windows
```

**Environment Variables:**
```bash
export JENKINS_AGENT_NAMESPACE="${JENKINS_NAMESPACE}"
export JENKINS_AGENT_LINUX_IMAGE="jenkins/inbound-agent:latest-alpine"
export JENKINS_AGENT_WINDOWS_IMAGE="jenkins/inbound-agent:windowsservercore-ltsc2022"
```

#### Phase 3: Agent Service Configuration (Est: 30 min)

**File:** `scripts/etc/jenkins/agent-service.yaml.tmpl`

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: jenkins-agent
  namespace: ${JENKINS_NAMESPACE}
spec:
  type: ClusterIP
  ports:
    - port: 50000
      targetPort: 50000
      name: agent
  selector:
    app.kubernetes.io/name: jenkins
    app.kubernetes.io/instance: jenkins
```

#### Phase 4: Test Jobs (Est: 1 hour)

**File:** `scripts/etc/jenkins/test-jobs/linux-agent-test.groovy`

```groovy
pipeline {
    agent {
        label 'linux'
    }
    stages {
        stage('System Info') {
            steps {
                sh 'uname -a'
                sh 'cat /etc/os-release'
                sh 'pwd'
                sh 'whoami'
            }
        }
        stage('Docker Test') {
            steps {
                sh 'docker --version'
                sh 'docker run --rm hello-world'
            }
        }
        stage('kubectl Test') {
            steps {
                sh 'kubectl version --client'
                sh 'kubectl get nodes'
            }
        }
    }
}
```

**File:** `scripts/etc/jenkins/test-jobs/windows-agent-test.groovy`

```groovy
pipeline {
    agent {
        label 'windows'
    }
    stages {
        stage('System Info') {
            steps {
                powershell 'Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion'
                powershell '$PSVersionTable'
                powershell 'Get-Location'
                powershell '$env:USERNAME'
            }
        }
        stage('PowerShell Test') {
            steps {
                powershell '''
                    Write-Host "Testing PowerShell..."
                    Get-ChildItem Env:
                '''
            }
        }
    }
}
```

**Deployment:**
- Create Job DSL seed job to deploy test pipelines
- Or manually create via Jenkins UI

---

## Part 2: SMB CSI Driver

### Overview

Deploy SMB CSI driver to enable SMB/CIFS storage for Jenkins agents (shared workspace, build artifacts, NuGet cache, etc.).

### Use Cases

1. **Shared Workspace:** Multiple agents access same workspace
2. **Build Artifacts:** Store artifacts on SMB share
3. **NuGet/Maven Cache:** Windows agents share package cache
4. **Logs and Reports:** Centralized log storage

### Implementation Plan

#### Phase 1: Deploy SMB CSI Driver (Est: 1 hour)

**File:** `scripts/plugins/smb-csi.sh`

```bash
#!/usr/bin/env bash
# SMB CSI Driver plugin

function deploy_smb_csi() {
    _info "[smb-csi] Deploying SMB CSI driver"

    # Install SMB CSI driver via Helm
    local namespace="${SMB_CSI_NAMESPACE:-kube-system}"
    local release="${SMB_CSI_RELEASE:-smb-csi-driver}"

    _helm repo add smb-csi-driver https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts 2>/dev/null || true
    _helm repo update

    _helm upgrade --install "$release" smb-csi-driver/csi-driver-smb \
        --namespace "$namespace" \
        --create-namespace \
        --wait

    _info "[smb-csi] SMB CSI driver deployed successfully"
}

function create_smb_secret() {
    local namespace="${1:?namespace required}"
    local secret_name="${2:-smb-credentials}"
    local smb_user="${SMB_USERNAME:?SMB_USERNAME required}"
    local smb_pass="${SMB_PASSWORD:?SMB_PASSWORD required}"

    _kubectl create secret generic "$secret_name" \
        --namespace="$namespace" \
        --from-literal=username="$smb_user" \
        --from-literal=password="$smb_pass" \
        --dry-run=client -o yaml | _kubectl apply -f -

    _info "[smb-csi] Created SMB credentials secret: $secret_name"
}

function create_smb_pv() {
    local template="$SCRIPT_DIR/etc/smb-csi/smb-pv.yaml.tmpl"

    if [[ ! -f "$template" ]]; then
        _err "[smb-csi] Template not found: $template"
        return 1
    fi

    envsubst < "$template" | _kubectl apply -f -
    _info "[smb-csi] SMB PersistentVolume created"
}
```

#### Phase 2: SMB Storage Configuration (Est: 1 hour)

**File:** `scripts/etc/smb-csi/vars.sh`

```bash
# SMB CSI Configuration

# SMB Server connection
export SMB_SERVER="${SMB_SERVER:-192.168.1.100}"  # SMB server IP or hostname
export SMB_SHARE="${SMB_SHARE:-jenkins}"          # SMB share name
export SMB_USERNAME="${SMB_USERNAME:-jenkins}"    # SMB username
export SMB_PASSWORD="${SMB_PASSWORD:-}"           # SMB password (set via environment)

# CSI driver settings
export SMB_CSI_NAMESPACE="${SMB_CSI_NAMESPACE:-kube-system}"
export SMB_CSI_RELEASE="${SMB_CSI_RELEASE:-smb-csi-driver}"

# Storage class
export SMB_STORAGE_CLASS_NAME="${SMB_STORAGE_CLASS_NAME:-smb}"
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
  source: "//${SMB_SERVER}/${SMB_SHARE}"
  csi.storage.k8s.io/node-stage-secret-name: "smb-credentials"
  csi.storage.k8s.io/node-stage-secret-namespace: "${JENKINS_NAMESPACE}"
reclaimPolicy: Retain
volumeBindingMode: Immediate
```

**File:** `scripts/etc/smb-csi/smb-pvc.yaml.tmpl`

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

#### Phase 3: Integration with Jenkins Agents (Est: 30 min)

Update pod templates to mount SMB volumes:

```yaml
# In JCasC kubernetes cloud config
volumes:
  - persistentVolumeClaim:
      claimName: "jenkins-smb-workspace"
      mountPath: "/mnt/shared"
      readOnly: false
```

---

## Windows Nano Server Considerations

### Feasibility Check

**k3d/k3s Windows Support:**
- ❌ k3d (Docker-based) does NOT support Windows containers on Linux hosts
- ⚠️ k3s supports Windows worker nodes but requires:
  - Separate Windows Server machine
  - k3s agent installation on Windows
  - Hybrid cluster (Linux control plane + Windows workers)

### Options

**Option A: Linux-only (Recommended for k3d)**
- Deploy only Linux agents
- Use Wine or Mono for limited Windows compatibility
- Focus on cross-platform tooling (Docker, kubectl, etc.)

**Option B: Hybrid k3s Cluster (Advanced)**
- Requires Windows Server machine
- Install k3s agent on Windows node
- Join to existing k3s cluster
- Deploy Windows Nano agent pods

**Option C: Simulated Windows Testing**
- Use Windows Docker containers on Windows Docker Desktop
- Run k3d on Windows host (not Linux)
- Or use GitHub Actions Windows runners for real Windows builds

### Recommendation

For this project (k3d on Linux/macOS):
1. **Implement Linux agents only** (immediate value)
2. **Document Windows agent setup** for hybrid clusters
3. **Use Docker Desktop on Windows** for actual Windows testing if needed

---

## Testing Strategy

### Linux Agent Tests

```bash
# Test 1: Basic agent provisioning
./bin/test-jenkins-agent.sh linux

# Test 2: Docker-in-Docker
# Job: Build and push Docker image

# Test 3: kubectl access
# Job: Deploy to test namespace

# Test 4: Parallel builds
# Trigger 5 jobs simultaneously, verify 5 agents spawn
```

### Windows Agent Tests (if available)

```bash
# Test 1: PowerShell execution
./bin/test-jenkins-agent.sh windows

# Test 2: .NET build
# Job: Build C# project

# Test 3: NuGet restore from SMB cache
```

### SMB CSI Tests

```bash
# Test 1: Create PVC
kubectl apply -f scripts/etc/smb-csi/smb-pvc.yaml.tmpl

# Test 2: Mount in test pod
kubectl run test-smb --image=alpine -- sh -c "echo test > /mnt/shared/test.txt"

# Test 3: Verify from SMB server
# Check file exists on SMB share

# Test 4: Multi-pod access
# Start 2 pods, both write to same PVC, verify data
```

---

## Files to Create/Modify

### New Files

```
scripts/plugins/smb-csi.sh                          # SMB CSI plugin
scripts/etc/smb-csi/vars.sh                         # SMB configuration
scripts/etc/smb-csi/storage-class.yaml.tmpl         # SMB StorageClass
scripts/etc/smb-csi/smb-pvc.yaml.tmpl               # SMB PVC template
scripts/etc/jenkins/agent-rbac.yaml.tmpl            # Agent RBAC
scripts/etc/jenkins/agent-service.yaml.tmpl         # Agent service
scripts/etc/jenkins/test-jobs/linux-agent-test.groovy    # Linux test job
scripts/etc/jenkins/test-jobs/windows-agent-test.groovy  # Windows test job
bin/test-jenkins-agent.sh                           # Agent testing utility
docs/howto/jenkins-kubernetes-agents.md             # Usage guide
docs/howto/smb-csi-setup.md                         # SMB CSI guide
```

### Modified Files

```
scripts/etc/jenkins/values-ldap.yaml.tmpl           # Add JCasC kubernetes cloud
scripts/etc/jenkins/values-ad-test.yaml.tmpl        # Add kubernetes cloud
scripts/etc/jenkins/values-ad-prod.yaml.tmpl        # Add kubernetes cloud
scripts/plugins/jenkins.sh                          # Deploy RBAC, agent service
```

---

## Environment Variables

```bash
# Jenkins Agent Configuration
export JENKINS_AGENT_NAMESPACE="${JENKINS_NAMESPACE}"
export JENKINS_AGENT_LINUX_IMAGE="jenkins/inbound-agent:latest-alpine"
export JENKINS_AGENT_WINDOWS_IMAGE="jenkins/inbound-agent:windowsservercore-ltsc2022"
export JENKINS_AGENT_CAPACITY="10"  # Max concurrent agents
export JENKINS_AGENT_RETENTION="5"  # Minutes to keep idle agents

# SMB CSI Configuration
export SMB_SERVER="192.168.1.100"
export SMB_SHARE="jenkins"
export SMB_USERNAME="jenkins"
export SMB_PASSWORD="SecurePassword123!"
export SMB_STORAGE_CLASS_NAME="smb"
```

---

## Deployment Workflow

```bash
# Step 1: Deploy SMB CSI driver
./scripts/k3d-manager deploy_smb_csi

# Step 2: Create SMB credentials
export SMB_PASSWORD="your-smb-password"
./scripts/k3d-manager create_smb_secret jenkins

# Step 3: Deploy Jenkins with agent support
./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault --enable-k8s-agents

# Step 4: Verify agent service
kubectl get svc -n jenkins jenkins-agent

# Step 5: Create test jobs
# Via Jenkins UI or Job DSL

# Step 6: Trigger test job
# Verify agent pod is created and job completes
```

---

## Success Criteria

- ✅ Linux agent pod template configured in JCasC
- ✅ RBAC allows Jenkins to create/manage agent pods
- ✅ Agent service exposes port 50000 for JNLP
- ✅ Test job completes successfully on Linux agent
- ✅ SMB CSI driver installed and operational
- ✅ SMB PVC can be mounted by agent pods
- ✅ Documentation complete for both features
- ⚠️ Windows agent (optional, requires Windows nodes)

---

## Timeline

| Task | Effort | Priority |
|------|--------|----------|
| RBAC Configuration | 30 min | High |
| JCasC Kubernetes Cloud | 1-2 hrs | High |
| Agent Service | 30 min | High |
| Linux Test Jobs | 1 hr | High |
| SMB CSI Driver Deployment | 1 hr | Medium |
| SMB Storage Configuration | 1 hr | Medium |
| Testing and Validation | 1-2 hrs | High |
| Documentation | 1 hr | Medium |
| **Total** | **6-8 hrs** | - |

---

## Dependencies

- ✅ Kubernetes plugin already installed
- ✅ Jenkins ServiceAccount exists
- ❌ Agent RBAC not configured
- ❌ Agent service not created
- ❌ SMB CSI driver not installed
- ⚠️ Windows nodes (optional, not available in k3d)

---

## Risks and Mitigations

### Risk 1: Windows Nodes Not Available
- **Impact:** High (can't test Windows agents)
- **Probability:** High (k3d doesn't support Windows)
- **Mitigation:**
  - Focus on Linux agents first
  - Document Windows setup for hybrid clusters
  - Use external Windows CI/CD if needed

### Risk 2: SMB Server Not Available
- **Impact:** Medium (can't test SMB CSI)
- **Probability:** Medium
- **Mitigation:**
  - Use Samba server in Docker container
  - Or skip SMB CSI initially
  - Use NFS as alternative

### Risk 3: Agent Pod Resource Exhaustion
- **Impact:** Medium (cluster slowdown)
- **Probability:** Low
- **Mitigation:**
  - Set resource limits in pod templates
  - Configure agent capacity limits
  - Monitor cluster resources

---

## Future Enhancements

1. **Auto-scaling:** HPA for agent pods based on queue depth
2. **Pod retention:** Keep agents alive for faster subsequent builds
3. **Custom agent images:** Specialized agents with pre-installed tools
4. **Windows support:** Document hybrid cluster setup
5. **Multi-cloud:** Support agents across different clouds
6. **Spot instances:** Use spot/preemptible instances for cost savings

---

## References

- [Kubernetes Plugin Documentation](https://plugins.jenkins.io/kubernetes/)
- [Jenkins Inbound Agent Images](https://hub.docker.com/r/jenkins/inbound-agent)
- [SMB CSI Driver](https://github.com/kubernetes-csi/csi-driver-smb)
- [k3s Windows Support](https://docs.k3s.io/advanced#windows-experimental)
- [Jenkins JCasC Kubernetes Cloud](https://github.com/jenkinsci/configuration-as-code-plugin/blob/master/demos/kubernetes-helm/values.yaml)
