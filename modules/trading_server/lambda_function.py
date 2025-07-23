#!/usr/bin/env python3
"""
Start the Alpaca ingest node and all trading‑server EC2 instances,
verify they pass both EC2 status checks, and dispatch a shell script
via SSM.  Any instance that still fails after one stop/start cycle
causes the Lambda to error so the caller can react.
"""

import os
import time
import boto3
import botocore.exceptions

# ──────────────────────────────────────────────────────────────────────────────
# Helper: wait until *both* reachability checks are OK
# ──────────────────────────────────────────────────────────────────────────────
def wait_for_status_ok(ec2, instance_ids, *, max_minutes=5, delay=10):
    """
    Poll `describe_instance_status` every <delay> seconds until *both*
    SystemStatus and InstanceStatus are "ok" or until <max_minutes> elapse.

    Returns (ok_ids, bad_ids).
    """
    deadline = time.time() + max_minutes * 60
    remaining = set(instance_ids)
    ok_ids = set()

    while remaining and time.time() < deadline:
        statuses = ec2.describe_instance_status(
            InstanceIds=list(remaining),
            IncludeAllInstances=True
        )["InstanceStatuses"]

        for st in statuses:
            iid = st["InstanceId"]
            sys_ok = st["SystemStatus"]["Status"] == "ok"
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
    region       = os.environ.get("AWS_REGION", "us-east-1")
    environment  = os.environ.get("ENVIRONMENT",  "qa")
    ingest_name  = f"alpaca-websocket-ingest-{environment}"
    trade_pattern = f"trading-server-{environment}-*"

    ec2 = boto3.client("ec2", region_name=region)
    ssm = boto3.client("ssm", region_name=region)

    # ─── 1) locate ingest node ────────────────────────────────────────────────
    ingest_tag = {"Name": "tag:Name", "Values": [ingest_name]}
    ingest_res = ec2.describe_instances(Filters=[ingest_tag])["Reservations"]
    if not ingest_res:
        raise RuntimeError(f"No EC2 found with tag Name={ingest_name}")
    ingest_inst = ingest_res[0]["Instances"][0]
    ingest_id   = ingest_inst["InstanceId"]

    # ─── 2) ensure ingest node is healthy ────────────────────────────────────
    if ingest_inst["State"]["Name"] != "running":
        ec2.start_instances(InstanceIds=[ingest_id])

    ok, bad = wait_for_status_ok(ec2, [ingest_id])
    if bad:
        # one stop/start retry
        ec2.stop_instances(InstanceIds=bad)
        ec2.get_waiter("instance_stopped").wait(InstanceIds=bad)
        ec2.start_instances(InstanceIds=bad)
        _, still_bad = wait_for_status_ok(ec2, bad, max_minutes=6)
        if still_bad:
            raise RuntimeError(f"Ingest node {still_bad} failed EC2 health checks")

    # refresh description to get Public IP
    ingest_inst = ec2.describe_instances(Filters=[ingest_tag])["Reservations"][0]["Instances"][0]
    nats_ip = ingest_inst.get("PublicIpAddress")
    if not nats_ip:
        raise RuntimeError("Ingest node has no PublicIpAddress")

    # ─── 3) find all trading servers ─────────────────────────────────────────
    trade_tag = {"Name": "tag:Name", "Values": [trade_pattern]}
    trade_res = ec2.describe_instances(Filters=[trade_tag])["Reservations"]
    if not trade_res:
        raise RuntimeError(f"No EC2 found with tag Name={trade_pattern}")

    trade_insts = [
        i for r in trade_res for i in r["Instances"]
        if i["State"]["Name"] not in ("terminated", "shutting-down", "terminating")
    ]
    if not trade_insts:
        raise RuntimeError(f"No valid (non‑terminated) trading servers found")

    # ─── 4) start stopped servers ────────────────────────────────────────────
    to_start = [i["InstanceId"] for i in trade_insts if i["State"]["Name"] == "stopped"]
    if to_start:
        ec2.start_instances(InstanceIds=to_start)

    # Wait for health
    all_ids = [i["InstanceId"] for i in trade_insts]  # running + freshly started
    ok, bad = wait_for_status_ok(ec2, all_ids)

    # Retry *once* for the bad list
    if bad:
        ec2.stop_instances(InstanceIds=bad)
        ec2.get_waiter("instance_stopped").wait(InstanceIds=bad)
        ec2.start_instances(InstanceIds=bad)
        ok2, still_bad = wait_for_status_ok(ec2, bad, max_minutes=6)
        ok += ok2
        if still_bad:
            raise RuntimeError(f"Trading servers {still_bad} failed EC2 health checks")

    if not ok:
        raise RuntimeError("No healthy trading servers for SSM commands")

    # ─── 5) dispatch script via SSM ──────────────────────────────────────────
    script_path = os.path.join(os.getcwd(), "run.sh")
    with open(script_path) as f:
        script_lines = f.read().splitlines()

    commands = [f"export NATS_PUBLIC_IP={nats_ip}", *script_lines]

    resp = ssm.send_command(
        InstanceIds=ok,
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands},
        TimeoutSeconds=120,
    )
    cmd_id = resp["Command"]["CommandId"]

    # ─── 6) gather results ──────────────────────────────────────────────────
    time.sleep(2)
    results = {}
    for iid in ok:
        inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=iid)
        results[iid] = {
            "Status": inv["Status"],
            "Stdout": inv.get("StandardOutputContent", ""),
            "Stderr": inv.get("StandardErrorContent", ""),
        }

    return {"statusCode": 200, "body": results}
