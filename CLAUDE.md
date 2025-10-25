# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Terraform-based infrastructure project for an algorithmic trading system on AWS. The system uses a **modular multi-environment architecture** supporting dev, QA, and production deployments.

### Project Structure
```
terraform-algo-trading/
├── modules/                    # Reusable Terraform modules
│   ├── alpaca_websocket/      # WebSocket data ingestion module
│   ├── trading_server/        # Trading server module
│   └── trading_server_shutdown/ # Automated shutdown module
├── environments/              # Environment-specific configurations
│   ├── dev/                  # Development environment
│   ├── qa/                   # QA environment
│   └── prod/                 # Production environment
├── shared/                   # Common variable definitions
├── mlflow_server/           # MLOps infrastructure (standalone)
├── gpu_instance/            # GPU instances (standalone)
└── gpu_instance_init/       # GPU AMI configuration (standalone)
```

### Core Components
- **modules/alpaca_websocket/**: WebSocket server for real-time data ingestion from Alpaca API
- **modules/trading_server/**: Auto-scaling EC2 instances running algorithmic trading models
- **modules/trading_server_shutdown/**: Lambda function for graceful daily shutdown
- **mlflow_server/**: MLOps infrastructure (EC2, RDS, S3, IAM) - standalone component
- **gpu_instance/**: GPU-enabled instances for model training - standalone component

### Multi-Environment Support
- **Development Environment**: `algo-model-deploy-dev` S3 bucket, manual-only Lambdas (no EventBridge) for experimental work
- **QA Environment**: `algo-model-deploy` S3 bucket, smaller instance types
- **Production Environment**: `algo-model-deploy-prod` S3 bucket, larger instance types
- **Independent State**: Each environment maintains separate Terraform state
- **Environment Promotion**: Test configurations in QA (after dev) before promoting to production

### Key Technologies
- **Terraform**: Infrastructure as Code with modular design
- **AWS Lambda**: Serverless automation (Python)
- **EC2**: Auto-provisioned instances based on S3 model artifacts
- **EventBridge**: Scheduled triggers for automation
- **SSM**: Remote command execution on EC2 instances

## Development Commands

### Environment-Specific Deployment
```bash
# Work in the dev environment when testing new module changes
cd environments/dev
terraform init
terraform plan
terraform apply

# Deploy to QA environment
cd environments/qa
terraform init
terraform plan
terraform apply

# Deploy to Production environment
cd environments/prod
terraform init
terraform plan
terraform apply

# Destroy environments
terraform destroy
```

### Development Workflow
```bash
# 1. Test new AMI or configuration in QA
cd environments/qa
# Update terraform.tfvars with new AMI version
terraform apply

# 2. After validation, promote to production
cd ../prod
# Update terraform.tfvars with tested configuration
terraform apply
```

### Module Development
```bash
# Test individual modules (for development)
cd modules/alpaca_websocket
terraform init
terraform plan -var="environment=dev" -var="bucket_name=test-bucket"
```

## Infrastructure Patterns

### Module Structure
Each module follows this standard pattern:
- `main.tf`: Core infrastructure resources
- `variables.tf`: Input parameters with type validation
- `outputs.tf`: Exported values for module consumers
- `lambda.tf`: Lambda function configuration (where applicable)
- `lambda_function.py`: Lambda function code
- `run.sh`: EC2 initialization scripts

### Dynamic Resource Provisioning
- **Trading servers auto-provision** based on S3 model artifacts in `models/` prefix
- **Pattern matching**: `models/<type>/<symbol>/<model>-outer_X_inner_Y`
- **One EC2 instance per model** with automatic configuration injection
- **Environment isolation** through naming conventions and separate S3 buckets

### Environment Configuration
- **Environment-specific variables**: Instance types, AMI versions, bucket names
- **Shared networking**: VPC/subnet configuration (update in `shared/common-variables.tf`)
- **IAM resource isolation**: All roles/policies include environment suffix

## Key Configuration Files

### Environment Configurations
- `environments/dev/terraform.tfvars`: Development defaults (no scheduler/shutdown)
- `environments/qa/terraform.tfvars`: QA-specific settings
- `environments/prod/terraform.tfvars`: Production-specific settings
- `shared/common-variables.tf`: Shared variable definitions and validation

### Deployment Scripts
- `modules/*/run.sh`: Environment-aware initialization scripts
- Scripts automatically configure environment-specific parameters

### Lambda Functions
- `modules/*/lambda_function.py`: Environment-aware automation functions
- All functions include environment tagging and filtering

## Deployment Workflow

1. **Model Artifact Deployment** (external process):
   - Dev: Upload to `algo-model-deploy-dev/models/`
   - QA: Upload to `algo-model-deploy/models/`
   - Prod: Upload to `algo-model-deploy-prod/models/`

2. **Infrastructure Deployment**:
   ```bash
   # Development smoke test
   cd environments/dev && terraform apply

   # QA Testing
   cd ../qa && terraform apply
   
   # Production Deployment  
   cd ../prod && terraform apply
   ```

3. **Environment Promotion**:
   - Iterate in dev (new AMIs/config) before promoting to QA
   - Copy working Dev settings into QA tfvars, validate
   - Copy validated QA settings into Prod tfvars before final deployment

## Important Notes

- **State Management**: Each environment maintains independent Terraform state
- **AMI Testing**: Always test new AMI versions in QA before production deployment
- **External Dependencies**: Integrates with `algo-modeling-v2` repository for model code
- **Automated Scaling**: EC2 instances auto-provision based on S3 model structure
- **Environment Isolation**: Complete separation between QA and production resources
