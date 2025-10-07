# Zama Jobs API - Architecture Submission

## Overview

This repository contains a comprehensive architectural design for the fictional "Zama Jobs API" - a platform that enables developers to submit long-running, asynchronous jobs via a REST API with blockchain-based finality confirmation.

## 📁 Repository Structure

```
zama-jobs-api/
├── API-ARCHITECTURE.md    # Main deliverable - Complete architecture document
├── README.md              # This file - Submission overview
├── designs/               # Architecture diagrams
│   └── hld5.png          # High-level architecture diagram
├── examples/             # Optional implementation samples (incomplete)
│   ├── job-api/          # Rust-based gRPC job handler service
│   └── job-handler/      # Go-based job processor
└── kubernetes/           # Optional K8s deployment manifests (incomplete)
    └── *.yaml            # Service definitions and deployments
```

## 🎯 Challenge Objective

The challenge required demonstrating strong architectural decision-making across:
- **API Governance**: REST API design with versioning, error handling, and idempotency
- **Security-by-default**: Authentication, authorization, and least-privilege access
- **Reliability Thinking**: SLOs, error budgets, and resilience patterns
- **Usage Metering**: Event capture for consumption-based billing

## 📋 Main Deliverable: API-ARCHITECTURE.md

The `API-ARCHITECTURE.md` file is the primary submission containing a complete architectural design that addresses all requirements:

### A. Architecture Decision Pack (ADRs)

**Section 2: Architecture Decision Pack**
- **ADR-001: API Governance** - REST API with path versioning, RFC 7807 error model, UUID-based idempotency
- **ADR-002: Authentication** - OAuth 2.0 with JWT tokens (15-min expiry)
- **ADR-003: Rate Limiting** - Two-tier strategy with token bucket algorithm
- **ADR-004: Blockchain Integration** - Relayer pattern with EIP-712 signatures
- **ADR-005: Metering & Billing** - Event-driven capture via NATS JetStream

**Key Design Decisions:**
- **REST over GraphQL/gRPC** for accessibility
- **Path-based versioning** (`/v1/`) for clarity
- **Compute Units (CUs)** as unified billing metric
- **Batch blockchain confirmations** for 73% gas savings

### B. System Interface & Logic Design

**Section 3: System Interface & Logic**
- **3.1 API Specification** - Complete OpenAPI 3.1 spec with all endpoints
- **3.2 API Handler Logic** - 10-step processing flow with Rust implementation
- **3.3 gRPC Interface** - Internal service communication protocol
- **3.6 Smart Contract** - Minimal on-chain interface with replay protection
- **3.7 Technology Rationale** - Justification for each technology choice

**Key Implementation Details:**
- **Idempotency** via Redis with 24-hour TTL
- **Job lifecycle** managed through PostgreSQL + NATS
- **Replay protection** using unique jobId generation
- **Access control** via OpenZeppelin role-based contracts

### C. Reliability & Security

**Section 4: Reliability & Security**
- **4.1 Reliability** - 99.9% availability SLO, p95 < 300ms latency
- **4.2 Security** - Defense-in-depth with network policies

**Section 5: Operational Excellence**
- **5.3 Circuit Breakers** - Fault isolation patterns
- **5.4 Observability** - Prometheus, Grafana, Loki stack
- **5.5 Testing Strategy** - Contract, load, and chaos testing
- **5.6 Compliance** - GDPR, SOC2, ISO 27001 readiness

### Additional Sections (Beyond Requirements)

**Section 6: Cost Analysis & Optimization**
- Infrastructure cost breakdown (~$6,500/month)
- Optimization strategies (spot instances, request coalescing)
- Tiered storage for 60% cost reduction

## 💻 Optional Implementation Samples

The `examples/` and `kubernetes/` folders contain **incomplete** implementation artifacts that support the architectural design:

### examples/job-api/ (Rust gRPC Service)
- Basic gRPC service structure
- Proto definitions for job management
- Demonstrates the chosen tech stack
- **Status**: Skeleton implementation only

### examples/job-handler/ (Go Job Processor)
- NATS message consumer
- Job processing logic outline
- Showcases Go concurrency patterns
- **Status**: Basic structure, not production-ready

### kubernetes/ (Deployment Manifests)
- Service definitions
- Basic deployment configurations
- Network policies
- **Status**: Foundational manifests, requires customization

**Note**: These implementations are intentionally minimal, serving as supporting evidence for the architectural decisions rather than production-ready code.

## 🏗️ Architecture Highlights

### Technology Stack
- **Ingress**: Cilium (eBPF-based networking)
- **API Gateway**: Kong (with 100+ plugins)
- **IAM**: Keycloak (OAuth 2.0/OIDC)
- **Job Handler**: Rust (memory safety, predictable performance)
- **Job Processor**: Go (excellent concurrency)
- **Message Broker**: NATS.io (lightweight, JetStream persistence)
- **Blockchain**: COTI Network (EVM-compatible with privacy features)
- **Orchestration**: Kubernetes

### Key Innovations

1. **Two-Tier Rate Limiting**
   - Layer 1: Kong (coarse-grained RPS checks, <10ms)
   - Layer 2: Job Handler (fine-grained CU calculation, <50ms)

2. **Compute Unit Model**
   - Unified billing metric (1 CU = 1 KB payload)
   - Soft buffers with optional overage billing
   - Transparent cost allocation

3. **Gas Optimization**
   - Batch confirmations reduce costs by 73%
   - Configurable confirmation intervals
   - Merkle tree for proof aggregation

4. **Multi-Channel Notifications**
   - WebSocket for real-time updates
   - Webhooks with HMAC signatures
   - Eliminates expensive polling

## 🎨 Design Philosophy

The architecture prioritizes:

1. **Security-by-Default**: Zero-trust networking, defense-in-depth, least privilege
2. **Developer Experience**: Clear APIs, comprehensive docs, predictable errors
3. **Operational Excellence**: Observable, resilient, cost-optimized
4. **Scalability**: Horizontal scaling, stateless components, event-driven
5. **Compliance Ready**: Audit logging, data classification, GDPR compliance

## 🎯 Performance Targets

- **Availability**: 99.9% uptime SLO
- **Latency**: p95 < 300ms, p99 < 500ms
- **Throughput**: 1,000 RPS sustained, 5,000 RPS burst
- **Job Success Rate**: 95% completion rate
- **Cost Efficiency**: $0.561 per job (including blockchain)

## 🚀 Getting Started

This is a design-focused submission. To explore the architecture:

1. **Read the main document**: Start with `API-ARCHITECTURE.md`
2. **Review the diagrams**: Check `designs/hld5.png` for visual overview
3. **Explore samples**: Browse `examples/` for implementation hints
4. **Check deployments**: See `kubernetes/` for infrastructure setup

## ✅ Evaluation Criteria Addressed

| Requirement | Location in Submission |
|------------|----------------------|
| API Governance | Section 2.3, Section 3.1 (OpenAPI spec) |
| Platform Policies | Section 2.4-2.5 (Auth, Rate Limiting) |
| Metering Logic | Section 2.7, Section 3.2 |
| On-Chain Interface | Section 2.6, Section 3.6 |
| API Handler Logic | Section 3.2, Section 3.4 |
| Reliability | Section 4.1, Section 5.1-5.4 |
| Security | Section 4.2, Section 5.6 |
| Cost Analysis | Section 6 (bonus) |
| Testing Strategy | Section 5.5 (bonus) |

## 🌟 Key Differentiators

1. **Comprehensive ADRs** with clear trade-off analysis
2. **Production-ready design** beyond basic requirements
3. **Cost-conscious architecture** with optimization strategies
4. **Real implementation samples** in Rust and Go
5. **Complete OpenAPI specification** with 500+ lines
6. **Operational excellence** with chaos engineering and observability
7. **Technology rationale** for all stack choices
