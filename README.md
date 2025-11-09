# Karpenter + EKS Terraform Demo

This repository contains a two-stack Terraform configuration that deploys an Amazon EKS cluster (in `terraform/infra`) and installs the [Karpenter](https://karpenter.sh/) autoscaler plus demo workloads (in `terraform/karpenter`).

The steps below assume you have Terraform, kubectl, and AWS CLI access (with SSO or long-lived credentials) to the target AWS account.

## Prerequisites

1. **Authenticate to AWS**  
   Use `aws sso login` or the mechanism your organization requires before running Terraform or kubectl commands.

2. **Enable required AWS service-linked role**  
   Karpenter needs the EC2 Spot service-linked role to exist. Most organizations have this role pre-created, but if not, run this one-time command (requires IAM permissions):

   ```bash
   aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
   ```

   If the role already exists you'll see:
   ```
   An error occurred (InvalidInput) ... Service role name AWSServiceRoleForEC2Spot has been taken in this account...
   ```
   which is expected and means the role is ready for use.

## Deploy order

1. **Provision the EKS infrastructure**

   ```bash
   terraform -chdir=terraform/infra init
   terraform -chdir=terraform/infra apply
   ```

   This stack creates:
   - VPC, subnets, routing, NAT
   - EKS cluster and controller node group
   - IAM roles/policies for Karpenter, including controller permissions for Spot service-linked role creation
   - Outputs consumed by the demo stack (cluster name/endpoint, instance profile, security groups, etc.)

2. **Install Karpenter, NodeClass/NodePools, demo workloads**

   ```bash
   terraform -chdir=terraform/karpenter init
   terraform -chdir=terraform/karpenter apply
   ```

   This stack:
   - Deploys the official Karpenter Helm chart (v1.8.2)
   - Creates an `EC2NodeClass` referencing AL2023 AMIs (x86/arm) and tagged subnets/SGs
   - Creates multiple `NodePool` definitions (amd64/arm64 × on-demand/spot)
   - Installs optional demo `Deployment`s to trigger autoscaling

3. **Restart Karpenter controller after each Terraform change**

   Anytime the Helm values or IAM permissions change, restart the deployment:

   ```bash
   kubectl -n kube-system rollout restart deploy/karpenter
   kubectl -n kube-system rollout status deploy/karpenter
   ```

## Monitoring & verification

- **Logs**
  ```bash
  kubectl -n kube-system logs deploy/karpenter --since=5m --tail=200
  ```
  Expect to see `found provisionable pod(s)` followed by `created nodeclaim` / `launched nodeclaim`.

- **Pods & nodes**
  ```bash
  kubectl get pods -n default -l app=demo-amd64-spot
  kubectl get nodes -l karpenter.sh/managed-by=karpenter
  ```

## Troubleshooting tips

- **`AuthFailure.ServiceLinkedRoleCreationNotPermitted`**  
  The spot service-linked role was missing; create it manually with the command mentioned above or ensure the controller IAM policy includes `iam:CreateServiceLinkedRole` (already present in this repo).

- **`SecurityGroupSelector did not match` / `SubnetSelector did not match`**  
  Confirm the VPC subnets and security groups are tagged with `karpenter.sh/discovery=<cluster>`. The infra stack handles this automatically.

- **`No AMIs found`**  
  Verify the `EC2NodeClass` is using a valid EKS version/AMI family; for 1.33+ clusters, AL2023 AMIs via SSM are required.

## Cleanup

Destroy both stacks (demo first, then infra) to tear everything down:

```bash
terraform -chdir=terraform/karpenter destroy
terraform -chdir=terraform/infra destroy
```

Make sure you delete any EC2 instances or service-linked roles you created manually if they are no longer required.

# EKS + Karpenter (POC)

This POC provisions a new VPC and an EKS cluster on AWS with Karpenter enabled to schedule workloads on both amd64 (x86) and arm64 (Graviton) Spot and On-Demand nodes.

- Stack: `terraform/infra` (network + EKS + Karpenter controller) and `terraform/karpenter` (Karpenter CRDs/NodePools + optional demo workloads)
- Naming is driven by the `name` variable (see `terraform/infra/terraform.tfvars`)

## Prerequisites
- Terraform >= 1.5
- AWS credentials configured (env vars or AWS profile)
- kubectl >= 1.27

## Quick start
1. Deploy AWS foundation
   ```
   cd terraform/infra
   terraform init
   terraform apply
   ```

2. Configure kubeconfig (run from `terraform/infra`)
   ````
   aws eks update-kubeconfig \
     --name "$(terraform output -raw cluster_name)" \
     --region "$(terraform output -raw aws_region)"
   ````

3. Deploy Kubernetes CRDs, Provisioners, and optional workloads
   ```
   cd ../karpenter
   terraform init
   terraform apply
   ```

## Verify
- Karpenter controller: `kubectl -n karpenter get pods`
- Karpenter CRDs: `kubectl get crds | grep -i karpenter`
- Core add-ons: `kubectl get pods -n kube-system | egrep 'coredns|vpc-cni|ebs-csi'`

## Schedule example workloads
Four NodePools are created:
- `amd64-spot`, `amd64-ondemand`, `arm64-spot`, `arm64-ondemand`

You can target capacity either by capacity-type or by NodePool name.

Customize pools (arch, capacity type, instance types, limits) by editing the `nodepools` map in `terraform/karpenter/terraform.tfvars`. Defaults favor the lowest-cost burstable families (`t3a*/t3*` for amd64, `t4g*` for arm64).

The sample nginx deployments are gated by `enable_demo_workloads` in `terraform/karpenter/terraform.tfvars`; set it to `true` to install them automatically.

### A) Node selector by `capacity-type` and `arch` (recommended)

amd64 on Spot:
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-amd64-spot
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-amd64-spot
  template:
    metadata:
      labels:
        app: demo-amd64-spot
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
        karpenter.sh/capacity-type: spot
      containers:
      - name: web
        image: public.ecr.aws/docker/library/nginx:stable
```

arm64 on On-Demand:
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-arm64-ondemand
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-arm64-ondemand
  template:
    metadata:
      labels:
        app: demo-arm64-ondemand
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        karpenter.sh/capacity-type: on-demand
      containers:
      - name: web
        image: public.ecr.aws/docker/library/nginx:stable
```

### B) Node selector by NodePool name
```
spec:
  nodeSelector:
    karpenter.sh/nodepool: amd64-spot
```

## Observe provisioning
```
kubectl get nodes -L karpenter.sh/nodepool -L kubernetes.io/arch -L karpenter.sh/capacity-type -o wide
kubectl get pods -o wide
```

## Notes
- This is a POC: simplified IAM, networking, and security. Defaults aim for clarity over hardening.
- Instance type lists and network overrides can be adjusted in `terraform/infra/terraform.tfvars` and `terraform/karpenter/terraform.tfvars`.
- For additional stability later, pin add-on versions instead of using `most_recent = true`.

## Architecture Reference

Detailed cloud architecture guidance for Innovate Inc. (accounts, networking, Kubernetes design, and database strategy) lives in [`docs/architecture.md`](docs/architecture.md).
