"""Uptime sweep: stop tagged EC2 instances that have run too long.

Invoked hourly by EventBridge Scheduler. Stops every instance that:
  * carries the configured Project tag (PROJECT_TAG env var), and
  * has been running longer than MAX_RUNTIME_HOURS (measured from LaunchTime).

LaunchTime resets whenever a stopped instance is started, so "uptime" here is
time since the most recent start — exactly the lease semantics we want. This
sweep is the backstop that catches instances started outside the summon
workflow (console, CLI, autoscaling mishaps); the summon workflow additionally
creates a friendly one-time stop schedule at start time.
"""

import datetime
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

PROJECT_TAG = os.environ["PROJECT_TAG"]
MAX_RUNTIME_HOURS = float(os.environ["MAX_RUNTIME_HOURS"])


def handler(event, context):
    ec2 = boto3.client("ec2")
    now = datetime.datetime.now(datetime.timezone.utc)
    cutoff = now - datetime.timedelta(hours=MAX_RUNTIME_HOURS)

    paginator = ec2.get_paginator("describe_instances")
    pages = paginator.paginate(
        Filters=[
            {"Name": "tag:Project", "Values": [PROJECT_TAG]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )

    overdue = []
    for page in pages:
        for reservation in page["Reservations"]:
            for instance in reservation["Instances"]:
                if instance["LaunchTime"] <= cutoff:
                    uptime_h = (now - instance["LaunchTime"]).total_seconds() / 3600
                    logger.info(
                        "Stopping %s (up %.1fh, limit %.0fh)",
                        instance["InstanceId"],
                        uptime_h,
                        MAX_RUNTIME_HOURS,
                    )
                    overdue.append(instance["InstanceId"])

    if overdue:
        ec2.stop_instances(InstanceIds=overdue)
    else:
        logger.info("No instance over the %.0fh limit", MAX_RUNTIME_HOURS)

    return {"stopped": overdue}
