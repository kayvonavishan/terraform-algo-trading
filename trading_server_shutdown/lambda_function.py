import os
import boto3

def lambda_handler(event, context):
    region = os.environ.get("AWS_REGION", "us-east-1")
    ec2 = boto3.client("ec2", region_name=region)

    # Filter instances by tags for trading servers and ingest node
    filters = [
        {"Name": "tag:Name", "Values": ["trading-server*", "alpaca-websocket-ingest"]}
    ]
    reservations = ec2.describe_instances(Filters=filters).get("Reservations", [])
    # Collect instance IDs that are not already stopped or stopping
    instance_ids = [
        inst["InstanceId"]
        for r in reservations
        for inst in r["Instances"]
        if inst["State"]["Name"] not in ["stopped", "stopping"]
    ]

    if not instance_ids:
        return {"statusCode": 200, "body": "No instances to stop"}

    # Stop the instances
    ec2.stop_instances(InstanceIds=instance_ids)

    return {"statusCode": 200, "body": f"Stopped instances: {instance_ids}"}
