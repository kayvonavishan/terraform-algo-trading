import os
import json
import subprocess
import boto3
from urllib.parse import quote

def get_github_token():
    """
    Retrieve the GitHub personal access token from AWS Secrets Manager.
    The secret is stored as a JSON key-value pair, where the key is "private-key".
    """
    secret_name = os.environ.get("GITHUB_SECRET_ID", "github/key")
    region_name = os.environ.get("AWS_REGION", "us-east-1")
    
    client = boto3.client("secretsmanager", region_name=region_name)
    response = client.get_secret_value(SecretId=secret_name)
    
    # Parse the secret JSON string
    secret_dict = json.loads(response["SecretString"])
    
    # Retrieve the value associated with the key "private-key"
    token = secret_dict.get("private-key")
    if not token:
        raise Exception("The key 'private-key' was not found in the secret.")
    
    return token

def clone_repo():
    """
    Constructs an HTTPS URL with the personal access token for authentication,
    then clones the repository into /tmp/repo.
    """
    token = get_github_token()
    # URL-encode the token to ensure any special characters are handled properly
    encoded_token = quote(token, safe='')
    
    # Construct the HTTPS clone URL with the token embedded
    repo_url = f"https://{encoded_token}@github.com/kayvonavishan/terraform-algo-trading.git"
    clone_dir = "/tmp/repo"
    
    # Clone the repository; note that error handling and logging can be expanded as needed
    subprocess.run(["git", "clone", repo_url, clone_dir], check=True)
    return clone_dir

def lambda_handler(event, context):
    try:
        # Clone the GitHub repository using the personal access token
        clone_dir = clone_repo()
        
        # Build the path to your shell script, located at alpaca_websocket/run.sh within the repo
        script_path = os.path.join(clone_dir, "alpaca_websocket", "run.sh")
        os.chmod(script_path, 0o755)  # Ensure the script is executable
        
        # Execute the shell script and capture its output
        result = subprocess.run([script_path], capture_output=True, text=True, check=True)
        output = result.stdout.strip()
        
        return {
            "statusCode": 200,
            "body": output
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": f"Error executing Lambda: {str(e)}"
        }
