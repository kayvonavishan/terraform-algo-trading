import os
import time
import boto3

def lambda_handler(event, context):
    try:
        region_name = os.environ.get("AWS_REGION", "us-east-1")
        # Initialize boto3 clients for SSM and EC2.
        ssm_client = boto3.client("ssm", region_name=region_name)
        ec2_client = boto3.client("ec2", region_name=region_name)

        # Find all running EC2 instances where the tag 'Name' starts with 'trading-server'.
        filters = [
            {'Name': 'tag:Name', 'Values': ['trading-server*']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
        ec2_response = ec2_client.describe_instances(Filters=filters)
        instance_ids = []
        for reservation in ec2_response.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                instance_id = instance.get("InstanceId")
                if instance_id:
                    instance_ids.append(instance_id)
        
        if not instance_ids:
            raise Exception("Could not find any running instances with tag Name starting with 'trading-server'")
        
        # Read the shell script from the deployment package.
        script_path = os.path.join(os.getcwd(), "trading_server", "run.sh")
        with open(script_path, "r") as script_file:
            commands = script_file.read()

        # Use SSM to run the shell script on the target EC2 instances.
        response = ssm_client.send_command(
            InstanceIds=instance_ids,
            DocumentName="AWS-RunShellScript",
            Parameters={'commands': [commands]},
            TimeoutSeconds=60,
        )
        command_id = response['Command']['CommandId']
        
        # Wait briefly for the command to finish.
        time.sleep(2)
        
        # Retrieve the invocation results for each instance.
        results = {}
        for instance_id in instance_ids:
            invocation = ssm_client.get_command_invocation(
                CommandId=command_id,
                InstanceId=instance_id,
            )
            results[instance_id] = {
                "Status": invocation.get("Status"),
                "StandardOutputContent": invocation.get("StandardOutputContent", ""),
                "StandardErrorContent": invocation.get("StandardErrorContent", "")
            }
        
        return {
            "statusCode": 200,
            "body": results
        }
        
    except Exception as e:
       return {
           "statusCode": 500,
           "body": f"Error executing Lambda: {str(e)}"
       }
