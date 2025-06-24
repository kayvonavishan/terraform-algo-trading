# ❶ Component YAML  (inline)
resource "aws_imagebuilder_component" "mlflow_install" {
  name                = "mlflow-install"
  platform            = "Linux"
  version             = "1.0.0"
  description         = "Install MLflow ${var.mlflow_version} + deps and create systemd unit"

  data = <<-YAML
    name: mlflow-install
    description: Install MLflow and systemd service
    schemaVersion: 1.0
    phases:
      - name: build
        steps:
          - name: InstallPackages
            action: ExecuteBash
            inputs:
              commands:
                - apt-get update -y
                - apt-get install -y python3-pip postgresql-client
                - pip3 install mlflow[extras]==${var.mlflow_version} boto3 psycopg2-binary

          - name: CreateService
            action: ExecuteBash
            inputs:
              commands:
                - |
                  cat <<'EOF' > /etc/systemd/system/mlflow.service
                  [Unit]
                  Description=MLflow Tracking Server
                  After=network.target

                  [Service]
                  Type=simple
                  EnvironmentFile=/etc/mlflow.env
                  ExecStart=/usr/local/bin/mlflow server \
                    --backend-store-uri $${MLFLOW_BACKEND} \
                    --default-artifact-root $${MLFLOW_ARTIFACT_ROOT} \
                    --host 0.0.0.0 \
                    --port 5000
                  Restart=on-failure

                  [Install]
                  WantedBy=multi-user.target
                  EOF
                - systemctl daemon-reload
                - systemctl enable mlflow
    YAML
}

# ❷ Image recipe
resource "aws_imagebuilder_image_recipe" "mlflow" {
  name         = "mlflow-ubuntu-22"
  version      = "1.0.0"
  parent_image = data.aws_ami.ubuntu.id
  components   = [aws_imagebuilder_component.mlflow_install.arn]
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# ❸ Infrastructure configuration for the build
resource "aws_imagebuilder_infrastructure_configuration" "mlflow" {
  name                  = "mlflow-build-infra"
  instance_profile_name = aws_iam_instance_profile.imageBuilder.name
  subnet_id             = local.public_subnet_id
  security_group_ids    = [aws_security_group.builder.id]
  terminate_instance_on_failure = true
}

resource "aws_security_group" "builder" {
  name   = "mlflow-imagebuilder-sg"
  vpc_id = local.vpc_id
  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_iam_role" "imageBuilder" {
  name               = "mlflow-imagebuilder-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_instance_profile" "imageBuilder" {
  name = "mlflow-imagebuilder-profile"
  role = aws_iam_role.imageBuilder.name
}

# Minimal permissions (+SSM)
resource "aws_iam_role_policy_attachment" "imageBuilder_ssm" {
  role       = aws_iam_role.imageBuilder.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ❹ Kick off the build & produce the AMI
resource "aws_imagebuilder_image" "mlflow" {
  image_recipe_arn                = aws_imagebuilder_image_recipe.mlflow.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.mlflow.arn
  tags = {
    Name = "mlflow-image"
  }
}

# Pull out the AMI ID
locals {
  mlflow_ami_id = one(aws_imagebuilder_image.mlflow.output_resources[0].amis).*image
}