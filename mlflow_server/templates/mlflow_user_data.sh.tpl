#cloud-config
write_files:
  - path: /etc/mlflow.env
    owner: root:root
    permissions: '0644'
    content: |
      MLFLOW_BACKEND=postgresql+psycopg2://mlflow:${db_password}@${db_endpoint}:5432/mlflow
      MLFLOW_ARTIFACT_ROOT=s3://${bucket_name}

runcmd:
  # Reload systemd so it sees our new env-file,
  # then start MLflow (it’s already 'enabled' on boot).
  - systemctl daemon-reload
  - systemctl restart mlflow.service