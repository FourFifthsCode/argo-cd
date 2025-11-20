#!/bin/bash
# Generate argocd-cm patch with embedded rootCA for OIDC

CA_FILE="${1:-certs/rootCA.pem}"

if [ ! -f "$CA_FILE" ]; then
    echo "Error: CA file not found at $CA_FILE" >&2
    exit 1
fi

# Read and indent CA cert
CA_CONTENT=$(awk '{print "      " $0}' "$CA_FILE")

cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  url: https://argocd.minikube.test
  oidc.config: |
    name: Keycloak
    issuer: https://keycloak.minikube.test/realms/argocd
    clientID: argocd
    clientSecret: aJZkkEAsql2HjF8LMw5w9Sap5FDi88CA
    requestedScopes: ["openid", "profile", "email", "groups"]
    rootCA: |
$CA_CONTENT
EOF

