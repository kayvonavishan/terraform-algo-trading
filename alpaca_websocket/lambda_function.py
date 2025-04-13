import os
import shutil
import subprocess

def lambda_handler(event, context):
    try:
        # Path in the read-only area
        orig_script_path = os.path.join(os.getcwd(), "alpaca_websocket", "run.sh")
        
        # Define a writable path in /tmp
        tmp_script_path = os.path.join("/tmp", "run.sh")
        
        # Copy the script to /tmp
        shutil.copy(orig_script_path, tmp_script_path)
        
        # Set executable permissions on the copied script
        os.chmod(tmp_script_path, 0o755)
        
        # Execute the script and capture its output
        result = subprocess.run([tmp_script_path], capture_output=True, text=True, check=True)
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
