#!/usr/bin/env python3
"""
Start the Alpaca ingest node and all trading‑server EC2 instances,
verify they pass both EC2 status checks, retry up to <max_retries>
stop/start cycles if necessary, and finally dispatch a shell script
via SSM.
"""

import os
import time
import boto3


# ──────────────────────────────────────────────────────────────────────────────
# Helper 1: wait until *both* reachability checks are OK
# ──────────────────────────────────────────────────────────────────────────────
def wait_for_status_ok(ec2, instance_ids, *, max_minutes=5, delay=10):
    """
    Poll `describe_instance_status` until both SystemStatus and InstanceStatus
    are "ok" for every instance or until timeout.
    Returns (ok_ids, bad_ids).
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

    return list(ok_ids), list(remaining)


# ──────────────────────────────────────────────────────────────────────────────
# Helper 2: ensure health with multiple stop/start retries
# ──────────────────────────────────────────────────────────────────────────────
def ensure_healthy(ec2, instance_ids, *, max_retries=2, wait_minutes=5):
    """
    Make sure every ID in <instance_ids> passes both reachability checks.
    Performs up to <max_retries> stop/start cycles.  Returns the list of
    healthy IDs; raises if any remain bad after all retries.
    """
    remaining = list(instance_ids)

    for attempt in range(max_retries + 1):  # initial attempt + N retries
        ok, bad = wait_for_status_ok(ec2, remaining, max_minutes=wait_minutes)
        if not bad:
            return ok  # all healthy

        if attempt == max_retries:
            raise RuntimeError(f"Instances {bad} failed EC2 health checks")

        # stop → start the bad ones on fresh hardware, then loop again
        ec2.stop_instances(InstanceIds=bad)
        ec2.get_waiter("instance_stopped").wait(InstanceIds=bad)
        ec2.start_instances(InstanceIds=bad)
        remaining = bad  # only re‑check the ones that were bad


# ──────────────────────────────────────────────────────────────────────────────
# Lambda entry‑point
# ──────────────────────────────────────────────────────────────────────────────
def lambda_handler(event, context):
    # ── config via env vars ──────────────────────────────────────────────────
    region       = os.environ.get("AWS_REGION", "us-east-1")
    environment  = os.environ.get("ENVIRONMENT",  "qa")
    max_retries  = int(os.environ.get("MAX_RETRIES", "2"))  # optional override

    ingest_name  = f"alpaca-websocket-ingest-{environment}"
    trade_pattern = f"trading-server-{environment}-*"

    ec2 = boto3.client("ec2", region_name=region)
    ssm = boto3.client("ssm", region_name=region)

    # ─── 1) locate ingest node ───────────────────────────────────────────────
    ingest_filters = [
        {"Name": "tag:Name",            "Values": [ingest_name]},
        # exclude terminated / shutting‑down / terminating
        {"Name": "instance-state-name", "Values": [
            "pending", "running", "stopping", "stopped"
        ]},
    ]
    ingest_res = ec2.describe_instances(Filters=ingest_filters)["Reservations"]

    ingest_insts = [i for r in ingest_res for i in r["Instances"]]
    if not ingest_insts:
        raise RuntimeError(f"No *non‑terminated* EC2 found with tag Name={ingest_name}")

    # if more than one survives (e.g. AWS is still cleaning up a duplicate),
    # prefer an already‑running copy; otherwise just take the newest launch.
    ingest_inst = (
        next((i for i in ingest_insts if i["State"]["Name"] == "running"), None)
        or max(ingest_insts, key=lambda x: x["LaunchTime"])
    )
    ingest_id = ingest_inst["InstanceId"]

    # ─── 2) power on ingest node if needed, then ensure health ───────────────
    if ingest_inst["State"]["Name"] != "running":
        ec2.start_instances(InstanceIds=[ingest_id])

    ensure_healthy(ec2, [ingest_id], max_retries=max_retries, wait_minutes=6)

    # refresh description to get current Public IP
    ingest_inst = ec2.describe_instances(Filters=[ingest_filters])["Reservations"][0]["Instances"][0]
    nats_ip = ingest_inst.get("PublicIpAddress")
    if not nats_ip:
        raise RuntimeError("Ingest node has no PublicIpAddress")

    # ─── 3) find trading servers ─────────────────────────────────────────────
    trade_tag = {"Name": "tag:Name", "Values": [trade_pattern]}
    trade_res = ec2.describe_instances(Filters=[trade_tag])["Reservations"]
    if not trade_res:
        raise RuntimeError(f"No EC2 found with tag Name={trade_pattern}")

    trade_insts = [
        i for r in trade_res for i in r["Instances"]
        if i["State"]["Name"] not in ("terminated", "shutting-down", "terminating")
    ]
    if not trade_insts:
        raise RuntimeError("No valid (non‑terminated) trading servers found")

    # ─── 4) start stopped servers ────────────────────────────────────────────
    to_start = [i["InstanceId"] for i in trade_insts if i["State"]["Name"] == "stopped"]
    if to_start:
        ec2.start_instances(InstanceIds=to_start)

    # ─── 5) ensure *all* trading servers are healthy ────────────────────────
    all_ids = [i["InstanceId"] for i in trade_insts]  # running + newly started
    healthy_trade_ids = ensure_healthy(
        ec2, all_ids, max_retries=max_retries, wait_minutes=6
    )

    # ─── 6) dispatch script via SSM ──────────────────────────────────────────
    script_path = os.path.join(os.getcwd(), "run.sh")
    with open(script_path) as f:
        script_lines = f.read().splitlines()

    commands = [f"export NATS_PUBLIC_IP={nats_ip}", *script_lines]

    cmd_resp = ssm.send_command(
        InstanceIds=healthy_trade_ids,
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands},
        TimeoutSeconds=120,
    )
    cmd_id = cmd_resp["Command"]["CommandId"]

    # ─── 7) gather results ──────────────────────────────────────────────────
    time.sleep(2)
    results = {}
    for iid in healthy_trade_ids:
        inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=iid)
        results[iid] = {
            "Status": inv["Status"],
            "Stdout": inv.get("StandardOutputContent", ""),
            "Stderr": inv.get("StandardErrorContent", ""),
        }

    return {"statusCode": 200, "body": results}
