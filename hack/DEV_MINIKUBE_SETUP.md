# Minikube Development Setup

Idempotent setup script for local ArgoCD development with Keycloak SSO on macOS + minikube.

## Purpose

Configures `*.minikube.test` wildcard DNS and TLS for seamless local development with proper HTTPS and service discovery.

## What It Does

**Host (macOS):**
- Installs and configures dnsmasq to resolve `*.minikube.test` → `127.0.0.1`
- Creates `/etc/resolver/minikube-test` for domain routing
- Generates wildcard TLS certificate with mkcert

**In-Cluster (Kubernetes):**
- Configures CoreDNS to resolve `*.minikube.test` → ingress controller IP
- Adds mkcert CA to ArgoCD trusted certificates
- Generates kustomize patch with OIDC config + CA

## System Changes

### macOS
```
/opt/homebrew/etc/dnsmasq.conf          # dnsmasq config
/etc/resolver/minikube-test             # DNS resolver config
127.0.0.2 loopback alias (if needed)    # Port 53 conflict workaround
```

### Kubernetes
```
ConfigMap/coredns (kube-system)         # Wildcard DNS template
ConfigMap/argocd-tls-certs-cm (argocd)  # mkcert CA trust
```

### Generated Files (Not in Git)
```
manifests/dev-tilt/keycloak/certs/tls.{crt,key}  # Wildcard cert
manifests/dev-tilt/certs/rootCA.pem              # mkcert CA copy
manifests/dev-tilt/argocd-cm-patch.yaml          # OIDC config patch
```

## Usage

```bash
# Full setup (run once or after minikube restart)
./hack/dev-minikube-setup.sh setup

# Check status
./hack/dev-minikube-setup.sh check

# Clean up all configs
./hack/dev-minikube-setup.sh cleanup
```

## Workflow

```bash
# 1. Start minikube
minikube start
minikube addons enable ingress

# 2. Run setup
./hack/dev-minikube-setup.sh setup

# 3. Start tunnel (separate terminal - must stay running)
minikube tunnel

# 4. Start Tilt (automatically reruns setup idempotently)
tilt up

# 5. Access services
open https://argocd.minikube.test
open https://keycloak.minikube.test
```

## Requirements

- macOS
- minikube (with Docker driver)
- Homebrew
- mkcert (installed by script if missing)
- dnsmasq (installed by script if missing)

## Idempotency

Safe to run multiple times - only makes changes when needed:
- ✓ Skips if dnsmasq already configured
- ✓ Skips if certificates valid (>24h before expiry)
- ✓ Skips if CoreDNS already configured
- ✓ Skips if ArgoCD CA already trusted
- ✓ Always regenerates patch files (fast operation)

## Troubleshooting

**DNS not resolving:**
```bash
./hack/dev-minikube-setup.sh check  # Diagnose issues
./hack/dev-minikube-setup.sh setup  # Re-run setup
```

**Certificate errors in browser:**
- Run `mkcert -install` to trust the CA
- Restart browser

**In-cluster certificate errors:**
- Script automatically configures ArgoCD CA trust
- Restart ArgoCD server: `kubectl rollout restart deployment/argocd-server -n argocd`

