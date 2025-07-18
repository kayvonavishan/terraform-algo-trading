import os
import time
import boto3

def lambda_handler(event, context):
    region = os.environ.get("AWS_REGION", "us-east-1")
    ec2 = boto3.client("ec2", region_name=region)
    ssm = boto3.client("ssm", region_name=region)

    # ─── 1) FIND INGEST NODE ────────────────────────────────────────────────
    ingest_tag = {'Name': 'tag:Name', 'Values': ['alpaca-websocket-ingest']}
    all_ingest = ec2.describe_instances(Filters=[ingest_tag]).get('Reservations', [])
    if not all_ingest:
        raise Exception("No EC2 found with tag Name=alpaca-websocket-ingest")
    ingest_inst = all_ingest[0]['Instances'][0]
    ingest_id   = ingest_inst['InstanceId']
    ingest_state = ingest_inst['State']['Name']

    # ─── 2) START INGEST NODE IF NEEDED ────────────────────────────────────
    if ingest_state != 'running':
        ec2.start_instances(InstanceIds=[ingest_id])
        waiter = ec2.get_waiter('instance_running')
        # Wait up to ~60s
        waiter.wait(InstanceIds=[ingest_id], WaiterConfig={'Delay':5, 'MaxAttempts':12})
        # extra buffer for SSM agent
        time.sleep(120)

    # ─── 3) RE-DESCRIBE TO GET PUBLIC IP ──────────────────────────────────
    ingest_inst = ec2.describe_instances(Filters=[ingest_tag])\
                    ['Reservations'][0]['Instances'][0]
    nats_ip = ingest_inst.get('PublicIpAddress')
    if not nats_ip:
        raise Exception("Ingest node has no PublicIpAddress")

    # ─── 4) FIND ALL TRADING SERVERS ─────────────────────────────────────
    trade_tag = {'Name': 'tag:Name', 'Values': ['trading-server*']}
    all_trade = ec2.describe_instances(Filters=[trade_tag]).get('Reservations', [])
    if not all_trade:
        raise Exception("No EC2 found with tag Name=trading-server*")
    trade_insts = [i
               for r in all_trade
               for i in r['Instances']
               if i['State']['Name'] not in ('terminated','shutting-down')]
    trade_ids   = [i['InstanceId'] for i in trade_insts]

    # ─── 5) START ANY TRADING SERVERS NOT RUNNING ─────────────────────────
    to_start = [i['InstanceId']
            for i in trade_insts
            if i['State']['Name'] == 'stopped']
    if to_start:
        ec2.start_instances(InstanceIds=to_start)
        waiter = ec2.get_waiter('instance_running')
        waiter.wait(InstanceIds=to_start, WaiterConfig={'Delay':5, 'MaxAttempts':12})
        time.sleep(5)

    # ─── 6) LOAD YOUR SCRIPT & INJECT NATS IP ─────────────────────────────
    script_path = os.path.join(os.getcwd(), 'run.sh')
    with open(script_path) as f:
        lines = f.read().splitlines()
    commands = [
        f"export NATS_PUBLIC_IP={nats_ip}",
        *lines
    ]

    # ─── 7) DISPATCH VIA SSM ──────────────────────────────────────────────
    resp = ssm.send_command(
        InstanceIds=trade_ids,
        DocumentName="AWS-RunShellScript",
        Parameters={'commands': commands},
        TimeoutSeconds=120,  # give yourself a bit more runway
    )
    cmd_id = resp['Command']['CommandId']

    # ─── 8) COLLECT RESULTS ──────────────────────────────────────────────
    time.sleep(2)
    results = {}
    for iid in trade_ids:
        inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=iid)
        results[iid] = {
            "Status": inv['Status'],
            "Stdout": inv.get('StandardOutputContent', ''),
            "Stderr": inv.get('StandardErrorContent', ''),
        }

    return {"statusCode": 200, "body": results}
