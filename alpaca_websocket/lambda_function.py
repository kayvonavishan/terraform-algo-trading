import os
import time
import boto3
import json

def lambda_handler(event, context):
    try:
        region_name = os.environ.get("AWS_REGION", "us-east-1")
        # Initialize boto3 clients for SSM and EC2.
        ssm_client = boto3.client("ssm", region_name=region_name)
        ec2_client = boto3.client("ec2", region_name=region_name)

        # Find the instance ID for the EC2 instance using its tag.
        filters = [
            {'Name': 'tag:Name', 'Values': ['alpaca-websocket-ingest']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
        ec2_response = ec2_client.describe_instances(Filters=filters)
        instance_id = None
        for reservation in ec2_response.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                instance_id = instance.get("InstanceId")
                if instance_id:
                    break
            if instance_id:
                break
        if not instance_id:
            raise Exception("Could not find a running instance with tag Name=alpaca-websocket-ingest")
        
        # Read the shell script from the deployment package.
        script_path = os.path.join(os.getcwd(), "run.sh")
        with open(script_path, "r") as script_file:
            commands = script_file.read()

        # Use SSM to run the shell script on the target EC2 instance.
        response = ssm_client.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={'commands': [commands]},
            TimeoutSeconds=60,
        )
        command_id = response['Command']['CommandId']
        
        # Wait briefly for the command to finish.
        time.sleep(2)
        
        # Retrieve the invocation results.
        invocation = ssm_client.get_command_invocation(
            CommandId=command_id,
            InstanceId=instance_id,
        )
        
        return {
            "statusCode": 200,
            "body": invocation.get("StandardOutputContent", "")
        }
        
    except Exception as e:
       return {
           "statusCode": 500,
           "body": f"Error executing Lambda: {str(e)}"
       }
