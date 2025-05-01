import os
import time
import boto3

def lambda_handler(event, context):
    region = os.environ.get("AWS_REGION", "us-east-1")
    ssm = boto3.client("ssm", region_name=region)
    ec2 = boto3.client("ec2", region_name=region)

    # 1. Find the single alpaca-websocket-ingest instance
    ingest_filters = [
        {'Name': 'tag:Name', 'Values': ['alpaca-websocket-ingest']},
        {'Name': 'instance-state-name', 'Values': ['running']}
    ]
    ingest_resp = ec2.describe_instances(Filters=ingest_filters)
    try:
        ingest_inst = ingest_resp['Reservations'][0]['Instances'][0]
        nats_ip = ingest_inst['PublicIpAddress']
    except (IndexError, KeyError):
        raise Exception("Could not find running alpaca-websocket-ingest instance")

    # 2. Find all trading-server* instances
    trade_filters = [
        {'Name': 'tag:Name', 'Values': ['trading-server*']},
        {'Name': 'instance-state-name', 'Values': ['running']}
    ]
    trade_resp = ec2.describe_instances(Filters=trade_filters)
    instance_ids = [
        inst['InstanceId']
        for res in trade_resp.get('Reservations', []) 
        for inst in res.get('Instances', [])
    ]
    if not instance_ids:
        raise Exception("No running trading-server instances found")

    # 3. Read your local run.sh
    script_path = os.path.join(os.getcwd(), "trading_server", "run.sh")
    with open(script_path) as f:
        lines = f.read().splitlines()

    # 4. Prepend export (so your run.sh can reference $NATS_PUBLIC_IP)
    commands = [
        f"export NATS_PUBLIC_IP={nats_ip}",
        # (option A) source the script in‐line
        *lines,
        # (option B) or simply invoke the script file if it already exists on the instance:
        # f"bash /home/ec2-user/run.sh"
    ]

    # 5. Send to all trading-server instances
    resp = ssm.send_command(
        InstanceIds=instance_ids,
        DocumentName="AWS-RunShellScript",
        Parameters={'commands': commands},
        TimeoutSeconds=60,
    )
    cmd_id = resp['Command']['CommandId']

    # 6. (Optional) wait and collect results…
    time.sleep(2)
    results = {}
    for iid in instance_ids:
        inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=iid)
        results[iid] = {
            "Status": inv['Status'],
            "Stdout": inv.get('StandardOutputContent', ''),
            "Stderr": inv.get('StandardErrorContent', ''),
        }

    return {"statusCode": 200, "body": results}

