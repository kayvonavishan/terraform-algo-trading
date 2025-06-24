#cloud-config
runcmd:
  - |
    cat <<EOF > /etc/mlflow.env
    MLFLOW_BACKEND=postgresql+psycopg2://mlflow:${db_password}@${db_endpoint}:5432/mlflow
    MLFLOW_ARTIFACT_ROOT=s3://${bucket_name}
    EOF
  - systemctl restart mlflow