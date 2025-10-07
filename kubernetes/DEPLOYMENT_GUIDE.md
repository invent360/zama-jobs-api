# Zama Jobs API - Complete Kubernetes Deployment Guide

## Quick Start (5 minutes)

```bash
# 1. Ensure Kubernetes is running
kubectl cluster-info

# 2. Deploy the complete stack
cd kubernetes/
./deploy.sh

# 3. Start port forwarding
./port-forward.sh

# 4. Test the deployment
./test.sh
```

## Architecture Overview

This deployment creates a comprehensive cloud-native stack:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Internet                                 │
└─────────────────────┬───────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────────┐
│  Cilium Gateway (eBPF) - Infrastructure Layer                  │
│  • High-performance packet processing                          │
│  • L4/L7 load balancing                                        │
│  • Network policies & security                                 │
│  • Service mesh capabilities                                   │
└─────────────────────┬───────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────────┐
│  Kong Gateway - API Management Layer                           │
│  • API versioning & governance                                 │
│  • Authentication via Keycloak OIDC                            │
│  • Per-tenant rate limiting                                    │
│  • Usage metering & billing                                    │
│  • Request/response transformation                             │
└─────────────────────┬───────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────────┐
│  Keycloak - Identity & Access Management                       │
│  • OAuth2/OIDC provider                                        │
│  • Multi-tenant support                                        │
│  • User federation                                             │
│  • RBAC/ABAC policies                                          │
└─────────────────────┬───────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────────┐
│  NATS.io - Message Broker                                      │
│  • High-performance messaging                                  │
│  • JetStream for persistence                                   │
│  • Pub/sub and streaming                                       │
│  • Cluster mode for HA                                         │
└─────────────────────┬───────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────────┐
│  Zama Jobs Microservices                                       │
│  • Job Submission API                                          │
│  • Job Processing Engine                                       │
│  • Blockchain Confirmation Service                             │
│  • Metering & Billing Service                                  │
└─────────────────────┬───────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────────┐
│  Data Layer                                                     │
│  • PostgreSQL (Event Store & State)                            │
│  • Redis (Caching & Rate Limiting)                             │
│  • MinIO (S3-compatible Object Storage)                        │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Cilium (Infrastructure Layer)
- **eBPF-based networking** for high performance
- **Gateway API support** for modern ingress
- **Network policies** for zero-trust security
- **Service mesh** capabilities
- **Hubble UI** for observability

### 2. Kong Gateway (API Management)
- **API versioning** (`/v1/jobs`, `/v2/jobs`)
- **Authentication** via Keycloak OIDC
- **Rate limiting** per tenant
- **Usage metering** for billing
- **Plugin ecosystem** for extensibility

### 3. Keycloak (Identity Management)
- **OAuth2/OIDC** provider
- **Multi-tenant** support
- **Admin UI** at `localhost:8080`
- **Default credentials**: admin/admin123

### 4. NATS.io (Message Broker)
- **High-performance** messaging
- **JetStream** for persistence
- **Cluster mode** with 3 replicas
- **Monitoring** at `localhost:8222`

### 5. Backend Services
- **Job Submission** - REST API for job management
- **Job Processing** - Async job execution
- **Blockchain Service** - On-chain confirmation
- **Metering Service** - Usage tracking

### 6. Data Layer
- **PostgreSQL** - Event store and state management
- **Redis** - Caching and rate limiting
- **MinIO** - Object storage for job files

## Deployment Steps

### Prerequisites
- Kubernetes cluster (Minikube or Docker Desktop)
- kubectl CLI
- Helm 3.x
- 8GB+ RAM allocated to Kubernetes

### Step 1: Start Kubernetes

For **Minikube**:
```bash
minikube start --memory=8192 --cpus=4
minikube addons enable ingress
```

For **Docker Desktop**:
- Enable Kubernetes in Docker Desktop settings
- Allocate at least 8GB RAM

### Step 2: Deploy the Stack
```bash
cd kubernetes/
./deploy.sh
```

This script will:
1. Create namespaces
2. Install Cilium CNI with Gateway API
3. Deploy storage components (PostgreSQL, Redis, MinIO)
4. Deploy NATS message broker
5. Deploy Keycloak IAM
6. Deploy Kong Gateway
7. Deploy Zama microservices
8. Apply network policies
9. Deploy monitoring stack

### Step 3: Access Services
```bash
./port-forward.sh
```

Services will be available at:
- **Kong Gateway**: http://localhost:8000
- **Kong Admin**: http://localhost:8001
- **Keycloak**: http://localhost:8080 (admin/admin123)
- **NATS**: http://localhost:8222
- **Grafana**: http://localhost:3000 (admin/admin)
- **MinIO**: http://localhost:9001 (minioadmin/minioadmin123)

### Step 4: Test the Deployment
```bash
./test.sh
```

## Configuration

### Environment Variables
Create a `.env` file for customization:

```bash
# Cluster Configuration
CLUSTER_TYPE=minikube
NAMESPACE=zama-system

# Versions
CILIUM_VERSION=1.18.2
KONG_VERSION=3.4
KEYCLOAK_VERSION=22.0.1
NATS_VERSION=2.10.0

# Credentials
KEYCLOAK_ADMIN_PASSWORD=admin123
KONG_ADMIN_TOKEN=supersecret
```

### Scaling Services

Scale individual components:
```bash
# Scale job processing workers
kubectl scale deployment job-processing-service -n zama-system --replicas=5

# Scale Kong for high traffic
kubectl scale deployment kong-kong -n kong --replicas=3

# Scale NATS cluster
kubectl scale statefulset nats -n messaging --replicas=5
```

## Monitoring & Observability

### Grafana Dashboards
Access Grafana at http://localhost:3000:
- **Zama Overview**: Overall system metrics
- **Cilium Network**: eBPF and network metrics
- **Kong API Gateway**: API performance metrics

### Hubble UI (Cilium)
Network flow visualization:
```bash
cilium hubble ui
# Opens browser to http://localhost:12000
```

### Logs
View service logs:
```bash
# Kong logs
kubectl logs -n kong deployment/kong-kong -f

# Job processing logs
kubectl logs -n zama-system deployment/job-processing-service -f

# Keycloak logs
kubectl logs -n iam deployment/keycloak -f
```

## API Usage

### Authentication Flow
1. **Register** in Keycloak at http://localhost:8080
2. **Create API client** in Keycloak admin
3. **Get access token**:
```bash
curl -X POST http://localhost:8080/realms/zama/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=your-client-id" \
  -d "client_secret=your-client-secret"
```

### Submit Job
```bash
curl -X POST http://localhost:8000/v1/jobs \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Idempotency-Key: $(uuidgen)" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "fhe_computation",
    "params": {
      "circuit": "base64_encoded_circuit",
      "inputs": ["0x1234", "0x5678"]
    },
    "metadata": {
      "priority": "high"
    }
  }'
```

### Check Job Status
```bash
curl -H "Authorization: Bearer $ACCESS_TOKEN" \
  http://localhost:8000/v1/jobs/{job_id}/status
```

## Network Policies

The deployment includes comprehensive network policies:

- **Kong** can only access authorized services
- **Zama services** can only be reached through Kong
- **Storage** is isolated to authorized consumers
- **IAM** has restricted access patterns

View policies:
```bash
kubectl get ciliumnetworkpolicies --all-namespaces
```

## Troubleshooting

### Common Issues

**Cilium not ready**:
```bash
cilium status
cilium connectivity test
```

**Kong errors**:
```bash
kubectl logs -n kong deployment/kong-kong
curl http://localhost:8001/status
```

**Database connection issues**:
```bash
kubectl exec -it -n storage sts/postgres -- psql -U postgres -l
```

**NATS cluster issues**:
```bash
kubectl logs -n messaging sts/nats
curl http://localhost:8222/varz
```

### Resource Issues
If running out of resources:
```bash
# For Minikube
minikube stop
minikube start --memory=12288 --cpus=6

# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces
```

### Reset Deployment
```bash
./cleanup.sh
# Answer 'y' to delete everything
./deploy.sh
```

## Production Considerations

For production deployment:

1. **Use managed Kubernetes** (EKS, GKE, AKS)
2. **Configure persistent storage** with cloud providers
3. **Set up TLS certificates** for HTTPS
4. **Configure backup/restore** procedures
5. **Implement proper secret management**
6. **Set up auto-scaling** based on metrics
7. **Configure multi-region** deployment

### Production Scaling Guide

```bash
# High availability configuration
kubectl patch deployment kong-kong -n kong -p '{"spec":{"replicas":3}}'
kubectl patch statefulset postgres -n storage -p '{"spec":{"replicas":3}}'
kubectl patch deployment job-processing-service -n zama-system -p '{"spec":{"replicas":10}}'

# Resource limits for production
kubectl patch deployment job-submission-service -n zama-system -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "service",
          "resources": {
            "requests": {"cpu": "500m", "memory": "1Gi"},
            "limits": {"cpu": "2000m", "memory": "4Gi"}
          }
        }]
      }
    }
  }
}'
```

## Security

### Network Security
- All traffic encrypted in transit
- Network policies enforce zero-trust
- Service mesh with mTLS (optional)

### Application Security
- OAuth2/OIDC authentication
- JWT token validation
- Rate limiting per tenant
- Input validation

### Data Security
- Encryption at rest
- Database access controls
- Audit logging

## Performance Metrics

Expected performance on a 4-core, 8GB system:

| Metric | Target | Notes |
|--------|--------|-------|
| API Latency (p50) | < 50ms | Kong + backend |
| API Latency (p99) | < 200ms | Including auth |
| Throughput | 1000 RPS | Per Kong instance |
| Job Processing | < 5 min | Depends on job type |

## Support

For issues:
1. Check logs with `kubectl logs`
2. Review service status with `kubectl get pods`
3. Test connectivity with `./test.sh`
4. Check monitoring dashboards

## License

This deployment configuration is provided under Apache 2.0 license.