#cloud-config
write_files:
  - path: /etc/mlflow.env
    owner: root:root
    permissions: '0600'
    content: |
      MLFLOW_BACKEND=postgresql+psycopg2://mlflow:${db_password}@${db_endpoint}:5432/mlflow
      MLFLOW_ARTIFACT_ROOT=s3://${bucket_name}
      MLFLOW_PORT=${mlflow_port}

runcmd:
  - systemctl daemon-reload   # pick up the env file *and* any new unit
  - systemctl restart mlflow