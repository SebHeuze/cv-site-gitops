# Architecture Documentation

## Overview

This GitOps repository implements a production-grade Kubernetes deployment using:
- **Helm** for templating and package management
- **Argo CD** for GitOps continuous deployment
- **Traefik** for ingress routing
- **Authelia** for SSO and 2FA protection

## Directory Structure

```
gitops/
├── bootstrap/                   # Argo CD bootstrap
│   ├── argocd-namespace.yaml   # Namespace definition
│   └── app-of-apps.yaml        # Root application
│
├── apps/                        # Argo CD Application CRs
│   ├── infrastructure.yaml     # Wave 0
│   ├── kafka.yaml              # Wave 1
│   ├── cv-site.yaml            # Wave 2
│   ├── monitoring.yaml         # Wave 3
│   └── ingress.yaml            # Wave 4
│
├── charts/                      # Helm charts
│   ├── infrastructure/         # Namespaces, storage, secrets
│   ├── kafka/                  # Strimzi Kafka
│   ├── cv-site/                # Application services
│   ├── monitoring/             # Prometheus, Grafana, AKHQ
│   └── ingress/                # Traefik + Authelia
│
├── environments/                # Environment overrides
│   └── production/
│       ├── infrastructure-values.yaml
│       ├── kafka-values.yaml
│       ├── cv-site-values.yaml
│       ├── monitoring-values.yaml
│       └── ingress-values.yaml
│
├── scripts/                     # Deployment scripts
└── docs/                        # Documentation
```

## Sync Waves

Applications are deployed in order using Argo CD sync waves:

```
Wave 0: Infrastructure
    └── Namespaces (kafka-prd, cv-site-prd, monitoring-prd, authelia)
    └── PersistentVolumeClaims
    └── Secrets (GHCR, PostgreSQL, Authelia)

Wave 1: Kafka
    └── Strimzi Kafka Cluster (KRaft mode, 3 brokers)
    └── KafkaNodePools (controllers, brokers)
    └── KafkaTopics

Wave 2: CV-Site
    └── PostgreSQL
    └── Binance Ingester
    └── Trading Simulator
    └── Frontend

Wave 3: Monitoring
    └── Prometheus
    └── Grafana
    └── AKHQ

Wave 4: Ingress
    └── Authelia (SSO)
    └── Traefik Middlewares
    └── IngressRoutes
    └── Certificates
```

## Data Flow

```
                    ┌─────────────────────────────────────────────────┐
                    │                  INTERNET                        │
                    └─────────────────────┬───────────────────────────┘
                                          │
                    ┌─────────────────────▼───────────────────────────┐
                    │              TRAEFIK INGRESS                     │
                    │  ┌─────────────────────────────────────────┐    │
                    │  │         cv.sebastien.sh (Public)        │    │
                    │  │        api.sebastien.sh (Public)        │    │
                    │  │       grafana.sebastien.sh (2FA)        │    │
                    │  │        akhq.sebastien.sh (2FA)          │    │
                    │  │      prometheus.sebastien.sh (2FA)      │    │
                    │  └─────────────────────────────────────────┘    │
                    └─────────────────────┬───────────────────────────┘
                                          │
            ┌─────────────────────────────┼─────────────────────────────┐
            │                             │                             │
            ▼                             ▼                             ▼
┌───────────────────┐       ┌───────────────────┐       ┌───────────────────┐
│     AUTHELIA      │       │    cv-site-prd    │       │  monitoring-prd   │
│  (SSO + 2FA)      │       │                   │       │                   │
│                   │       │  ┌─────────────┐  │       │  ┌─────────────┐  │
│  - User DB        │       │  │  Frontend   │  │       │  │ Prometheus  │  │
│  - Sessions       │       │  └─────────────┘  │       │  └─────────────┘  │
│  - TOTP           │       │         │         │       │         │         │
│                   │       │         ▼         │       │         ▼         │
└───────────────────┘       │  ┌─────────────┐  │       │  ┌─────────────┐  │
                            │  │   Trading   │  │       │  │   Grafana   │  │
                            │  │  Simulator  │◄─┼───────┼──│             │  │
                            │  └──────┬──────┘  │       │  └─────────────┘  │
                            │         │         │       │                   │
                            │         ▼         │       │  ┌─────────────┐  │
                            │  ┌─────────────┐  │       │  │    AKHQ     │  │
                            │  │ PostgreSQL  │  │       │  └─────────────┘  │
                            │  └─────────────┘  │       │                   │
                            └─────────┬─────────┘       └───────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────────────┐
                    │                 kafka-prd                        │
                    │  ┌───────────────────────────────────────────┐  │
                    │  │          Strimzi Kafka Cluster             │  │
                    │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐    │  │
                    │  │  │Broker 0 │  │Broker 1 │  │Broker 2 │    │  │
                    │  │  └─────────┘  └─────────┘  └─────────┘    │  │
                    │  │                                           │  │
                    │  │  Topics:                                  │  │
                    │  │  - binance-btcusdc-trades (3 partitions)  │  │
                    │  │  - trading-events (3 partitions)          │  │
                    │  │  - analytics-results (1 partition)        │  │
                    │  └───────────────────────────────────────────┘  │
                    │                      ▲                          │
                    │                      │                          │
                    │  ┌───────────────────┴───────────────────────┐  │
                    │  │          Binance Ingester                 │  │
                    │  │  (WebSocket → Kafka Producer)             │  │
                    │  └───────────────────────────────────────────┘  │
                    └─────────────────────────────────────────────────┘
```

## Security

### Authelia Protection

Protected services require 2FA authentication via Authelia:
- Grafana
- AKHQ
- Prometheus
- Argo CD

Public services (no auth required):
- Frontend (cv.sebastien.sh)
- API (api.sebastien.sh)
- Auth Portal (auth.sebastien.sh)

### Access Control Policy

```yaml
access_control:
  default_policy: deny
  rules:
    - domain: cv.sebastien.sh
      policy: bypass
    - domain: api.sebastien.sh
      policy: bypass
    - domain: grafana.sebastien.sh
      policy: two_factor
    - domain: akhq.sebastien.sh
      policy: two_factor
```

### Secrets Management

Current implementation uses base64-encoded secrets in ConfigMaps.

For production, consider:
- **Sealed Secrets**: Encrypt secrets in Git
- **External Secrets Operator**: Sync from Vault/AWS SM
- **HashiCorp Vault**: Dynamic secrets

## Resource Allocation

| Component | Requests | Limits |
|-----------|----------|--------|
| Frontend | 128Mi / 100m | 256Mi / 500m |
| Trading Simulator | 768Mi / 500m | 1.5Gi / 1.5 |
| Binance Ingester | 512Mi / 250m | 1Gi / 1 |
| PostgreSQL | 512Mi / 250m | 2Gi / 1 |
| Kafka Broker | 1Gi / 500m | 2Gi / 1 |
| Kafka Controller | 512Mi / 250m | 1Gi / 500m |
| Prometheus | 1Gi / 500m | 2Gi / 1 |
| Grafana | 256Mi / 100m | 512Mi / 500m |
| AKHQ | 512Mi / 250m | 1Gi / 1 |
| Authelia | 128Mi / 100m | 256Mi / 250m |

## Storage Requirements

| PVC | Size | Storage Class |
|-----|------|---------------|
| postgres-pvc | 20Gi | local-path |
| prometheus-data-pvc | 50Gi | local-path |
| grafana-data-pvc | 10Gi | local-path |
| authelia-pvc | 1Gi | local-path |
| kafka-broker-* | 30Gi x 3 | local-path |
| kafka-controller-* | 30Gi x 3 | local-path |

**Total: ~270Gi**

## Helm Charts

### Chart Dependencies

```
infrastructure (Wave 0)
    └── No dependencies

kafka (Wave 1)
    └── Requires: Strimzi Operator pre-installed

cv-site (Wave 2)
    └── Requires: infrastructure, kafka

monitoring (Wave 3)
    └── Requires: infrastructure, kafka, cv-site

ingress (Wave 4)
    └── Requires: All above
```

### Values Override Strategy

Base values are in `charts/<name>/values.yaml`.
Environment overrides are in `environments/<env>/<name>-values.yaml`.

Argo CD merges them:
```yaml
source:
  path: charts/cv-site
  helm:
    valueFiles:
      - ../../environments/production/cv-site-values.yaml
```
