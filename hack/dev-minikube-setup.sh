#!/bin/bash
set -e

# Minikube Development Setup Script
# Handles DNS (dnsmasq), TLS certificates (mkcert), and local development configuration

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CERTS_DIR="manifests/dev-tilt/keycloak/certs"
DOMAIN="keycloak.minikube.test"

#######################################
# Functions
#######################################

check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -e "${YELLOW}⚠️  This script is only for macOS. Skipping.${NC}"
        exit 0
    fi
}

#######################################
# DNS Setup
#######################################

setup_dns() {
    check_macos
    echo -e "${YELLOW}🚀 Setting up DNS for .minikube.test domains...${NC}"

    # Check minikube
    if ! minikube status > /dev/null 2>&1; then
        echo -e "${RED}❌ Minikube is not running. Start with: minikube start${NC}"
        exit 1
    fi

    # Detect port 53 conflicts
    DNS_CONFLICT=$(sudo lsof -i :53 2>/dev/null | grep -E "localhost.*domain|127\.0\.0\.1.*domain" | grep -v dnsmasq || true)
    USE_ALTERNATE_IP=false

    if [ -n "$DNS_CONFLICT" ]; then
        echo -e "${YELLOW}⚠️  Port 53 on 127.0.0.1 in use. Using 127.0.0.2${NC}"
        USE_ALTERNATE_IP=true
    fi

    # Install dnsmasq
    if ! command -v dnsmasq &> /dev/null; then
        echo -e "${YELLOW}📦 Installing dnsmasq...${NC}"
        brew install dnsmasq
    fi

    # Determine IP
    if [ "$USE_ALTERNATE_IP" = true ]; then
        DNSMASQ_IP="127.0.0.2"
        if ! ifconfig lo0 | grep -q "127.0.0.2"; then
            echo -e "${GREEN}🔧 Creating loopback alias...${NC}"
            sudo ifconfig lo0 alias 127.0.0.2 up
        fi
    else
        DNSMASQ_IP="127.0.0.1"
    fi

    # Configure dnsmasq
    echo -e "${GREEN}📝 Configuring dnsmasq...${NC}"
    cat > "/opt/homebrew/etc/dnsmasq.conf" << EOF
listen-address=$DNSMASQ_IP
port=53
no-resolv
no-hosts
server=8.8.8.8
server=8.8.4.4
address=/minikube.test/127.0.0.1
EOF

    # Start/restart dnsmasq
    if pgrep -f "dnsmasq" > /dev/null; then
        if dig +short +timeout=1 $DOMAIN @$DNSMASQ_IP 2>/dev/null | grep -q "127.0.0.1"; then
            echo -e "${GREEN}✓ dnsmasq already running${NC}"
        else
            sudo pkill dnsmasq || true
            sleep 1
            sudo /opt/homebrew/opt/dnsmasq/sbin/dnsmasq -C /opt/homebrew/etc/dnsmasq.conf
        fi
    else
        echo -e "${GREEN}🚀 Starting dnsmasq...${NC}"
        sudo /opt/homebrew/opt/dnsmasq/sbin/dnsmasq -C /opt/homebrew/etc/dnsmasq.conf
    fi

    # Create resolver
    sudo mkdir -p /etc/resolver
    if [ -f /etc/resolver/minikube-test ]; then
        CURRENT_NS=$(grep nameserver /etc/resolver/minikube-test 2>/dev/null | awk '{print $2}')
        if [ "$CURRENT_NS" != "$DNSMASQ_IP" ]; then
            sudo tee /etc/resolver/minikube-test > /dev/null << RESOLVER_EOF
domain minikube.test
nameserver $DNSMASQ_IP
RESOLVER_EOF
        fi
    else
        echo -e "${GREEN}📝 Creating /etc/resolver/minikube-test...${NC}"
        sudo tee /etc/resolver/minikube-test > /dev/null << RESOLVER_EOF
domain minikube.test
nameserver $DNSMASQ_IP
RESOLVER_EOF
    fi

    # Clean up old configs
    [ -f /etc/resolver/dev ] && sudo rm /etc/resolver/dev
    [ -f /etc/resolver/minikube-dev ] && sudo rm /etc/resolver/minikube-dev
    [ -f /etc/resolver/test ] && sudo rm /etc/resolver/test

    # Reload DNS
    sudo launchctl enable system/com.apple.mDNSResponder.reloaded 2>/dev/null || true
    sudo launchctl disable system/com.apple.mDNSResponder.reloaded 2>/dev/null || true
    sleep 2

    # Test
    if dig +short $DOMAIN @$DNSMASQ_IP | grep -q "127.0.0.1"; then
        echo -e "${GREEN}✅ DNS working! *.minikube.test → 127.0.0.1${NC}"
        echo -e "${YELLOW}📝 Run 'minikube tunnel' in separate terminal${NC}"
    else
        echo -e "${RED}❌ DNS test failed${NC}"
        exit 1
    fi
}

#######################################
# TLS Setup
#######################################

setup_tls() {
    echo -e "${GREEN}🔐 Setting up TLS certificates...${NC}"

    # Install mkcert
    if ! command -v mkcert &> /dev/null; then
        echo -e "${YELLOW}📦 Installing mkcert...${NC}"
        brew install mkcert
    fi

    # Install CA
    if ! mkcert -CAROOT > /dev/null 2>&1 || ! ls "$(mkcert -CAROOT)/rootCA.pem" > /dev/null 2>&1; then
        echo -e "${GREEN}📦 Installing CA...${NC}"
        mkcert -install
    fi

    mkdir -p "$CERTS_DIR"
    CERT_FILE="$CERTS_DIR/tls.crt"
    KEY_FILE="$CERTS_DIR/tls.key"

    # Check existing certs
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        if openssl x509 -in "$CERT_FILE" -noout -checkend 86400 > /dev/null 2>&1; then
            EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
            echo -e "${BLUE}ℹ️  Valid certs exist (expires: $EXPIRY)${NC}"
            # Still update CA references
            update_ca_references
            return 0
        fi
    fi

    # Generate wildcard cert for all .minikube.test domains
    echo -e "${GREEN}🔐 Generating wildcard certificate for *.minikube.test...${NC}"
    cd "$CERTS_DIR"
    mkcert -cert-file tls.crt -key-file tls.key "*.minikube.test" 2>/dev/null
    cd - > /dev/null

    EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
    echo -e "${GREEN}✅ Certificates created (expires: $EXPIRY)${NC}"
    
    # Update CA references
    update_ca_references
}

update_ca_references() {
    # Copy CA to manifests directory for kustomize reference
    CA_ROOT=$(mkcert -CAROOT 2>/dev/null)
    if [ -n "$CA_ROOT" ] && [ -f "$CA_ROOT/rootCA.pem" ]; then
        mkdir -p manifests/dev-tilt/certs
        cp "$CA_ROOT/rootCA.pem" manifests/dev-tilt/certs/rootCA.pem
        
        # Generate argocd-cm-patch.yaml with rootCA
        if [ -f "manifests/dev-tilt/generate-oidc-patch.sh" ]; then
            cd manifests/dev-tilt
            ./generate-oidc-patch.sh certs/rootCA.pem > argocd-cm-patch.yaml
            cd - > /dev/null
        fi
    fi
}

#######################################
# Configure CoreDNS for in-cluster resolution
#######################################

configure_coredns() {
    echo -e "${GREEN}🔧 Configuring in-cluster DNS...${NC}"
    
    # Check if minikube is running
    if ! minikube status > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Minikube not running, skipping CoreDNS configuration${NC}"
        return 0
    fi
    
    # Get ingress controller IP
    INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    
    if [ -z "$INGRESS_IP" ]; then
        echo -e "${YELLOW}⚠️  Ingress controller not found, skipping CoreDNS configuration${NC}"
        return 0
    fi
    
    # Get minikube host IP (for host.minikube.internal)
    # First try to get it from existing CoreDNS config
    HOST_IP=$(kubectl get configmap coredns -n kube-system -o yaml 2>/dev/null | grep "host.minikube.internal" | awk '{print $1}')
    
    # If not found in CoreDNS, get it from minikube
    if [ -z "$HOST_IP" ]; then
        HOST_IP=$(minikube ssh "route -n | grep ^0.0.0.0 | awk '{print \$2}'" 2>/dev/null | tr -d '\r')
    fi
    
    # Fallback to a common default if still not found
    if [ -z "$HOST_IP" ]; then
        HOST_IP="192.168.5.2"
        echo -e "${YELLOW}⚠️  Could not detect host IP, using default: $HOST_IP${NC}"
    fi
    
    # Check if already configured correctly
    if kubectl get configmap coredns -n kube-system -o yaml 2>/dev/null | grep -q "minikube.test:53"; then
        CURRENT_CONFIG=$(kubectl get configmap coredns -n kube-system -o yaml 2>/dev/null | grep -A 5 "minikube.test:53")
        if echo "$CURRENT_CONFIG" | grep -q "template.*minikube.test"; then
            echo -e "${GREEN}✓ CoreDNS already configured correctly${NC}"
            return 0
        fi
    fi
    
    echo -e "${BLUE}📝 Updating CoreDNS: $DOMAIN → $INGRESS_IP (host: $HOST_IP)...${NC}"
    
    # Apply CoreDNS configuration
    kubectl patch configmap coredns -n kube-system --type merge -p "$(cat <<EOF
data:
  Corefile: |
    .:53 {
        log
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        hosts {
           $HOST_IP host.minikube.internal
           fallthrough
        }
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
    minikube.test:53 {
        errors
        cache 30
        template IN A minikube.test {
           answer "{{ .Name }} 60 IN A $INGRESS_IP"
        }
        forward . /etc/resolv.conf
    }
EOF
)" > /dev/null 2>&1
    
    # Restart CoreDNS
    kubectl rollout restart deployment/coredns -n kube-system > /dev/null 2>&1
    kubectl rollout status deployment/coredns -n kube-system --timeout=30s > /dev/null 2>&1
    
    echo -e "${GREEN}✅ CoreDNS configured for in-cluster resolution${NC}"
}

#######################################
# Configure ArgoCD to trust mkcert CA
#######################################

configure_argocd_ca() {
    echo -e "${GREEN}🔐 Configuring ArgoCD to trust mkcert CA...${NC}"
    
    # Check if ArgoCD namespace exists
    if ! kubectl get namespace argocd > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  ArgoCD namespace not found, skipping CA configuration${NC}"
        return 0
    fi
    
    # Get mkcert CA root
    CA_ROOT=$(mkcert -CAROOT 2>/dev/null)
    if [ -z "$CA_ROOT" ] || [ ! -f "$CA_ROOT/rootCA.pem" ]; then
        echo -e "${YELLOW}⚠️  mkcert CA not found, skipping${NC}"
        return 0
    fi
    
    # Check if CA is already configured
    if kubectl get configmap argocd-tls-certs-cm -n argocd -o yaml 2>/dev/null | grep -q "mkcert-ca.crt"; then
        CURRENT_CA=$(kubectl get configmap argocd-tls-certs-cm -n argocd -o jsonpath='{.data.mkcert-ca\.crt}' 2>/dev/null | head -1)
        NEW_CA=$(head -1 "$CA_ROOT/rootCA.pem")
        if [ "$CURRENT_CA" = "$NEW_CA" ]; then
            echo -e "${GREEN}✓ ArgoCD CA already configured correctly${NC}"
            return 0
        fi
    fi
    
    echo -e "${BLUE}📝 Adding mkcert CA to ArgoCD trusted certificates...${NC}"
    
    # Create or update the ConfigMap
    # Add CA cert with both hostname keys and generic key for maximum compatibility
    kubectl create configmap argocd-tls-certs-cm -n argocd \
        --from-file="keycloak.minikube.test=$CA_ROOT/rootCA.pem" \
        --from-file="argocd.minikube.test=$CA_ROOT/rootCA.pem" \
        --from-file="mkcert-ca.crt=$CA_ROOT/rootCA.pem" \
        --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
    
    # Restart ArgoCD server to pick up the new CA
    if kubectl get deployment argocd-server -n argocd > /dev/null 2>&1; then
        echo -e "${BLUE}🔄 Restarting ArgoCD server...${NC}"
        kubectl rollout restart deployment/argocd-server -n argocd > /dev/null 2>&1
        kubectl rollout status deployment/argocd-server -n argocd --timeout=60s > /dev/null 2>&1
    fi
    
    echo -e "${GREEN}✅ ArgoCD now trusts mkcert CA${NC}"
}

#######################################
# Check Status
#######################################

check_status() {
    check_macos
    echo -e "${BLUE}📊 Checking status...${NC}\n"

    # DNS
    if pgrep -f "dnsmasq" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ dnsmasq running${NC}"
    else
        echo -e "${RED}✗ dnsmasq not running${NC}"
    fi

    if [ -f /etc/resolver/minikube-test ]; then
        echo -e "${GREEN}✓ /etc/resolver/minikube-test exists${NC}"
    else
        echo -e "${RED}✗ /etc/resolver/minikube-test missing${NC}"
    fi

    # Use dscacheutil on macOS (more reliable than dig)
    if dscacheutil -q host -a name $DOMAIN 2>/dev/null | grep -q "ip_address: 127.0.0.1"; then
        echo -e "${GREEN}✓ DNS resolving $DOMAIN → 127.0.0.1${NC}"
    else
        echo -e "${RED}✗ DNS not resolving $DOMAIN${NC}"
    fi

    # TLS
    if [ -f "$CERTS_DIR/tls.crt" ] && [ -f "$CERTS_DIR/tls.key" ]; then
        if openssl x509 -in "$CERTS_DIR/tls.crt" -noout -checkend 86400 > /dev/null 2>&1; then
            echo -e "${GREEN}✓ TLS certificates valid${NC}"
        else
            echo -e "${YELLOW}⚠️  TLS certificates expiring soon${NC}"
        fi
    else
        echo -e "${RED}✗ TLS certificates missing${NC}"
    fi

    # Minikube
    if minikube status > /dev/null 2>&1; then
        echo -e "${GREEN}✓ minikube running${NC}"
    else
        echo -e "${RED}✗ minikube not running${NC}"
    fi

    if pgrep -f "minikube tunnel" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ minikube tunnel running${NC}"
    else
        echo -e "${YELLOW}⚠️  minikube tunnel not running${NC}"
    fi

    # In-cluster DNS test
    if minikube status > /dev/null 2>&1; then
        echo ""
        echo -e "${BLUE}🔍 In-cluster DNS test:${NC}"
        
        # Check if test pod already exists
        kubectl delete pod dns-test --ignore-not-found=true > /dev/null 2>&1
        
        # Create temporary test pod and wait for it
        if kubectl run dns-test --image=nicolaka/netshoot --restart=Never --command -- sleep 30 > /dev/null 2>&1; then
            # Wait for pod to be ready
            if kubectl wait --for=condition=ready pod/dns-test --timeout=15s > /dev/null 2>&1; then
                # Test DNS resolution from inside cluster
                INCLUSTER_DNS=$(kubectl exec dns-test -- nslookup $DOMAIN 2>/dev/null | grep "^Name:" -A 1 | grep "Address:" | awk '{print $2}' | head -1)
                INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
                
                if [ "$INCLUSTER_DNS" = "$INGRESS_IP" ]; then
                    echo -e "${GREEN}✓ in-cluster DNS: $DOMAIN → $INGRESS_IP (ingress)${NC}"
                elif [ "$INCLUSTER_DNS" = "127.0.0.1" ]; then
                    echo -e "${YELLOW}⚠️  in-cluster DNS: $DOMAIN → 127.0.0.1 (run './hack/dev-setup.sh setup' to fix)${NC}"
                else
                    echo -e "${YELLOW}⚠️  in-cluster DNS: $DOMAIN → ${INCLUSTER_DNS:-not resolved}${NC}"
                fi
                
                # Cleanup
                kubectl delete pod dns-test --force --grace-period=0 > /dev/null 2>&1
            else
                echo -e "${YELLOW}⚠️  Test pod failed to start${NC}"
                kubectl delete pod dns-test --force --grace-period=0 > /dev/null 2>&1
            fi
        else
            echo -e "${YELLOW}⚠️  Could not create test pod${NC}"
        fi
    fi
}

#######################################
# Cleanup
#######################################

cleanup() {
    check_macos
    echo -e "${YELLOW}🧹 Cleaning up...${NC}"

    CHANGED=false

    # Stop dnsmasq
    if pgrep -f "dnsmasq" > /dev/null; then
        echo -e "${GREEN}🛑 Stopping dnsmasq...${NC}"
        sudo pkill dnsmasq || true
        CHANGED=true
    fi

    # Remove loopback alias
    if ifconfig lo0 | grep -q "127.0.0.2"; then
        echo -e "${GREEN}🔧 Removing loopback alias...${NC}"
        sudo ifconfig lo0 -alias 127.0.0.2 2>/dev/null || true
        CHANGED=true
    fi

    # Remove resolvers
    for file in /etc/resolver/minikube-test /etc/resolver/test /etc/resolver/dev /etc/resolver/minikube-dev; do
        if [ -f "$file" ]; then
            echo -e "${GREEN}📝 Removing $(basename $file)...${NC}"
            sudo rm "$file"
            CHANGED=true
        fi
    done

    if [ "$CHANGED" = true ]; then
        sudo launchctl enable system/com.apple.mDNSResponder.reloaded 2>/dev/null || true
        sudo launchctl disable system/com.apple.mDNSResponder.reloaded 2>/dev/null || true
        echo -e "${GREEN}✅ Cleanup complete${NC}"
    else
        echo -e "${GREEN}✅ Already clean${NC}"
    fi
}

#######################################
# Main
#######################################

usage() {
    cat << EOF
Minikube Development Setup

Usage: $0 <command>

Commands:
  setup     Setup DNS and TLS certificates
  dns       Setup DNS only
  tls       Setup TLS certificates only
  check     Check current status
  cleanup   Remove all configurations

Examples:
  $0 setup    # Full setup (DNS + TLS)
  $0 check    # Check status
  $0 cleanup  # Remove everything
EOF
    exit 1
}

case "${1:-}" in
    setup)
        echo -e "${BLUE}🚀 Running dev setup for minikube...${NC}"
        setup_dns
        setup_tls
        configure_coredns
        configure_argocd_ca
        echo -e "\n${GREEN}✅ Setup complete!${NC}"
        echo -e "${BLUE}Access services at:${NC}"
        echo -e "  • https://keycloak.minikube.test"
        echo -e "  • https://argocd.minikube.test"
        ;;
    dns)
        setup_dns
        ;;
    tls)
        setup_tls
        ;;
    check)
        check_status
        ;;
    cleanup)
        cleanup
        ;;
    *)
        usage
        ;;
esac

