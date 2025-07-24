import os
import time
import boto3
import json

def lambda_handler(event, context):
    region_name = os.environ.get("AWS_REGION", "us-east-1")
    environment = os.environ.get("ENVIRONMENT", "qa")
    instance_name = f"alpaca-websocket-ingest-{environment}"
    
    ssm = boto3.client("ssm", region_name=region_name)
    ec2 = boto3.client("ec2", region_name=region_name)

    # 1. Locate ANY instance with your Name tag (exclude terminated instances)
    filters = [
        {'Name': 'tag:Name', 'Values': [instance_name]},
        {'Name': 'instance-state-name', 'Values': ['pending', 'running', 'shutting-down', 'stopping', 'stopped']}
    ]
    resp = ec2.describe_instances(Filters=filters)
    instances = [
        inst
        for r in resp.get("Reservations", [])
        for inst in r.get("Instances", [])
    ]
    if not instances:
        raise Exception(f"No EC2 found with tag Name={instance_name}")

    inst = instances[0]
    instance_id = inst["InstanceId"]
    state      = inst["State"]["Name"]

    # 2. Start it if it’s not already running
    if state != "running":
        ec2.start_instances(InstanceIds=[instance_id])

        # 3. Wait for the machine to boot and SSM agent to check in
        waiter = ec2.get_waiter("instance_running")
        waiter.wait(InstanceIds=[instance_id])
        # give the SSM agent a few extra seconds to come online
        time.sleep(30)

    # 4. Now send your RunShellScript command exactly as before
    with open(os.path.join(os.getcwd(), "run.sh")) as f:
        commands = f.read().splitlines()

    cmd = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Parameters={'commands': commands},
        TimeoutSeconds=60,
    )
    cid = cmd['Command']['CommandId']

    # (…then poll get_command_invocation exactly as you do now…)
    time.sleep(2)
    inv = ssm.get_command_invocation(CommandId=cid, InstanceId=instance_id)

    return {
        "statusCode": 200,
        "body": inv.get("StandardOutputContent", "")
    }