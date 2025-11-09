# Innovate Inc. Cloud Architecture

## Overview

Innovate Inc. is building a Python/Flask REST API paired with a React SPA. The company expects to start with a few hundred daily users and scale to millions, while handling sensitive user data and releasing continuously. The following design leverages AWS managed services to provide a secure, scalable, and cost-aware platform based on Amazon Elastic Kubernetes Service (EKS).

```mermaid
flowchart TB
    subgraph org[AWS Organizations]
        subgraph prod[Prod Account]
            subgraph prod_pub[Public Subnets]
                alb[Application Load Balancer]
            end
            subgraph prod_priv[Private Subnets]
                eks_prod[EKS Cluster]
            end
            subgraph prod_db[Isolated Subnets]
                rds_prod[(Amazon RDS\nPostgreSQL)]
            end
        end
        subgraph stage[Stage Account]
            eks_stage[EKS Cluster]
            rds_stage[(RDS Postgres)]
        end
        subgraph dev[Dev Account]
            eks_dev[EKS Cluster]
        end
        subgraph shared[Shared Services Account]
            ci_cd[CI/CD Tooling]
            ecr[Artifact Registry (ECR)]
        end
        subgraph sec[Security Account]
            guardduty[GuardDuty / SecurityHub]
            logging[Central Logging]
        end
    end
    developers[Developers] -->|git push| ci_cd
    ci_cd -->|build & scan| ecr
    ecr -->|deploy manifests| eks_prod
    users[End Users] --> alb --> eks_prod --> rds_prod
    eks_prod -. metrics/logs .-> logging
    eks_prod -. findings .-> guardduty
```

## Cloud Environment Structure

### Accounts
- **Shared Services account (Platform tooling)**
  - Houses centralized CI/CD tooling (e.g., AWS CodePipeline/CodeBuild or GitHub Actions runners), ECR repositories, developer tooling, and IAM Identity Center integrations.
  - Provides baseline IAM roles and standard AMIs/container base images.

- **Security account**
  - Centralizes AWS Security Hub, GuardDuty, AWS Config aggregators, and SIEM integrations.
  - Collects centralized logging (CloudTrail, VPC Flow Logs, ALB access logs) and manages incident response tooling.

- **Dev account**
  - Lightweight environment used by engineers for rapid prototyping and integration testing.
  - Single-node-group EKS cluster, smaller RDS instances, and relaxed auto-scaling policies to reduce cost.

- **Stage account**
  - Mirrors production on a smaller scale for pre-production verification and performance testing.
  - Uses the same IaC stack (Terraform) with smaller node pools and database instance classes.

- **Production account**
  - Runs the production VPC, EKS cluster, and database. Isolation limits blast radius and simplifies billing.

Accounts are managed under AWS Organizations with Service Control Policies (SCPs). Each account integrates back to the shared-services account for centralized logging (CloudTrail, CloudWatch Logs, S3) and cost governance.

## Network Design

### VPC Layout (per environment)
- **CIDR:** 10.10.0.0/16 (dev), 10.20.0.0/16 (stage), 10.30.0.0/16 (prod) to avoid overlap.
- **Subnets:** Three availability zones, each with:
  - Public subnet (ALB, NAT gateways).
  - Private subnet (Kubernetes worker nodes, internal services).
  - Isolated subnet (databases, no direct route to Internet).
- **Routing:**
  - Public subnets route to the Internet Gateway.
  - Private subnets route through managed NAT gateways (one per AZ in prod for HA; single gateway in staging for cost savings).
  - Isolated subnets only route within the VPC (no NAT or IGW).

### Network Security
- AWS Network Firewall or security groups + NACLs control ingress/egress.
- ALB terminates TLS using AWS Certificate Manager (ACM) certificates.
- EKS nodes and control-plane accessible only via AWS PrivateLink endpoints and secured security groups.
- VPC flow logs and GuardDuty are enabled for visibility.
- AWS WAF attaches to ALB for Layer-7 threat mitigation.

## Compute Platform

### Kubernetes (Amazon EKS)
- **Cluster footprint:** One EKS cluster per environment (dev, stage, prod). Clusters are created via Terraform modules and upgraded regularly (v1 minor releases) using managed add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI).
- **Namespace layout:** Logical isolation with namespaces for `frontend`, `backend`, `data`, `platform`, and `observability`. Each namespace has LimitRanges and ResourceQuotas to protect cluster capacity.
- **Node groups & capacity strategy:**
  - Managed node groups split by architecture (amd64/arm64) and purchasing model (On-Demand for critical workloads, Spot for cost-optimized workloads). Start with t3a/t4g families; scale up to m6i/c7g as load grows.
  - Karpenter provides just-in-time node provisioning with consolidation policies to reduce waste. Horizontal Pod Autoscaler (HPA) and Kubernetes Event-driven Autoscaler (KEDA) back workload scaling.
  - Cluster Autoscaler remains enabled for managed node groups used as fallback capacity.
- **Platform add-ons:**
  - Gateway: AWS Load Balancer Controller to provision ALBs/NLBs, integrated with external-dns for Route53 records.
  - Service Mesh (optional future): AWS App Mesh/Istio if zero-trust requirements tighten.
  - Ingress: ALB backed by WAF, TLS termination via ACM.
  - Monitoring: CloudWatch Container Insights + OpenTelemetry (Prometheus/Grafana).
- **Security controls:**
  - Pod Security Admission in restricted mode, reinforced with Gatekeeper policies (OPA) for image provenance, privileged pods, and network policies.
  - IRSA for every workload that touches AWS APIs; no node instance profiles exposed to applications.
  - Calico (or Cilium) network policies to segment frontend/backend/data namespaces.
- **Deployment patterns:**
  - Rolling updates by default; Argo Rollouts enabled for blue/green or canary when new features carry higher risk.
  - Maintenance windows defined for cluster upgrades and node AMI refreshes; surge rolling updates keep API available.

### Containerization & Delivery
- **Image build pipeline:**
  1. CI (GitHub Actions or CodeBuild) lints, tests, and builds Flask + React images using multi-stage Dockerfiles.
  2. Supply-chain security: SBOM generation (Syft), vulnerability scanning (Trivy), and signing (Cosign) before push.
  3. Immutable images pushed to Amazon ECR (shared services account) and promoted across environments via tag promotion (e.g., `staging-<sha>` → `prod-<sha>`).
- **Manifest management:**
  - Helm charts kept in a dedicated repo; values files per environment stored in Git.
  - GitOps via Argo CD watches the Git repo and reconciles desired state into each cluster. Changes are peer-reviewed in Git before promotion.
- **Runtime policies:**
  - Admission controllers enforce image signatures and prevent drift from Git.
  - Sidecar containers (Envoy/OPA) injected via mutating webhooks when advanced policies are required.

## Database

### Service Choice
- **Amazon RDS for PostgreSQL** (Multi-AZ) for managed patching, backups, and high availability.
- For staging, use a smaller instance with optionally Multi-AZ disabled; for production, Multi-AZ enabled with read replicas if needed.

### Backups & DR
- Automated snapshots retained for 30 days; manual snapshots taken before major releases.
- Point-in-time recovery enabled.
- Cross-region snapshot replication for disaster recovery.
- Secrets stored in AWS Secrets Manager and injected into pods via IRSA.

## Security & Compliance
- Use IAM Identity Center (SSO) with least-privilege roles for developers, operators, and auditors.
- Enable AWS Organizations SCPs to restrict root actions and enforce baseline controls.
- Encrypt data at rest (EBS volumes, RDS, S3) using AWS KMS.
- Enable ALB access logs and ship to centralized S3 bucket with retention policies.
- Use AWS Config, GuardDuty, and Security Hub for continuous compliance.
- Apply CIS Benchmarks to EKS via AWS EKS Best Practices or third-party scanners (Kube-bench, Kubesec).
- Implement pod-level security with Network Policies (Calico/Cilium) to enforce segmentation.

## Observability
- Amazon CloudWatch Container Insights + Prometheus/Grafana stack (AMP/AMG) for metrics.
- Fluent Bit/Vector DaemonSets to ship logs to CloudWatch Logs/S3/ELK.
- AWS X-Ray or OpenTelemetry collector for distributed tracing.
- Alerts via Amazon SNS / PagerDuty for SLO violations.

## CI/CD Workflow
1. Developers push changes to Git.
2. **Repository layout (hybrid model):**
   - `infra` repository: Terraform, Helm libraries, policy-as-code, and shared modules owned by the platform team.
   - `platform-config` repository: Argo CD manifests / Helm values per environment; holds image tags and environment config (sealed secrets, ConfigMaps).
   - Application repositories (`backend`, `frontend`, future services): Source code, Dockerfiles, unit tests, and service-specific CD logic.
   - Optional shared-library repo for Python/React utilities published to an internal package registry.
3. CI pipeline (GitHub Actions or CodeBuild) runs linters/tests, builds container images, scans artifacts, and pushes to ECR.
4. After a successful build, the pipeline updates the `platform-config` repo (via automated PR) with new immutable image tags; Argo CD reconciles the change into the target cluster.
5. Progressive delivery uses rolling updates by default, with optional canary or blue/green strategies (Argo Rollouts) for high-risk releases.
6. On failure, automatic rollback or manual intervention can be triggered through Git revert/Argo Rollouts/Kubernetes deployment history.

## Cost Management
- Use AWS Budgets and Cost Explorer to monitor spend.
- Use Compute Savings Plans or Reserved Instances for baseline On-Demand capacity once usage stabilizes.
- Spot instances for non-critical workloads; right-size node instance types periodically.
- Enable S3 Intelligent-Tiering for logs/long-term storage and set lifecycle policies.

## Operations & Governance
- All infrastructure defined in Terraform with workspaces per environment.
- Enforce policy-as-code (OPA/Conftest) during CI to catch misconfigurations.
- Incident response runbooks stored in version control; leverage AWS Chatbot for quick notifications.
- Regular game days to test failover, backup restores, and security incident response.

## Future Enhancements
- Explore multi-region disaster recovery via Amazon Aurora Global Database or read replicas.
- Add service mesh (AWS App Mesh/Istio) if east-west observability and policy control become a priority.
- Integrate with AWS Macie for data classification if storage of particularly sensitive data increases.

---

**Deliverables:** All Terraform code, Kubernetes manifests, and this architecture document live in a single Git repository. The Mermaid diagram above captures the high-level architecture; export to PNG/PDF using Mermaid CLI or VSCode extension if a static diagram is required.

## Future Discussion Topics

The following areas were out of scope for this document but are worth discussing during the interview:

- **AWS Control Tower adoption** – evaluate automated account vending and guardrails across dev/stage/prod, and how it would integrate with the proposed shared/securities accounts.
- **Multi-region strategy** – failover patterns, data replication, DNS traffic management, and disaster recovery options (pilot light, warm standby, or active-active) if Innovate Inc. expands beyond a single region.
- **Advanced traffic management** – API Gateway, WAN-friendly routing (Global Accelerator), or service mesh for zero-trust networking.
- **Data residency and compliance** – processes for audits, data classification (e.g., AWS Macie), and integration with third-party compliance tooling.
- **Cost optimization pipeline** – automated right-sizing, Spot orchestration, and budget alerting beyond baseline AWS Budgets.

