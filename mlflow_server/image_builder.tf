data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_imagebuilder_component" "mlflow_install" {
  name       = "mlflow-install"
  platform   = "Linux"
  version    = "1.0.0"

  data = <<-YAML
    name: mlflow-install
    schemaVersion: 1.0
    phases:
      - name: build
        steps:
          - name: Install
            action: ExecuteBash
            inputs:
              commands:
                # ————— basic OS deps —————
                - apt-get update -y
                - apt-get install -y python3-pip postgresql-client
                - pip3 install "mlflow[extras]==${var.mlflow_version}" boto3 psycopg2-binary

                # ————— systemd unit —————
                - |                
                cat >/etc/systemd/system/mlflow.service <<'UNIT'
                [Unit]
                Description=MLflow Tracking Server
                Wants=network-online.target
                After=network-online.target

                [Service]
                Type=simple
                EnvironmentFile=-/etc/mlflow.env
                ExecStart=/usr/local/bin/mlflow server \
                  --backend-store-uri $${MLFLOW_BACKEND} \
                  --default-artifact-root $${MLFLOW_ARTIFACT_ROOT} \
                  --host 0.0.0.0 --port $${MLFLOW_PORT}
                Restart=on-failure

                [Install]
                WantedBy=multi-user.target
                UNIT


                # ————— stub env file so the unit never fails if cloud-init is slow —————
                - touch /etc/mlflow.env
                - chmod 600 /etc/mlflow.env

                # ————— enable at boot —————
                - systemctl daemon-reload
                - systemctl enable mlflow
  YAML
}

resource "aws_imagebuilder_image_recipe" "mlflow" {
  name         = "mlflow-ubuntu-22"
  version      = "1.0.0"
  parent_image = data.aws_ami.ubuntu.id

  component {
    component_arn = aws_imagebuilder_component.mlflow_install.arn
  }
}


resource "aws_security_group" "builder" {
  name   = "mlflow-imagebuilder-sg"
  vpc_id = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "imagebuilder" {
  name               = "mlflow-imagebuilder-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_instance_profile" "imagebuilder" {
  name = "mlflow-imagebuilder-profile"
  role = aws_iam_role.imagebuilder.name
}

resource "aws_iam_role_policy_attachment" "imagebuilder_ssm" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_imagebuilder_infrastructure_configuration" "mlflow" {
  name                        = "mlflow-build-infra"
  instance_profile_name       = aws_iam_instance_profile.imagebuilder.name
  subnet_id                   = local.public_subnet_id
  security_group_ids          = [aws_security_group.builder.id]
  terminate_instance_on_failure = true
}

resource "aws_imagebuilder_image" "mlflow" {
  image_recipe_arn                = aws_imagebuilder_image_recipe.mlflow.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.mlflow.arn

  tags = {
    Name = "mlflow-image"
  }
}

locals {
  mlflow_ami_id = one(aws_imagebuilder_image.mlflow.output_resources[0].amis).image
}