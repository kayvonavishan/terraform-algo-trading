#!/usr/bin/env python3
"""
Lambda: start the Alpaca websocket‑ingest EC2 instance, verify both EC2 status
checks are OK, retry up to <max_retries> times with a stop/start if necessary,
then run a shell script through SSM.
"""

import os
import time
import boto3


# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────
def wait_for_status_ok(ec2, instance_ids, *, max_minutes=5, delay=10):
    """Return (ok_ids, bad_ids) after polling reachability checks."""
    deadline = time.time() + max_minutes * 60
    remaining, ok_ids = set(instance_ids), set()

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

    return list(ok_ids), list(remaining)


def ensure_healthy(ec2, iid, max_retries=2):
    """
    Make sure <iid> passes both reachability checks.
    Performs up to <max_retries> stop/start cycles in addition to the
    *initial* start.  Raises if still unhealthy.
    """
    attempt = 0
    while attempt <= max_retries:
        ok, bad = wait_for_status_ok(ec2, [iid])
        if not bad:                       # healthy
            return
        attempt += 1
        if attempt > max_retries:         # out of retries
            break
        # stop → start on fresh hardware
        ec2.stop_instances(InstanceIds=bad)
        ec2.get_waiter("instance_stopped").wait(InstanceIds=bad)
        ec2.start_instances(InstanceIds=bad)

    raise RuntimeError(
        f"Instance {iid} failed EC2 status checks after {max_retries} retry cycles"
    )


# ──────────────────────────────────────────────────────────────────────────────
# Lambda entry‑point
# ──────────────────────────────────────────────────────────────────────────────
def lambda_handler(event, context):
    region_name = os.environ.get("AWS_REGION", "us-east-1")
    environment = os.environ.get("ENVIRONMENT", "qa")
    instance_name = f"alpaca-websocket-ingest-{environment}"

    ec2 = boto3.client("ec2", region_name=region_name)
    ssm = boto3.client("ssm", region_name=region_name)

    # 1. Locate ANY instance with your Name tag (exclude terminated instances)
    filters = [
        {'Name': 'tag:Name', 'Values': [instance_name]},
        {'Name': 'instance-state-name', 'Values': ['pending', 'running', 'shutting-down', 'stopping', 'stopped']}
    ]
    resp = ec2.describe_instances(Filters=filters)

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

    # 3) ensure health, allowing two retry cycles
    ensure_healthy(ec2, iid, max_retries=2)

    # 4) run your script via SSM
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

    time.sleep(2)
    inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=iid)

    return {
        "statusCode": 200,
        "body": inv.get("StandardOutputContent", "")
    }
