"""Process post-create background events from the OrderFlow SQS queue."""
import json
import logging

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)


def handler(event, context):
    # SQS EVENT WORKER
    # Lambda retries failed records; repeated failures are moved to the queue's DLQ.
    for record in event.get("Records", []):
        message = json.loads(record["body"])
        if message.get("eventType") != "ORDER_CREATED" or not message.get("orderId"):
            raise ValueError("Invalid order-created event")

        # Placeholder background action: record a compact audit log entry.
        # Add notification or other post-create work here when needed.
        LOG.info(
            "order_created_event_processed messageId=%s orderId=%s",
            record.get("messageId", "unknown"),
            message["orderId"],
        )

    return {"batchItemFailures": []}
