"""Auto-stop guardrail for the Splunk/Cribl dev stack.

Invoked on a fixed schedule (default hourly) by EventBridge Scheduler. Stops any
EC2 instance tagged ``Project = PROJECT_TAG`` whose uptime since its most recent
start exceeds ``AUTO_STOP_AFTER_HOURS``.

This replaces the previous Splunk-only, per-boot OS ``shutdown`` approach. A
tag-driven ``StopInstances`` API call covers every instance in the stack —
including the Windows Cribl Edge box, where an OS shutdown script never ran — and
cannot get "stuck on": even if a prior stop was missed, the next scheduled run
re-evaluates uptime and stops the instance. Stopping an instance that is already
stopping/stopped is a harmless no-op.
"""

import datetime
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")

PROJECT_TAG = os.environ.get("PROJECT_TAG", "splunk-aws")
AUTO_STOP_AFTER_HOURS = float(os.environ.get("AUTO_STOP_AFTER_HOURS", "48"))


def handler(event, context):  # noqa: ARG001 - signature fixed by Lambda runtime
    now = datetime.datetime.now(datetime.timezone.utc)

    paginator = ec2.get_paginator("describe_instances")
    pages = paginator.paginate(
        Filters=[
            {"Name": "tag:Project", "Values": [PROJECT_TAG]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )

    expired = []
    for page in pages:
        for reservation in page["Reservations"]:
            for instance in reservation["Instances"]:
                uptime_hours = (now - instance["LaunchTime"]).total_seconds() / 3600.0
                if uptime_hours >= AUTO_STOP_AFTER_HOURS:
                    expired.append(instance["InstanceId"])
                    logger.info(
                        "stopping %s (uptime %.1fh >= %.1fh)",
                        instance["InstanceId"],
                        uptime_hours,
                        AUTO_STOP_AFTER_HOURS,
                    )

    if expired:
        ec2.stop_instances(InstanceIds=expired)
    else:
        logger.info(
            "no Project=%s instances exceed %.1fh", PROJECT_TAG, AUTO_STOP_AFTER_HOURS
        )

    return {"stopped": expired, "threshold_hours": AUTO_STOP_AFTER_HOURS}
