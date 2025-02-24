# Linkerd Service Mesh Setup

This document details the steps to install and configure Linkerd service mesh in the Kubernetes cluster.

## Prerequisites

- Kubernetes cluster running Microk8s
- kubectl configured to access the cluster
- Linkerd CLI installed

## Compatibility Check

First, check if your cluster is ready for Linkerd installation:

```bash
linkerd check --pre
```

## Installation Process

### 1. Install Linkerd CRDs

Install the custom resource definitions (CRDs) needed by Linkerd:

```bash
linkerd install --crds | kubectl apply -f -
```

### 2. Install Linkerd Control Plane

Install the Linkerd control plane components:

```bash
linkerd install | kubectl apply -f -
```

If you encounter permission issues, you may need to configure proxyInit to run as root:

```bash
linkerd install --set proxyInit.runAsRoot=true | kubectl apply -f -
```

### 3. Verify Installation

Check that Linkerd has been installed correctly:

```bash
linkerd check
```

### 4. Install Visualization Extension

Install the Linkerd visualization components for monitoring:

```bash
linkerd viz install | kubectl apply -f -
```

## Using Linkerd

### Inject Linkerd Proxies into Deployments

Inject Linkerd proxies into your deployments:

```bash
kubectl get deploy -n file-server -o yaml | linkerd inject - | kubectl apply -f -
```

### Monitor Service Metrics

View traffic metrics for services:

```bash
linkerd viz stat deploy -n file-server
```

### View Service Dependencies

Visualize service dependencies:

```bash
linkerd edges -n file-server
```

### Access Linkerd Dashboard

Open the Linkerd dashboard for visualization:

```bash
linkerd viz dashboard
```

## Prometheus Integration for Linkerd Metrics

Create a ServiceMonitor to collect Linkerd metrics in Prometheus:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: linkerd-federate
  namespace: linkerd-viz
spec:
  selector:
    matchLabels:
      linkerd.io/control-plane-component: prometheus
  namespaceSelector:
    matchNames:
    - linkerd-viz
  endpoints:
  - port: admin-http
    interval: 30s
    path: /federate
    params:
      match[]:
      - '{job="linkerd-proxy"}'
      - '{job="linkerd-controller"}'
EOF
```

## Access Prometheus in Linkerd-Viz Namespace

Forward the Prometheus port to access its UI:

```bash
kubectl port-forward -n linkerd-viz service/prometheus 9090:9090
```
