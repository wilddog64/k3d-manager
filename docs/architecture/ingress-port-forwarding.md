# Ingress Port Forwarding and Multi-Service SNI Routing

This document explains how k3d-manager enables multiple services (Jenkins, ArgoCD, etc.) to share a single external HTTPS port (443) through port forwarding and SNI-based routing.

## Overview

The ingress forwarding system solves a key challenge in k3s deployments: exposing services on standard ports (80/443) when Kubernetes uses high-numbered NodePorts (e.g., 32653).

**What it does:**
- Forwards external port 443 to Istio IngressGateway NodePort
- Enables multiple services to share port 443 via SNI routing
- Provides persistent, auto-starting systemd service (k3s only)
- Eliminates need for manual socat commands

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Client Machine (e.g., M4 Mac)                               │
│                                                             │
│  Browser/CLI → https://jenkins.dev.local.me:443             │
│                https://argocd.dev.local.me:443              │
│                                                             │
│  /etc/hosts:                                                │
│    10.211.55.14 jenkins.dev.local.me                        │
│    10.211.55.14 argocd.dev.local.me                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ TLS ClientHello with SNI
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ k3s Host (e.g., M2 Ubuntu)                                  │
│                                                             │
│  ┌──────────────────────────────────────┐                  │
│  │ systemd: k3s-ingress-forward         │                  │
│  │                                      │                  │
│  │  ExecStart: socat                   │                  │
│  │    TCP-LISTEN:443,fork,reuseaddr   │                  │
│  │    TCP:localhost:32653              │                  │
│  │                                      │                  │
│  │  Forwards raw TCP (no decryption)   │                  │
│  └────────────┬─────────────────────────┘                  │
│               │                                             │
│               │ Raw TCP stream with encrypted TLS           │
│               │                                             │
│               ▼                                             │
│  ┌──────────────────────────────────────┐                  │
│  │ Istio IngressGateway                 │                  │
│  │ (Service: istio-ingressgateway)      │                  │
│  │                                      │                  │
│  │  Port: 32653 (NodePort)             │                  │
│  │                                      │                  │
│  │  SNI Inspection:                     │                  │
│  │    Read SNI from TLS ClientHello     │                  │
│  │    Match to Gateway configuration    │                  │
│  │    Select correct TLS certificate    │                  │
│  │    Complete TLS handshake            │                  │
│  │    Decrypt HTTPS → HTTP              │                  │
│  └────────────┬─────────────────────────┘                  │
│               │                                             │
│               │ Decrypted HTTP                              │
│               │                                             │
│      ┌────────┴─────────┐                                  │
│      │                  │                                   │
│      ▼                  ▼                                   │
│  ┌────────────────┐ ┌──────────────────┐                  │
│  │ Gateway:       │ │ Gateway:         │                  │
│  │ jenkins-gw     │ │ argocd-gateway   │                  │
│  │                │ │                  │                  │
│  │ Hosts:         │ │ Hosts:           │                  │
│  │ jenkins.dev... │ │ argocd.dev...    │                  │
│  │                │ │                  │                  │
│  │ TLS Cert:      │ │ TLS Cert:        │                  │
│  │ jenkins-tls    │ │ argocd-tls       │                  │
│  └───────┬────────┘ └────────┬─────────┘                  │
│          │                   │                             │
│          ▼                   ▼                             │
│  ┌────────────────┐ ┌──────────────────┐                  │
│  │ VirtualService │ │ VirtualService   │                  │
│  │ jenkins/jenkins│ │ argocd/argocd    │                  │
│  │                │ │                  │                  │
│  │ Route →        │ │ Route →          │                  │
│  │ jenkins:8081   │ │ argocd-server:443│                  │
│  └───────┬────────┘ └────────┬─────────┘                  │
│          │                   │                             │
│          ▼                   ▼                             │
│  ┌────────────────┐ ┌──────────────────┐                  │
│  │ Jenkins Pod    │ │ ArgoCD Pod       │                  │
│  └────────────────┘ └──────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

## How Multiple Services Share Port 443

### SNI (Server Name Indication)

SNI is a TLS extension that allows the client to specify which hostname it's trying to reach **before** the TLS handshake completes. This enables:

1. **Single port** serving multiple HTTPS sites
2. **Different TLS certificates** for each hostname
3. **Routing decisions** before decryption

### Step-by-Step Request Flow

#### 1. Client Initiates Connection

```bash
# Client on M4 Mac
curl https://jenkins.dev.local.me/

# DNS Resolution (from /etc/hosts)
jenkins.dev.local.me → 10.211.55.14

# TLS ClientHello Packet Sent
Destination: 10.211.55.14:443
SNI: jenkins.dev.local.me  ← Key field for routing
```

#### 2. socat Forwards TCP Stream

```bash
# systemd service running on M2
socat TCP-LISTEN:443,fork,reuseaddr TCP:localhost:32653

# What happens:
# - Listens on all interfaces (0.0.0.0:443)
# - Accepts incoming connection
# - Creates forked process for this connection
# - Forwards ALL bytes to localhost:32653
# - No TLS inspection or decryption
```

**Key Point:** socat does **raw TCP forwarding** - it doesn't know or care about TLS, HTTP, or hostnames. It just passes bytes through.

#### 3. Istio Reads SNI Header

```bash
# Istio IngressGateway receives TLS ClientHello
# Reads SNI field: jenkins.dev.local.me

# Matches against configured Gateways:
Gateway: jenkins-gw
  hosts: [jenkins.dev.local.me]  ✓ MATCH
  tls:
    credentialName: jenkins-tls
    mode: SIMPLE

Gateway: argocd-gateway
  hosts: [argocd.dev.local.me]   ✗ No match
```

#### 4. TLS Handshake with Correct Certificate

```bash
# Istio loads certificate from Kubernetes secret
kubectl get secret -n istio-system jenkins-tls
  tls.crt: <Vault-issued certificate for jenkins.dev.local.me>
  tls.key: <Private key>

# Completes TLS handshake using jenkins-tls certificate
# Client validates certificate matches jenkins.dev.local.me
# Encrypted tunnel established
```

#### 5. HTTP Routing

```bash
# After TLS decryption, Istio has plain HTTP:
GET / HTTP/1.1
Host: jenkins.dev.local.me

# Matches VirtualService:
VirtualService: jenkins/jenkins
  hosts: [jenkins.dev.local.me]
  gateways: [istio-system/jenkins-gw]
  http:
    route:
      destination:
        host: jenkins.jenkins.svc.cluster.local
        port: 8081

# Forwards to Jenkins pod on port 8081
```

#### 6. Response Path (Reverse)

```bash
Jenkins Pod → VirtualService → Istio Gateway
  → Encrypts with jenkins-tls certificate
  → socat forwards encrypted response
  → Client receives HTTPS response
```

## Configuration Components

### 1. systemd Service

**File:** `/etc/systemd/system/k3s-ingress-forward.service`

```ini
[Unit]
Description=k3s Ingress Gateway HTTPS Port Forwarding
After=network-online.target k3s.service
Wants=network-online.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=3
ExecStart=/usr/bin/socat TCP-LISTEN:443,fork,reuseaddr TCP:10.211.55.14:32653

[Install]
WantedBy=multi-user.target
```

**Key Features:**
- `Restart=always` - Auto-restarts on failure
- `After=k3s.service` - Starts after k3s is ready
- `fork` - Handles multiple simultaneous connections
- `reuseaddr` - Quick restart without "address in use" errors

### 2. Istio Gateway (per service)

**Jenkins Gateway:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: jenkins-gw
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: jenkins-tls  # K8s secret with cert
    hosts:
    - jenkins.dev.local.me
```

**ArgoCD Gateway:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: argocd-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https-argocd
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: argocd-tls  # Different cert
    hosts:
    - argocd.dev.local.me
```

### 3. VirtualService (per service)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: jenkins
  namespace: jenkins
spec:
  hosts:
  - jenkins.dev.local.me
  gateways:
  - istio-system/jenkins-gw
  http:
  - route:
    - destination:
        host: jenkins.jenkins.svc.cluster.local
        port:
          number: 8081
```

## Usage

### Setup (k3s provider)

```bash
# Automatic during cluster deployment
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster

# Manual setup
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager setup_ingress_forward

# Check status
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager status_ingress_forward

# Remove
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager remove_ingress_forward
```

### Client Configuration

On your client machine (e.g., M4 Mac), add DNS entries:

```bash
# /etc/hosts
10.211.55.14 jenkins.dev.local.me
10.211.55.14 argocd.dev.local.me
10.211.55.14 vault.dev.local.me
```

### Access Services

```bash
# Jenkins
https://jenkins.dev.local.me/

# ArgoCD
https://argocd.dev.local.me/

# ArgoCD CLI
argocd login argocd.dev.local.me --username admin

# All use the same port (443) but route to different services!
```

## Adding New Services

To add a new service that shares port 443:

### 1. Issue TLS Certificate

```bash
# Using Vault PKI
kubectl exec -n vault vault-0 -- vault write pki/issue/service-tls \
  common_name=myapp.dev.local.me \
  ttl=720h

# Or use k3d-manager's certificate helpers
```

### 2. Create Kubernetes Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-tls
  namespace: istio-system
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-cert>
  tls.key: <base64-encoded-key>
```

### 3. Create Gateway

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: myapp-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https-myapp
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: myapp-tls
    hosts:
    - myapp.dev.local.me
```

### 4. Create VirtualService

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp
  namespace: myapp
spec:
  hosts:
  - myapp.dev.local.me
  gateways:
  - istio-system/myapp-gateway
  http:
  - route:
    - destination:
        host: myapp.myapp.svc.cluster.local
        port:
          number: 8080
```

### 5. Update Client DNS

```bash
# Add to /etc/hosts on client machines
10.211.55.14 myapp.dev.local.me
```

**No changes needed to port forwarding!** The existing socat forward handles all services automatically via SNI routing.

## Troubleshooting

### Port 443 Not Listening

```bash
# Check if service is running
sudo systemctl status k3s-ingress-forward

# Check port
sudo ss -tlnp | grep :443

# Restart service
sudo systemctl restart k3s-ingress-forward
```

### Connection Refused

```bash
# Verify Istio IngressGateway is running
kubectl get pod -n istio-system -l app=istio-ingressgateway

# Check NodePort
kubectl get svc -n istio-system istio-ingressgateway -o yaml | grep nodePort
```

### Wrong Certificate Returned

```bash
# Test SNI with openssl
echo | openssl s_client -connect jenkins.dev.local.me:443 -servername jenkins.dev.local.me 2>/dev/null | openssl x509 -noout -text

# Should show CN=jenkins.dev.local.me

# If wrong cert is returned, check Gateway configuration
kubectl get gateway -n istio-system -o yaml
```

### Service Not Routing

```bash
# Check VirtualService
kubectl get virtualservice -A

# Verify Gateway reference
kubectl get virtualservice -n myapp myapp -o yaml

# Check Istio configuration
kubectl -n istio-system logs -l app=istiod --tail=50
```

## Configuration Variables

Control ingress forwarding behavior with environment variables:

```bash
# Enable/disable auto-setup during deploy_cluster
K3S_INGRESS_FORWARD_ENABLED=1  # default

# Change external port (if 443 is unavailable)
K3S_INGRESS_FORWARD_HTTPS_PORT=8443

# Override node IP detection
K3S_NODE_IP=192.168.1.100

# Change systemd service name
K3S_INGRESS_SERVICE_NAME=custom-ingress-forward
```

## Security Considerations

### TLS Certificate Validation

- Each service has its own certificate from Vault PKI
- Certificates are automatically rotated (default 30-day TTL)
- Clients validate certificate matches requested hostname
- No certificate sharing between services

### Network Isolation

- socat runs as root (required for port 443)
- Only forwards to localhost (Istio IngressGateway)
- Istio enforces authentication/authorization policies
- Services remain isolated in their namespaces

### Secret Management

- TLS certificates stored in Kubernetes secrets
- Vault PKI issues and tracks all certificates
- Automatic rotation via CronJobs
- Old certificates revoked in Vault

## Performance Characteristics

### Latency

- socat: ~0.1ms overhead (raw TCP forwarding)
- Istio: ~1-2ms for TLS + routing
- Total added latency: ~2ms

### Throughput

- socat: Near line-rate (kernel forwarding)
- Istio: Scales horizontally (multiple replicas)
- Bottleneck typically at application, not ingress

### Connection Limits

- socat: Thousands of concurrent connections (fork mode)
- Istio: Configurable via resource limits
- systemd: Auto-restart on failure

## Comparison: k3d vs k3s

| Feature | k3d (Docker) | k3s (Native) |
|---------|--------------|--------------|
| Port forwarding | Automatic (Docker) | Manual (socat) |
| Setup | Simple | Requires systemd |
| Performance | Container overhead | Native performance |
| Persistence | Container lifecycle | systemd service |
| Management | docker restart | systemctl restart |

## WSL (Windows Subsystem for Linux) Support

### WSL2 with systemd

**✅ Fully Supported (WSL2 with systemd enabled)**

The ingress forwarding works in WSL2 if systemd is enabled:

#### 1. Enable systemd in WSL2

```bash
# Inside WSL, create/edit /etc/wsl.conf
sudo tee /etc/wsl.conf > /dev/null <<EOF
[boot]
systemd=true
EOF

# Restart WSL (on Windows PowerShell)
wsl --shutdown
wsl
```

#### 2. Deploy with Port Forwarding

```bash
# Inside WSL:
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster
```

The script will detect WSL and provide appropriate instructions.

### Accessing Services from Windows Host {#wsl-windows-access}

WSL2 uses a virtualized network, so services running in WSL require additional configuration to access from Windows:

#### Option 1: Use WSL IP with NodePort (Simplest)

```bash
# Inside WSL, get IP address:
hostname -I
# Example output: 172.28.208.1
```

**On Windows, edit hosts file (as Administrator):**
```
# C:\Windows\System32\drivers\etc\hosts
172.28.208.1 jenkins.dev.local.me
172.28.208.1 argocd.dev.local.me
```

**Access services via NodePort:**
```
https://jenkins.dev.local.me:32653/
https://argocd.dev.local.me:32653/
```

**Note:** WSL IP changes on restart. You'll need to update the hosts file.

#### Option 2: Windows Port Forwarding (Port 443)

**Set up port forwarding (Windows PowerShell as Administrator):**
```powershell
# Get WSL IP
wsl hostname -I
# Example: 172.28.208.1

# Forward Windows port 443 to WSL port 443
netsh interface portproxy add v4tov4 listenport=443 listenaddress=0.0.0.0 connectport=443 connectaddress=172.28.208.1

# View configured forwards
netsh interface portproxy show all

# Delete if needed
netsh interface portproxy delete v4tov4 listenport=443 listenaddress=0.0.0.0
```

**Update Windows hosts:**
```
# C:\Windows\System32\drivers\etc\hosts
127.0.0.1 jenkins.dev.local.me
127.0.0.1 argocd.dev.local.me
```

**Access on standard port:**
```
https://jenkins.dev.local.me/
https://argocd.dev.local.me/
```

#### Option 3: Mirrored Networking (Windows 11 22H2+)

**Enable in `.wslconfig` (Windows):**
```ini
# C:\Users\<YourUsername>\.wslconfig
[wsl2]
networkingMode=mirrored
```

**Restart WSL:**
```powershell
wsl --shutdown
wsl
```

With mirrored networking, ports bound in WSL are automatically accessible from Windows on localhost.

### Accessing from Within WSL

Simple - just use localhost:

```bash
# Inside WSL, add to /etc/hosts:
127.0.0.1 jenkins.dev.local.me
127.0.0.1 argocd.dev.local.me

# Access services:
curl https://jenkins.dev.local.me/
argocd login argocd.dev.local.me --username admin
```

### WSL1 Limitations

**❌ Not Supported (No systemd)**

WSL1 does not support systemd, which is required for the automatic service setup.

**Workaround:**
Run socat manually in a background terminal:

```bash
# Inside WSL1:
sudo socat TCP-LISTEN:443,fork,reuseaddr TCP:localhost:32653 &

# Or use screen/tmux to keep it running
screen -S ingress-forward
sudo socat TCP-LISTEN:443,fork,reuseaddr TCP:localhost:32653
# Ctrl+A, D to detach
```

### Checking Your WSL Version

```powershell
# On Windows PowerShell:
wsl --list --verbose

# Output:
#   NAME      STATE           VERSION
# * Ubuntu    Running         2         ← WSL2
```

### WSL-Specific Troubleshooting

**Port 443 not accessible from Windows:**
- Verify socat is running: `sudo ss -tlnp | grep :443`
- Check Windows Firewall isn't blocking
- Verify WSL IP with `hostname -I`
- Update Windows hosts file with current WSL IP

**systemd not available:**
- Check WSL version: `wsl --list --verbose` (needs WSL2)
- Verify `/etc/wsl.conf` has `[boot] systemd=true`
- Restart WSL completely: `wsl --shutdown` then `wsl`
- Check systemd status: `systemctl --version`

**Services work in WSL but not from Windows:**
- This is expected WSL2 behavior
- Use one of the Windows access methods above
- Consider mirrored networking if on Windows 11 22H2+

## References

- [Istio Gateway Configuration](https://istio.io/latest/docs/reference/config/networking/gateway/)
- [SNI (RFC 6066)](https://tools.ietf.org/html/rfc6066#section-3)
- [socat Documentation](http://www.dest-unreach.org/socat/doc/socat.html)
- [Vault PKI Secrets Engine](https://www.vaultproject.io/docs/secrets/pki)

## Related Documentation

- [Vault PKI Setup](../howto/vault-pki-setup.md)
- [SSL Certificate Scripts](../../bin/setup-vault-ca.sh)
- [k3s Provider Configuration](../../scripts/lib/providers/k3s.sh)
