# CV Site GitOps

Kubernetes infrastructure for [cv-site](https://github.com/sebheuze/cv-site-package) using **Flux CD**, managed with Kustomize overlays.

## Architecture

```
Flux CD (GitOps)
  |
  ├── infrastructure/    Traefik, cert-manager, Strimzi, CloudNativePG, ESO
  ├── databases/         PostgreSQL (CNPG), Kafka (Strimzi KRaft)
  ├── apps/              frontend, trading-simulator, binance-ingester, AKHQ
  └── monitoring/        Prometheus, Grafana
```

Secrets are synced from an external **HashiCorp Vault** instance via External Secrets Operator. No secret values are stored in this repository.

## Directory Structure

```
clusters/
  ├── local/              Flux sync point for dev
  └── production/         Flux sync point for prod
infrastructure/
  ├── controllers/        HelmReleases (traefik, cert-manager, strimzi, cnpg, eso)
  └── configs/            Namespaces, ClusterIssuers, middlewares, IngressRoutes
databases/                CloudNativePG PostgreSQL + Strimzi Kafka clusters
apps/                     Application deployments (cv-site + AKHQ)
monitoring/               kube-prometheus-stack + Grafana
```

Each layer uses `base/`, `local/`, and `production/` overlays via Kustomize.

## Prerequisites

- Kubernetes cluster (K3s, Kind, or managed)
- [Flux CLI](https://fluxcd.io/flux/installation/)
- HashiCorp Vault (external) - see [INSTALL_VAULT.md](INSTALL_VAULT.md)

## Bootstrap

```bash
# Production
flux bootstrap github \
  --owner=<your-github-username> \
  --repository=cv-site-gitops \
  --branch=main \
  --path=clusters/production \
  --personal

# Local
flux bootstrap github \
  --owner=<your-github-username> \
  --repository=cv-site-gitops \
  --branch=main \
  --path=clusters/local \
  --personal
```

Then create the Vault token secret:
```bash
kubectl create secret generic vault-token \
  -n external-secrets \
  --from-literal=token=<your-vault-token>
```

## Dependency Chain

```
infra-controllers --> infra-configs --> databases --> apps
                                    └-> monitoring
```

## Key Components

| Component | Purpose |
|---|---|
| **Traefik** | Ingress controller with TLS termination |
| **cert-manager** | Automated Let's Encrypt certificates |
| **Authelia** | SSO with 2FA for admin services |
| **Strimzi** | Kafka operator (KRaft mode, no Zookeeper) |
| **CloudNativePG** | PostgreSQL operator |
| **External Secrets** | Vault-to-Kubernetes secret sync |
| **Prometheus + Grafana** | Monitoring and dashboards |

## License

MIT
