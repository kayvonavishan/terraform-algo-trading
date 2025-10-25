# Agent Guide for terraform-algo-trading

This repository provisions and orchestrates an algorithmic trading stack on AWS using Terraform, EC2, and Lambda. It includes:

- Alpaca websocket ingest EC2 and Lambda to bootstrap ingest
- Per-model trading server EC2 fleet and Lambda to start/run them via SSM
- A scheduled shutdown Lambda
- Environment entrypoints for dev/qa/prod

These instructions are for AI/code agents working inside this repo. Follow them for structure, style, and safe changes.

## What’s Canonical

- Use `modules/` + `environments/{dev,qa,prod}` as the source of truth.
- The top-level stacks `alpaca_websocket/`, `trading_server/`, and `trading_server_shutdown/` are legacy examples/prototypes. Do not modify them unless explicitly requested; prefer module changes.
- Related infra (e.g., `mlflow_server/`, `gpu_instance*/`) is separate; keep changes isolated to the intended component.

## Layout

- `modules/alpaca_websocket` — EC2 + Lambda for ingest; environment-suffixed resource names
- `modules/trading_server` — EC2 fleet + Lambda, S3 model discovery, optional Lambda chaining
- `modules/trading_server_shutdown` — Scheduled Lambda to stop instances
- `environments/{dev,qa,prod}` — Entrypoints that instantiate modules and set per-env vars
- `shared/common-variables.tf` — Shared variable patterns (VPC defaults, instance types, filters)

## Deploy Workflows

Run Terraform per environment from its folder. Example (QA):

1) `cd environments/qa`
2) `terraform init`
3) `terraform plan -var-file=terraform.tfvars -out plan.out`
4) `terraform apply plan.out`

Notes

- AWS credentials must already be configured for the target account/region.
- Lambdas are auto-packaged via the `archive_file` data source in each module; no separate zip step needed.
- `terraform destroy` from the same directory tears down that environment.

## Lambda Packaging Model

- Each module’s Lambda zips the module directory (`${path.module}`) via `data "archive_file"` while excluding `*.tf` and `.terraform/*`.
- Keep runtime files (e.g., `lambda_function.py`, `run.sh`) in the module folder root so they are included in the zip.
- The Python code expects to read `run.sh` from the working directory (`/var/task` in Lambda) via `os.getcwd()`.
- Only standard library + `boto3` are used; if you add dependencies, either vendor them into the zip or introduce a Lambda layer (do not add network-time installs).

## Event Chaining and Scheduling

- When `enable_eventbridge = true` in module variables, a success destination chains `AlpacaWebsocketLambda_${var.environment}` to `TradingServerLambda_${var.environment}`.
- The shutdown module creates a CloudWatch Events (EventBridge) rule to run daily and stop all trading servers and the ingest node.

## Naming and Discovery

- Environment suffix: Resource names (Lambda functions, IAM roles) include `_${var.environment}` in modules.
- EC2 tags:
  - Websocket ingest: `Name=alpaca-websocket-ingest-${var.environment}`
  - Trading servers: `Name=trading-server-${var.environment}-${symbol}-${model_type}-${model_number}`
- Lambdas discover instances by tag values/patterns (e.g., `trading-server*`, `alpaca-websocket-ingest[-${env}]`). Keep tags consistent with module logic.

## S3 Model Discovery (trading_server)

- Models are discovered under `s3://<bucket>/models/<model_type>/<symbol>/<model_number>/...`.
- Terraform `locals` parse keys to produce `model_info_attrs` and drive one EC2 instance per model.
- Instances write a `deployment_config.txt` in user data with bucket/model metadata for use by `run.sh`.

## Secrets, IAM, and SSM

- GitHub auth is fetched from AWS Secrets Manager `github/ssh-key` (JSON with `private-key`). Do not hard-code secrets.
- EC2 instances must attach `AmazonSSMManagedInstanceCore` and have SSM Agent installed in the AMI.
- Lambdas use `ssm:SendCommand` to run `run.sh` via `AWS-RunShellScript` on EC2s. Ensure instance profiles/roles remain intact.

## VPC and Networking

- Subnet ID and security group IDs are currently specified inline in modules. Treat them as environment-specific infrastructure details; do not change without confirmation.
- `shared/common-variables.tf` includes a `vpc_config` pattern if parameterization is needed in the future.

## Coding Conventions

Terraform

- 2-space indentation; group related resources with clear headers.
- Keep environment-specific resource names suffixed (e.g., `..._${var.environment}`).
- Keep inputs in `variables.tf` with types and helpful descriptions; export meaningful data via `outputs.tf`.
- Use `locals` for computed values; avoid hard-coding where an input makes sense.
- Validate with `terraform fmt -check` and `terraform validate` before finishing changes.

Python (Lambdas)

- Entry point must be `lambda_function.lambda_handler`.
- Read `AWS_REGION` from env; default to `us-east-1` if absent.
- Use `boto3` clients with explicit `region_name`.
- Keep logic idempotent and resilient (e.g., waiters, retries, health checks as in `modules/trading_server/lambda_function.py`).

Shell (`run.sh` on EC2 via SSM)

- Assume AMI includes required tools (jq, awscli, git, python, nats-server, streamlit, etc.). Avoid network-time installs where possible.
- Scripts should be idempotent and non-interactive; prefer `sudo -u ec2-user` where needed.
- Keep `run.sh` at module root so it’s in the Lambda zip.

## Where to Edit

- Prefer changes under `modules/<component>/` and wire via `environments/<env>/`.
- Only update top-level legacy stacks if the request explicitly targets them or for parity after module changes.
- If you introduce a new capability, add variables/outputs and document the behavior within the module; keep the environment entrypoints simple.

## Validation Checklist (for agents)

- Terraform:
  - `terraform fmt -check`
  - `terraform validate`
  - `terraform plan` in the target `environments/<env>` directory
- Packaging:
  - Confirm `data.archive_file` contains the expected runtime files (no `*.tf`)
- Execution paths:
  - Lambdas reference `run.sh` and SSM permissions exist
  - EC2 instance profiles contain SSM + Secrets + needed S3 permissions

## Known Gotchas

- Some files contain odd replacement characters from encoding (e.g., `�?`). Ignore them unless you’re explicitly cleaning encoding.
- The `archive_file` data source comes from the `hashicorp/archive` provider. If `terraform init` complains, add `required_providers { archive = { source = "hashicorp/archive" } }` to the environment.
- Python runtime is set to `python3.8`. Consider upgrading (e.g., 3.12) only if requested; changes ripple across all Lambdas.
- Hard-coded network IDs (subnet/SG) exist; parameterize only if asked or if you’re addressing an environment request.

## Quick References

- Websocket module vars: `aws_region`, `environment`, `bucket_name`, `instance_type`, `key_name`, `ami_name_filter`, `enable_eventbridge`, `git_branch`.
- Trading server module vars: `aws_region`, `environment`, `bucket_name`, `instance_type`, `key_name`, `ami_name_filter`, `websocket_instance_name`, `enable_eventbridge`, `git_branch`.
- Environments set defaults via `terraform.tfvars` and may override `git_branch` per env.

Following the above keeps environments consistent and avoids drift between modules and legacy stacks. When in doubt: prefer minimal, targeted changes in `modules/`, validate with `plan`, and ask before altering shared networking or naming patterns.

