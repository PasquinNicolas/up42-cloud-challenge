> [!CAUTION]
> The usage of minikube was compromised, for this solution we used Microk8s
> See the file CHALLENGE.mb for more details.

# Minikube Cluster Setup

This document details the steps to set up a Minikube Kubernetes cluster for the UP42 File Server deployment.

## Prerequisites

- Docker installed
- Minikube binary installed
- kubectl installed

## Cluster Creation

Start by creating a Minikube cluster with the required resources and addons:

```bash
minikube start \
  --cpus 4 \
  --memory 8192 \
  --disk-size 80g \
  --driver docker \
  --addons metallb \
  --addons ingress \
  --addons metrics-server \
  --addons registry
```

## Verify Installation

Confirm the cluster is running and addons are properly installed:

```bash
kubectl get nodes
kubectl get pods -A
```

## Configure MetalLB Load Balancer

Configure MetalLB to assign external IPs to LoadBalancer services:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.49.100-192.168.49.200
EOF
```

## Configure Host File (Optional)

If you need to access services via domain names locally, add entries to your hosts file:

```bash
MINIKUBE_IP=$(minikube ip)
echo "$MINIKUBE_IP your-domain.local" | sudo tee -a /etc/hosts
```

## Troubleshooting

If you encounter issues with your Minikube installation, you can check the logs:

```bash
minikube logs
```

To completely reset Minikube if needed:

```bash
minikube delete
minikube stop
sudo rm -rf ~/.minikube
```

## Additional Commands

List all enabled addons:

```bash
minikube addons list
```

Access the Minikube dashboard:

```bash
minikube dashboard
```

Get the Minikube IP address:

```bash
minikube ip
```
