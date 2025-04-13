import os
import shutil
import subprocess
import boto3
import json

def lambda_handler(event, context):
    try:
        # Determine the current working directory and file paths.
        cwd = os.getcwd()
        orig_script_path = os.path.join(cwd, "alpaca_websocket", "run.sh")
        tmp_script_path = os.path.join("/tmp", "run.sh")
        
        # Copy run.sh from the package to /tmp.
        shutil.copy(orig_script_path, tmp_script_path)
        
        # Convert CRLF (or CR) line endings to LF.
        with open(tmp_script_path, "rb") as f:
            content = f.read()
        content = content.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
        with open(tmp_script_path, "wb") as f:
            f.write(content)
        
        # Set executable permissions on run.sh.
        os.chmod(tmp_script_path, 0o755)
        
        # Retrieve the PEM file from Secrets Manager via boto3.
        secret_name = "algo-deployment.pem"
        region_name = os.environ.get("AWS_REGION", "us-east-1")
        secrets_client = boto3.client("secretsmanager", region_name=region_name)
        secret_response = secrets_client.get_secret_value(SecretId=secret_name)
        secret_string = secret_response.get("SecretString")
        if not secret_string:
            raise Exception("Secret string is empty")
        secret_json = json.loads(secret_string)
        pem_key = secret_json.get("key")
        if not pem_key:
            raise Exception("PEM key not found in the secret")
        
        # Write the PEM file to /tmp.
        pem_path = os.path.join("/tmp", "algo-deployment.pem")
        with open(pem_path, "w") as pem_file:
            pem_file.write(pem_key)
        os.chmod(pem_path, 0o600)
        
        # Use boto3 to get the public IP of the EC2 instance.
        ec2_client = boto3.client("ec2", region_name=region_name)
        filters = [
            {'Name': 'tag:Name', 'Values': ['alpaca-websocket-ingest']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
        ec2_response = ec2_client.describe_instances(Filters=filters)
        instance_ip = None
        for reservation in ec2_response.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                instance_ip = instance.get("PublicIpAddress")
                if instance_ip:
                    break
            if instance_ip:
                break
        if not instance_ip:
            raise Exception("Could not find a running instance with tag Name=alpaca-websocket-ingest")
        
        # Set the INSTANCE_IP environment variable for the shell script.
        env = os.environ.copy()
        env["INSTANCE_IP"] = instance_ip
        
        # Execute run.sh and capture its output.
        result = subprocess.run(["bash", tmp_script_path],
                                capture_output=True,
                                text=True,
                                check=True,
                                cwd="/tmp",
                                env=env)
        output = result.stdout.strip()
        
        return {
            "statusCode": 200,
            "body": output
        }
    except Exception as e:
        #print("STDOUT:", e.stdout)
        #print("STDERR:", e.stderr)
        return {
            "statusCode": 500,
            "body": f"Error executing Lambda: {str(e)}"
        }
