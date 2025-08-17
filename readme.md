# Infrastructure Documentation

## Overview

This document outlines the infrastructure decisions for a microservice designed to handle billions of records with sub-500ms response times. **The application is deployed on AWS (Amazon Web Services)**, leveraging managed services for optimal performance, scalability, and cost-efficiency. All architectural choices were made balancing performance requirements, AWS service capabilities, and operational complexity.

## AWS Cloud Architecture

### Why AWS?

We chose **AWS as our cloud provider** for several strategic reasons:
- **Managed Kubernetes (EKS)**: Reduces operational overhead while maintaining Kubernetes compatibility
- **Global Infrastructure**: 31 regions and 99 availability zones for low-latency access
- **Integrated Services**: Native integration between EKS, RDS, ElastiCache, and MSK
- **Cost Optimization**: Reserved Instances, Savings Plans, and Spot Instances options
- **Compliance**: SOC, PCI-DSS, HIPAA certifications meet our requirements
- **Team Expertise**: Existing team knowledge reduces learning curve

### AWS Services Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     AWS Cloud (us-east-1)               │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────┐        ┌──────────────────┐      │
│  │   CloudFront     │───────▶│   WAF            │      │
│  │   Global CDN     │        │   DDoS Protection│      │
│  └──────────────────┘        └──────────────────┘      │
│            │                                            │
│            ▼                                            │
│  ┌──────────────────┐        ┌──────────────────┐      │
│  │   Route 53       │───────▶│   ALB            │      │
│  │   DNS Service    │        │   Load Balancer  │      │
│  └──────────────────┘        └──────────────────┘      │
│            │                                            │
│            ▼                                            │
│  ┌──────────────────────────────────────────────┐      │
│  │            EKS Cluster (3 AZs)               │      │
│  │  ┌────────┐  ┌────────┐  ┌────────┐        │      │
│  │  │ Node 1 │  │ Node 2 │  │ Node 3 │        │      │
│  │  │  AZ-1a │  │  AZ-1b │  │  AZ-1c │        │      │
│  │  └────────┘  └────────┘  └────────┘        │      │
│  └──────────────────────────────────────────────┘      │
│            │                                            │
│            ▼                                            │
│  ┌──────────────────────────────────────────────┐      │
│  │           Data Services                      │      │
│  │  ┌─────────────┐  ┌──────────────┐         │      │
│  │  │ RDS Postgres│  │ ElastiCache  │         │      │
│  │  │ + Replicas  │  │ Redis Cluster│         │      │
│  │  └─────────────┘  └──────────────┘         │      │
│  │  ┌─────────────┐  ┌──────────────┐         │      │
│  │  │ MSK (Kafka) │  │ S3 Buckets   │         │      │
│  │  │ 3 Brokers   │  │ Backups/Logs │         │      │
│  │  └─────────────┘  └──────────────┘         │      │
│  └──────────────────────────────────────────────┘      │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Core AWS Services Used

### Compute & Container Services

**Amazon EKS (Elastic Kubernetes Service)**
- **Version**: 1.28
- **Node Groups**: 3x c5.2xlarge EC2 instances
- **Why EKS**: Managed control plane reduces operational overhead by 70%
- **Auto-scaling**: Cluster Autoscaler + Karpenter for efficient scaling
- **Cost**: ~$0.10/hour for control plane + EC2 costs

**Amazon ECR (Elastic Container Registry)**
- Stores Docker images with automatic vulnerability scanning
- Image immutability for production tags
- Lifecycle policies to manage storage costs

### Networking & Content Delivery

**Amazon CloudFront**
- Global CDN with 450+ edge locations
- Integrated AWS WAF for application security
- Origin Shield for additional caching layer
- ~$0.085/GB data transfer

**Amazon Route 53**
- DNS service with health checks
- Failover routing policies
- Latency-based routing for multi-region (future)

**AWS Application Load Balancer (ALB)**
- Layer 7 load balancing with path-based routing
- WebSocket support for real-time features
- Integration with AWS Certificate Manager for SSL

### Data Services

**Amazon RDS for PostgreSQL**
- **Instance**: db.r5.2xlarge (primary) + 2 read replicas
- **Storage**: 1TB GP3 SSD with 16,000 IOPS
- **Multi-AZ**: Automatic failover in <60 seconds
- **Backups**: Automated daily snapshots, 35-day retention
- **Cost**: ~$3,200/month with reserved instances

**Amazon ElastiCache for Redis**
- **Configuration**: 3-node cluster, cache.r6g.xlarge
- **Engine**: Redis 7.0 with cluster mode enabled
- **Automatic failover**: <30 seconds
- **Cost**: ~$450/month

**Amazon MSK (Managed Streaming for Kafka)**
- **Cluster**: 3x kafka.m5.large brokers
- **Storage**: 1TB per broker with auto-scaling
- **Version**: Apache Kafka 3.5
- **Cost**: ~$600/month

### Storage

**Amazon S3**
- **Buckets**:
  - `company-backups`: Database backups (S3 Standard-IA)
  - `company-logs`: Application logs (S3 Intelligent-Tiering)
  - `company-archives`: Old data (S3 Glacier)
- **Lifecycle Policies**: Automatic tier transitions
- **Cost**: ~$100/month

**Amazon EBS**
- **Type**: GP3 volumes for Kubernetes PVs
- **IOPS**: 16,000 IOPS for database volumes
- **Snapshots**: Daily automated snapshots

### Monitoring & Observability

**Amazon CloudWatch**
- Backup logging destination
- Custom metrics for business KPIs
- Alarms integrated with SNS

**AWS X-Ray** (Optional)
- Distributed tracing for troubleshooting
- Service map visualization
- Integration with EKS

### Security Services

**AWS IAM**
- Service accounts with IRSA (IAM Roles for Service Accounts)
- Fine-grained permissions per microservice
- MFA enforced for production access

**AWS Secrets Manager**
- Automatic secret rotation
- Integration with RDS for database credentials
- Encryption at rest with KMS

**AWS WAF**
- Rate limiting rules
- OWASP Top 10 protection
- Custom rules for application-specific threats

## AWS-Specific Configuration

### EKS Node Configuration

```yaml
# EKS Node Group Configuration
nodeGroups:
  - name: compute-optimized
    instanceTypes: 
      - c5.2xlarge
    minSize: 3
    maxSize: 10
    desiredCapacity: 3
    volumeSize: 100
    volumeType: gp3
    privateNetworking: true
    asgMetricsCollection:
      - granularity: 1Minute
    iam:
      withAddonPolicies:
        ebs: true
        efs: true
        albIngress: true
        cloudWatch: true
```

### Cost Optimization on AWS

| Service | On-Demand | With Reserved Instances | Savings |
|---------|-----------|------------------------|---------|
| EKS Nodes (c5.2xlarge) | $1,500/month | $900/month | 40% |
| RDS PostgreSQL | $5,400/month | $3,200/month | 41% |
| ElastiCache | $750/month | $450/month | 40% |
| **Total** | **$7,650/month** | **$4,550/month** | **40%** |

### AWS Cost Breakdown

- **Compute (EKS)**: ~$1,100/month
  - Control plane: $73/month
  - Worker nodes: $900/month (reserved)
  - Data transfer: $127/month
- **Database (RDS)**: ~$3,200/month
  - Primary instance: $1,600/month
  - Read replicas: $1,400/month
  - Backup storage: $200/month
- **Cache (ElastiCache)**: ~$450/month
- **Message Queue (MSK)**: ~$600/month
- **Storage (S3 + EBS)**: ~$150/month
- **Monitoring (CloudWatch)**: ~$200/month
- **Total**: ~$5,700/month

## Deployment Commands for AWS

```bash
# Configure AWS CLI
aws configure --profile production

# Create EKS cluster
eksctl create cluster \
  --name microservice-prod \
  --region us-east-1 \
  --nodes 3 \
  --node-type c5.2xlarge \
  --managed

# Update kubeconfig
aws eks update-kubeconfig --name microservice-prod --region us-east-1

# Deploy AWS Load Balancer Controller
helm install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system

# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier prod-postgres \
  --db-instance-class db.r5.2xlarge \
  --engine postgres \
  --engine-version 15.4 \
  --master-username apiuser \
  --allocated-storage 1000 \
  --storage-type gp3

# Create ElastiCache cluster
aws elasticache create-replication-group \
  --replication-group-id prod-redis \
  --replication-group-description "Production Redis" \
  --cache-node-type cache.r6g.xlarge \
  --engine redis \
  --num-cache-clusters 3

# Deploy application
kubectl apply -f kubernetes/prod/
```

## AWS Well-Architected Framework Alignment

Our architecture follows AWS Well-Architected Framework pillars:

1. **Operational Excellence**: CloudWatch monitoring, automated deployments
2. **Security**: IAM roles, encryption, network isolation
3. **Reliability**: Multi-AZ deployment, auto-scaling, health checks
4. **Performance Efficiency**: Right-sized instances, caching, CDN
5. **Cost Optimization**: Reserved instances, spot instances for dev
6. **Sustainability**: Efficient resource usage, auto-scaling

## Disaster Recovery on AWS

- **RTO (Recovery Time Objective)**: 15 minutes
- **RPO (Recovery Point Objective)**: 5 minutes
- **Backup Strategy**: Automated RDS snapshots to S3
- **Multi-Region DR**: Cold standby in us-west-2 (future)

## AWS-Specific Runbook

**Service Degradation?**
```bash
# Check EKS cluster health
kubectl get nodes
aws eks describe-cluster --name microservice-prod

# Check RDS status
aws rds describe-db-instances --db-instance-identifier prod-postgres

# Check ElastiCache
aws elasticache describe-replication-groups
```

**Scaling Issues?**
```bash
# Scale EKS nodes
eksctl scale nodegroup --cluster microservice-prod --name workers --nodes 5

# Scale RDS (vertical)
aws rds modify-db-instance \
  --db-instance-identifier prod-postgres \
  --db-instance-class db.r5.4xlarge \
  --apply-immediately
```

## Future AWS Enhancements

1. **Multi-Region Active-Active**: Using AWS Global Accelerator
2. **Serverless Components**: Lambda for event processing
3. **Aurora Serverless v2**: For automatic database scaling
4. **EKS Fargate**: For serverless Kubernetes pods
5. **AWS Outposts**: For hybrid cloud requirements
