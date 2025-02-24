# HashiCorp Vault Setup

This document details the steps to install and configure HashiCorp Vault for secret management in the Kubernetes cluster.

## Prerequisites

- Kubernetes cluster running
- Helm installed
- kubectl configured to access the cluster

## Installation Process

### 1. Add HashiCorp Helm Repository

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

### 2. Create Namespace for Vault

```bash
kubectl create namespace vault
```

### 3. Configure Vault Helm Values

Create a `vault-values.yaml` file with the following content for a development setup:

```bash
cat > vault-values.yaml << EOF
server:
   affinity: ""
   ha:
      enabled: true
      raft: 
         enabled: true
         setNodeId: true
         config: |
            cluster_name = "vault-integrated-storage"
            storage "raft" {
               path    = "/vault/data/"
            }

            listener "tcp" {
               address = "[::]:8200"
               cluster_address = "[::]:8201"
               tls_disable = "true"
            }
            service_registration "kubernetes" {}
EOF
```

### 4. Install Vault with Helm

```bash
helm install vault hashicorp/vault --values vault-values.yaml -n vault
```

### 5. Initialize Vault

Initialize Vault and save the unseal keys and root token:

```bash
kubectl exec vault-0 -n vault -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > cluster-keys.json
```

### 6. Unseal Vault Nodes

Unseal the first Vault server:

```bash
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)
kubectl exec vault-0 -n vault -- vault operator unseal $VAULT_UNSEAL_KEY
```

If using HA setup, join other nodes to the Vault cluster and unseal them:

```bash
kubectl exec -ti vault-1 -n vault -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -ti vault-2 -n vault -- vault operator raft join http://vault-0.vault-internal:8200

kubectl exec -ti vault-1 -n vault -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -ti vault-2 -n vault -- vault operator unseal $VAULT_UNSEAL_KEY
```

### 7. Configure Vault

Extract the root token for authentication:

```bash
export ROOT_TOKEN=$(jq -r ".root_token" cluster-keys.json)
```

Port forward to access Vault API:

```bash
kubectl port-forward svc/vault 8200:8200 -n vault &

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$ROOT_TOKEN
```

### 8. Configure Vault for Secret Management

Enable the Kubernetes authentication method:

```bash
vault auth enable kubernetes
```

Configure Kubernetes authentication:

```bash
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    issuer="https://kubernetes.default.svc.cluster.local" \
    disable_iss_validation=true
```

Enable the KV secrets engine version 2:

```bash
vault secrets enable -path=secret kv-v2
```

Create policies for applications:

```bash
vault policy write file-server - <<EOF
path "secret/data/file-server/*" {
  capabilities = ["read"]
}
EOF
```

Create roles for Kubernetes service accounts:

```bash
vault write auth/kubernetes/role/file-server \
    bound_service_account_names=file-server \
    bound_service_account_namespaces=file-server \
    policies=file-server \
    ttl=1h
```

### 9. Store Secrets in Vault

Store MinIO credentials:

```bash
vault kv put secret/file-server/minio \
    access_key=minioadmin \
    secret_key=minioadmin
```

## Accessing Vault

To access the Vault UI or API:

```bash
kubectl port-forward svc/vault 8200:8200 -n vault &
```

Then visit http://localhost:8200 in your browser or use the Vault CLI with:

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$ROOT_TOKEN
vault login $VAULT_TOKEN
```

## Verify Stored Secrets

To verify that secrets are properly stored:

```bash
vault kv get secret/file-server/minio
```
Great! You've successfully set up Vault in HA mode with Raft storage. Let's now proceed with installing the External Secrets Operator and configure it to work with Vault.

1. First, let's add the External Secrets Operator Helm repository:

```bash
# Add External Secrets Operator helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
```

2. Install External Secrets Operator:

```bash
# Create namespace for External Secrets
kubectl create namespace external-secrets

# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true
```

3. Next, let's configure Vault to store our MinIO credentials. First, port-forward the Vault service to access it locally:

```bash
# Port forward Vault service
kubectl port-forward svc/vault 8200:8200 &

# Set Vault address and token
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(jq -r ".root_token" cluster-keys.json)

# Login to Vault
vault login $VAULT_TOKEN
```

4. Now, configure Vault and store our credentials:

```bash
# Enable the KV secrets engine
vault secrets enable -path=secret kv-v2

# Store MinIO credentials
vault kv put secret/file-server/minio \
    access_key=minioadmin \
    secret_key=minioadmin

# Enable Kubernetes authentication
vault auth enable kubernetes

# Configure Kubernetes authentication
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    issuer="https://kubernetes.default.svc.cluster.local" \
    disable_iss_validation=true

# Create a policy for accessing MinIO credentials
vault policy write file-server - <<EOF
path "secret/data/file-server/minio" {
  capabilities = ["read"]
}
EOF

# Create a Kubernetes auth role
vault write auth/kubernetes/role/file-server \
    bound_service_account_names=file-server \
    bound_service_account_namespaces=file-server \
    policies=file-server \
    ttl=1h
```

5. Now, let's create a service account in the file-server namespace:

```bash
kubectl create namespace file-server --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: file-server
  namespace: file-server
EOF
```

6. Configure the SecretStore and ExternalSecret resources:

```bash
# Create a SecretStore that connects to Vault
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: file-server
spec:
  provider:
    vault:
      server: "http://vault.default:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "file-server"
          serviceAccountRef:
            name: "file-server"
EOF

# Create an ExternalSecret that fetches MinIO credentials
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: minio-credentials
  namespace: file-server
spec:
  refreshInterval: "15m"
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: file-server-minio-secret
    creationPolicy: Owner
  data:
  - secretKey: access-key
    remoteRef:
      key: file-server/minio
      property: access_key
  - secretKey: secret-key
    remoteRef:
      key: file-server/minio
      property: secret_key
EOF
```


The key change needed is to remove our direct secret creation and instead rely on the ExternalSecret to create it for us.
We need to update our Helm chart to use the secrets.
