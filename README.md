# Project 2: Highly Available Auto-Scaling Web App on AWS

A secure, self-healing web application infrastructure on AWS — built manually first to understand every component, then fully rebuilt as Infrastructure as Code with Terraform.

## Architecture

- **VPC** (10.1.0.0/16) across 2 Availability Zones (us-east-2a, us-east-2b)
- **Public subnets**: host the ALB and EC2 instances
- **Private subnets**: host RDS — no internet route, no public access
- **Application Load Balancer**: single public entry point, distributes traffic across healthy instances
- **Auto Scaling Group**: min 2 / max 4 EC2 instances, self-healing across both AZs
- **RDS (MySQL)**: private, `publicly_accessible = false`, reachable only from EC2
- **IAM + SSM**: instance access via Session Manager — no SSH keys, no open port 22 anywhere

## Security Design

Three chained security groups, each trusting only the layer before it:

Internet → ALB (port 80) → EC2 (port 80, ALB-only) → RDS (port 3306, EC2-only)

No layer is directly reachable except the ALB. RDS has zero internet exposure at the network level (private subnet) and the security-group level (EC2-only).

## A real bug I hit and fixed

New Auto Scaling Group instances kept failing ALB health checks (502 Bad Gateway). Root cause: the Launch Template wasn't assigning public IPs, so new instances had no internet access — meaning the `yum install nginx` step in the user-data script silently failed. Fixed in the console, then made sure the Terraform version (`associate_public_ip_address = true`) got it right from the start.

## Infrastructure as Code

Everything above was rebuilt 100% in Terraform — 22 resources, one `terraform apply`, fully reproducible:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

**Note:** `terraform.tfvars` (containing the RDS password) is intentionally excluded via `.gitignore`. To run this yourself, create your own `terraform.tfvars`:
```hcl
db_password = "YourOwnPassword"
```

## Tech Stack

AWS VPC · EC2 · Auto Scaling · Application Load Balancer · RDS (MySQL) · IAM · Systems Manager (SSM) · Terraform

Please find the screenshots below
1. VPC overview Architecture (Image 1):
 <img width="1535" height="784" alt="image" src="https://github.com/user-attachments/assets/77621323-b9ef-40c4-9bbc-4097b5d65362" />
2. Security Groups list (Image 2)
  <img width="1568" height="417" alt="image" src="https://github.com/user-attachments/assets/dfe4815b-3ba9-4532-83f0-af2c6a95bb55" />
3.  Target Group "Healthy" status (Image 3)
 <img width="1568" height="417" alt="image" src="https://github.com/user-attachments/assets/dfe4815b-3ba9-4532-83f0-af2c6a95bb55" />
4. terraform apply success output (Image 4)
  <img width="1568" height="506" alt="image" src="https://github.com/user-attachments/assets/356b1b6c-f942-43b9-98c9-60b3acb2f294" />



