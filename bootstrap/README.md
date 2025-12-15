# Bootstrap Guide

This guide explains how to bootstrap the CV-Site infrastructure with ArgoCD.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     ArgoCD (App of Apps)                        │
│                   Manages all applications                      │
└─────────────────────────────────────────────────────────────────┘
                              │
    ┌────────────┬────────────┼────────────┬────────────┐
    ▼            ▼            ▼            ▼            ▼
┌────────┐ ┌──────────┐ ┌──────────┐ ┌─────────┐ ┌───────────┐
│Traefik │ │ Authelia │ │  Kafka   │ │ CV-Site │ │ Monitoring│
│ (Ingress)│ │  (Auth)  │ │ (Strimzi)│ │  (Apps) │ │(Prometheus)│
└────────┘ └──────────┘ └──────────┘ └─────────┘ └───────────┘
```

## Sync Wave Order

| Wave | Component      | Description                           |
|------|----------------|---------------------------------------|
| 0    | ArgoCD         | Self-management (optional)            |
| 1    | Infrastructure | Namespaces, storage, secrets          |
| 2    | Traefik        | Ingress controller                    |
| 3    | Ingress        | IngressRoutes, Authelia, Middlewares  |
| 4    | Kafka          | Strimzi Kafka cluster                 |
| 5    | CV-Site        | Application workloads                 |
| 5    | Monitoring     | Prometheus, Grafana, AKHQ             |

## Prerequisites

1. **Kubernetes Cluster** (any of the following):
   - k3d / k3s
   - kind
   - minikube
   - Docker Desktop Kubernetes
   - Cloud-managed Kubernetes (EKS, GKE, AKS)

2. **Required Operators**:
   - [Strimzi Kafka Operator](https://strimzi.io/quickstarts/)
   - [cert-manager](https://cert-manager.io/docs/installation/)

3. **Local DNS** (for local development):
   Add to `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows):
   ```
   127.0.0.1 argocd.k8s.local
   127.0.0.1 auth.k8s.local
   127.0.0.1 cv.k8s.local
   127.0.0.1 api.k8s.local
   127.0.0.1 grafana.k8s.local
   127.0.0.1 prometheus.k8s.local
   127.0.0.1 akhq.k8s.local
   127.0.0.1 traefik.k8s.local
   ```

## Local Environment Bootstrap

### Step 1: Install Prerequisites

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=300s

# Install Strimzi Kafka Operator
kubectl create namespace kafka-prd
kubectl apply -f https://strimzi.io/install/latest?namespace=kafka-prd -n kafka-prd
```

### Step 2: Install ArgoCD

```bash
# Create ArgoCD namespace
kubectl apply -f argocd-namespace.yaml

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 3: Deploy App of Apps (Local Environment)

```bash
# Apply the local app-of-apps
kubectl apply -f app-of-apps-local.yaml
```

### Step 4: Access ArgoCD UI

Before Traefik is deployed, use port-forwarding:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Then access: https://localhost:8080

After everything is deployed, access via: https://argocd.k8s.local

## Production Environment Bootstrap

For production, use the standard app-of-apps:

```bash
kubectl apply -f app-of-apps.yaml
```

## URLs

### Local Environment (*.k8s.local)

| Service    | URL                          | Auth Required |
|------------|------------------------------|---------------|
| ArgoCD     | https://argocd.k8s.local     | Yes (Authelia)|
| Authelia   | https://auth.k8s.local       | No            |
| Frontend   | https://cv.k8s.local         | No            |
| API        | https://api.k8s.local        | No            |
| Grafana    | https://grafana.k8s.local    | Yes (Authelia)|
| Prometheus | https://prometheus.k8s.local | Yes (Authelia)|
| AKHQ       | https://akhq.k8s.local       | Yes (Authelia)|
| Traefik    | https://traefik.k8s.local    | Yes (Authelia)|

### Production Environment (*.sebastien.sh)

| Service    | URL                           | Auth Required |
|------------|-------------------------------|---------------|
| ArgoCD     | https://argocd.sebastien.sh   | Yes (Authelia)|
| Authelia   | https://auth.sebastien.sh     | No            |
| Frontend   | https://cv.sebastien.sh       | No            |
| API        | https://api.sebastien.sh      | No            |
| Grafana    | https://grafana.sebastien.sh  | Yes (Authelia)|
| Prometheus | https://prometheus.sebastien.sh| Yes (Authelia)|
| AKHQ       | https://akhq.sebastien.sh     | Yes (Authelia)|

## Default Credentials

### Authelia (Local)
- **Username**: admin
- **Password**: admin (CHANGE THIS!)

### Grafana
- **Username**: admin
- **Password**: admin (CHANGE THIS!)

### ArgoCD
- **Username**: admin
- **Password**: Retrieved from secret (see Step 2)

## Troubleshooting

### ArgoCD not syncing
```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller
```

### Traefik not routing
```bash
# Check Traefik logs
kubectl logs -n traefik deployment/traefik

# Check IngressRoutes
kubectl get ingressroutes -A
```

### Authelia not authenticating
```bash
# Check Authelia logs
kubectl logs -n authelia deployment/authelia

# Verify configuration
kubectl get configmap -n authelia authelia-config -o yaml
```

### Certificate issues
```bash
# Check certificates
kubectl get certificates -A

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```
