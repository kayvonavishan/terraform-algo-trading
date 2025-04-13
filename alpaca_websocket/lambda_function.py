import os
import subprocess

def lambda_handler(event, context):
    try:
        # Assuming the deployment package unzips to the current working directory
        # Build the path to the shell script (which is packaged locally)
        script_path = os.path.join(os.getcwd(), "alpaca_websocket", "run.sh")
        
        # Ensure the script has the correct executable permissions
        os.chmod(script_path, 0o755)
        
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
