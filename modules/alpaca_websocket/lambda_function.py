#!/usr/bin/env python3
"""
Lambda: start the Alpaca websocket‑ingest EC2 instance, be sure it passes
*both* EC2 status checks (system + instance), retry once with stop/start,
then run a shell script via SSM.
"""

import os
import time
import boto3


# ──────────────────────────────────────────────────────────────────────────────
# Helper ─ wait until both reachability checks are OK
# ──────────────────────────────────────────────────────────────────────────────
def wait_for_status_ok(ec2, instance_ids, *, max_minutes=5, delay=10):
    """
    Poll `describe_instance_status` until both SystemStatus and InstanceStatus
    are "ok" (or until the timeout).  Returns (ok_ids, bad_ids).
    """
    deadline = time.time() + max_minutes * 60
    remaining = set(instance_ids)
    ok_ids = set()

    while remaining and time.time() < deadline:
        statuses = ec2.describe_instance_status(
            InstanceIds=list(remaining),
            IncludeAllInstances=True,
        )["InstanceStatuses"]

        for st in statuses:
            iid = st["InstanceId"]
            sys_ok  = st["SystemStatus"]["Status"]  == "ok"
            inst_ok = st["InstanceStatus"]["Status"] == "ok"
            if sys_ok and inst_ok:
                ok_ids.add(iid)
                remaining.discard(iid)

        if remaining:
            time.sleep(delay)

    bad_ids = list(remaining)
    return list(ok_ids), bad_ids


# ──────────────────────────────────────────────────────────────────────────────
# Main Lambda entry‑point
# ──────────────────────────────────────────────────────────────────────────────
def lambda_handler(event, context):
    region_name = os.environ.get("AWS_REGION", "us-east-1")
    environment = os.environ.get("ENVIRONMENT", "qa")
    instance_name = f"alpaca-websocket-ingest-{environment}"

    ec2 = boto3.client("ec2", region_name=region_name)
    ssm = boto3.client("ssm", region_name=region_name)

    # 1) locate the ingest instance by Name tag
    resp = ec2.describe_instances(
        Filters=[{"Name": "tag:Name", "Values": [instance_name]}]
    )
    instances = [
        i
        for r in resp.get("Reservations", [])
        for i in r.get("Instances", [])
    ]
    if not instances:
        raise RuntimeError(f"No EC2 found with tag Name={instance_name}")

    inst = instances[0]
    iid  = inst["InstanceId"]

    # 2) start if needed
    if inst["State"]["Name"] != "running":
        ec2.start_instances(InstanceIds=[iid])

    # 3) wait for both EC2 checks to be OK
    ok, bad = wait_for_status_ok(ec2, [iid])

    # 4) retry once (stop → start) if still bad
    if bad:
        ec2.stop_instances(InstanceIds=bad)
        ec2.get_waiter("instance_stopped").wait(InstanceIds=bad)
        ec2.start_instances(InstanceIds=bad)
        _, still_bad = wait_for_status_ok(ec2, bad, max_minutes=6)
        if still_bad:
            raise RuntimeError(f"Ingest instance {still_bad} failed EC2 health checks")

    # 5) run your script via SSM
    script_path = os.path.join(os.getcwd(), "run.sh")
    with open(script_path) as f:
        commands = f.read().splitlines()

    cmd_resp = ssm.send_command(
        InstanceIds=[iid],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands},
        TimeoutSeconds=60,
    )
    cmd_id = cmd_resp["Command"]["CommandId"]

    time.sleep(2)  # brief pause before first poll
    inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=iid)

    return {
        "statusCode": 200,
        "body": inv.get("StandardOutputContent", "")
    }
