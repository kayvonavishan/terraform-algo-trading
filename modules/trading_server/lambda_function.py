#!/usr/bin/env python3
"""Start the ingest node and trading servers, ensure health, then run run.sh via SSM."""

import os
import time
import boto3


def wait_for_status_ok(ec2_client, instance_ids, *, max_minutes=5, delay=10):
    """Poll describe_instance_status until both status checks pass for each instance."""
    deadline = time.time() + max_minutes * 60
    remaining = set(instance_ids)
    healthy = set()

    while remaining and time.time() < deadline:
        response = ec2_client.describe_instance_status(
            InstanceIds=list(remaining),
            IncludeAllInstances=True,
        )
        statuses = response["InstanceStatuses"]

        for status in statuses:
            instance_id = status["InstanceId"]
            sys_ok = status["SystemStatus"]["Status"] == "ok"
            inst_ok = status["InstanceStatus"]["Status"] == "ok"
            if sys_ok and inst_ok:
                healthy.add(instance_id)
                remaining.discard(instance_id)

        if remaining:
            time.sleep(delay)

    return list(healthy), list(remaining)


def ensure_healthy(ec2_client, instance_ids, *, max_retries=2, wait_minutes=5):
    """
    Ensure each instance passes both status checks.
    Performs up to max_retries stop/start cycles for unhealthy instances.
    """
    remaining = list(instance_ids)

    for attempt in range(max_retries + 1):
        ok_ids, bad_ids = wait_for_status_ok(
            ec2_client,
            remaining,
            max_minutes=wait_minutes,
        )
        if not bad_ids:
            return ok_ids

        if attempt == max_retries:
            raise RuntimeError(f"Instances {bad_ids} failed EC2 health checks")

        ec2_client.stop_instances(InstanceIds=bad_ids)
        ec2_client.get_waiter("instance_stopped").wait(InstanceIds=bad_ids)
        ec2_client.start_instances(InstanceIds=bad_ids)
        remaining = bad_ids


def lambda_handler(event, context):
    """Lambda entry point."""
    region = os.environ.get("AWS_REGION", "us-east-1")
    environment = os.environ.get("ENVIRONMENT", "qa")
    max_retries = int(os.environ.get("MAX_RETRIES", "2"))

    ingest_instance_name = os.environ.get("WEBSOCKET_INSTANCE_NAME")
    if not ingest_instance_name:
        ingest_instance_name = f"alpaca-websocket-ingest-{environment}"

    trade_prefix = os.environ.get("TRADING_SERVER_NAME_PREFIX")
    if not trade_prefix:
        trade_prefix = f"trading-server-{environment}-"
    trade_pattern = f"{trade_prefix}*"

    ec2 = boto3.client("ec2", region_name=region)
    ssm = boto3.client("ssm", region_name=region)

    ingest_filters = [
        {"Name": "tag:Name", "Values": [ingest_instance_name]},
        {"Name": "instance-state-name", "Values": ["pending", "running", "stopping", "stopped"]},
    ]
    ingest_reservations = ec2.describe_instances(Filters=ingest_filters)["Reservations"]
    ingest_instances = [inst for res in ingest_reservations for inst in res["Instances"]]
    if not ingest_instances:
        raise RuntimeError(f"No EC2 instances with tag Name={ingest_instance_name}")

    ingest_instance = (
        next((inst for inst in ingest_instances if inst["State"]["Name"] == "running"), None)
        or max(ingest_instances, key=lambda inst: inst["LaunchTime"])
    )
    ingest_id = ingest_instance["InstanceId"]

    if ingest_instance["State"]["Name"] != "running":
        ec2.start_instances(InstanceIds=[ingest_id])

    ensure_healthy(ec2, [ingest_id], max_retries=max_retries, wait_minutes=6)

    ingest_instance = ec2.describe_instances(Filters=ingest_filters)["Reservations"][0]["Instances"][0]
    nats_ip = ingest_instance.get("PublicIpAddress")
    if not nats_ip:
        raise RuntimeError("Ingest node does not have a public IP address")

    trade_filters = [{"Name": "tag:Name", "Values": [trade_pattern]}]
    trade_reservations = ec2.describe_instances(Filters=trade_filters)["Reservations"]
    if not trade_reservations:
        raise RuntimeError(f"No EC2 instances with tag Name={trade_pattern}")

    trade_instances = [
        inst
        for res in trade_reservations
        for inst in res["Instances"]
        if inst["State"]["Name"] not in ("terminated", "shutting-down", "terminating")
    ]
    if not trade_instances:
        raise RuntimeError("No non-terminated trading servers found")

    to_start = [inst["InstanceId"] for inst in trade_instances if inst["State"]["Name"] == "stopped"]
    if to_start:
        ec2.start_instances(InstanceIds=to_start)

    all_trade_ids = [inst["InstanceId"] for inst in trade_instances]
    healthy_trade_ids = ensure_healthy(
        ec2,
        all_trade_ids,
        max_retries=max_retries,
        wait_minutes=6,
    )

    script_path = os.path.join(os.getcwd(), "run.sh")
    with open(script_path, "r", encoding="utf-8") as script_file:
        script_lines = script_file.read().splitlines()

    commands = [f"export NATS_PUBLIC_IP={nats_ip}", *script_lines]

    response = ssm.send_command(
        InstanceIds=healthy_trade_ids,
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands},
        TimeoutSeconds=120,
    )
    command_id = response["Command"]["CommandId"]

    time.sleep(2)
    results = {}
    for instance_id in healthy_trade_ids:
        invocation = ssm.get_command_invocation(
            CommandId=command_id,
            InstanceId=instance_id,
        )
        results[instance_id] = {
            "Status": invocation["Status"],
            "Stdout": invocation.get("StandardOutputContent", ""),
            "Stderr": invocation.get("StandardErrorContent", ""),
        }

    return {"statusCode": 200, "body": results}
