"""Shared API, validation, lifecycle, and DynamoDB helpers.

The API Gateway handlers call these operations. Lambda accesses DynamoDB using
its execution role; client credentials are never used for table access.
"""
import base64
import json
import logging
import math
import os
from datetime import datetime, timezone
from decimal import Decimal
from urllib.parse import unquote
from uuid import uuid4

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError


LOG = logging.getLogger()
LOG.setLevel(logging.INFO)
TABLE_NAME = os.environ["ORDERS_TABLE"]
TABLE = boto3.resource("dynamodb").Table(TABLE_NAME)

# BUSINESS RULES
# Only these order status changes are accepted by the update operation.
ALLOWED_TRANSITIONS = {
    "PENDING": {"CONFIRMED", "CANCELLED"},
    "CONFIRMED": {"PROCESSING", "CANCELLED"},
    "PROCESSING": {"SHIPPED"},
    "SHIPPED": {"DELIVERED"},
    "DELIVERED": set(),
    "CANCELLED": set(),
}
STATUSES = set(ALLOWED_TRANSITIONS)


class ApiError(Exception):
    def __init__(self, status_code, code, message):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message


def response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Cache-Control": "no-store"},
        "body": json.dumps(payload, separators=(",", ":"), default=json_default),
    }


def json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    raise TypeError(f"Cannot JSON encode {type(value).__name__}")


# COMMON API RESPONSE AND ERROR HANDLING
# Convert expected validation/database errors into safe JSON HTTP responses.
def api_handler(event, operation):
    request_id = (event.get("requestContext") or {}).get("requestId", "unknown")
    try:
        result = operation(event)
        status, payload = result
        return response(status, payload)
    except ApiError as error:
        return response(error.status_code, {"error": {"code": error.code, "message": error.message}})
    except ClientError:
        LOG.exception("DynamoDB operation failed requestId=%s", request_id)
        return response(500, {"error": {"code": "INTERNAL_ERROR", "message": "The request could not be completed."}})
    except Exception:
        LOG.exception("Unhandled request failure requestId=%s", request_id)
        return response(500, {"error": {"code": "INTERNAL_ERROR", "message": "The request could not be completed."}})


def parse_json_body(event):
    body = event.get("body")
    if event.get("isBase64Encoded") and body:
        try:
            body = base64.b64decode(body, validate=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            raise ApiError(400, "VALIDATION_ERROR", "Request body must be valid UTF-8 JSON.")
    try:
        value = json.loads(body or "")
    except (json.JSONDecodeError, TypeError):
        raise ApiError(400, "VALIDATION_ERROR", "Request body must be valid JSON.")
    if not isinstance(value, dict):
        raise ApiError(400, "VALIDATION_ERROR", "Request body must be a JSON object.")
    return value


def required_string(value, field, max_length=128):
    if not isinstance(value, str) or not value.strip() or len(value.strip()) > max_length:
        raise ApiError(400, "VALIDATION_ERROR", f"'{field}' must be a non-empty string of at most {max_length} characters.")
    return value.strip()


# CREATE ORDER
# Validate input, generate an order ID, then write with DynamoDB PutItem.
def create_order(event):
    body = parse_json_body(event)
    customer_id = required_string(body.get("customerId"), "customerId")
    items = body.get("items")
    if not isinstance(items, list) or not 1 <= len(items) <= 50:
        raise ApiError(400, "VALIDATION_ERROR", "'items' must contain between 1 and 50 entries.")
    cleaned_items = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise ApiError(400, "VALIDATION_ERROR", f"items[{index}] must be an object.")
        product_id = required_string(item.get("productId"), f"items[{index}].productId")
        quantity = item.get("quantity")
        if isinstance(quantity, bool) or not isinstance(quantity, int) or quantity < 1 or quantity > 10000:
            raise ApiError(400, "VALIDATION_ERROR", f"items[{index}].quantity must be an integer from 1 to 10000.")
        cleaned_items.append({"productId": product_id, "quantity": quantity})
    amount = body.get("totalAmount")
    if isinstance(amount, bool) or not isinstance(amount, (int, float)) or not math.isfinite(amount) or amount <= 0:
        raise ApiError(400, "VALIDATION_ERROR", "'totalAmount' must be a finite positive number.")

    now = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    order_id = str(uuid4())
    order = {
        "orderId": order_id,
        "customerId": customer_id,
        "items": cleaned_items,
        "totalAmount": Decimal(str(amount)),
        "status": "PENDING",
        "createdAt": now,
        "updatedAt": now,
        "createdAtOrder": f"{now}#{order_id}",
        "version": 1,
    }
    TABLE.put_item(Item=order, ConditionExpression="attribute_not_exists(orderId)")
    LOG.info("order_created orderId=%s customerId=%s", order_id, customer_id)
    return 201, {"order": order}


def path_order_id(event):
    params = event.get("pathParameters") or {}
    return required_string(unquote(params.get("orderId", "")), "orderId", 64)


# GET ORDER BY ID
# Read one item using the DynamoDB table's orderId primary key.
def get_order(event):
    order_id = path_order_id(event)
    result = TABLE.get_item(Key={"orderId": order_id}, ConsistentRead=True)
    order = result.get("Item")
    if not order:
        raise ApiError(404, "ORDER_NOT_FOUND", "No order was found with that ID.")
    return 200, {"order": order}


# DELETE ORDER
# Permanently delete the order using orderId; return 404 if it does not exist.
def delete_order(event):
    order_id = path_order_id(event)
    try:
        TABLE.delete_item(
            Key={"orderId": order_id},
            ConditionExpression="attribute_exists(orderId)",
        )
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            raise ApiError(404, "ORDER_NOT_FOUND", "No order was found with that ID.")
        raise
    LOG.info("order_deleted orderId=%s", order_id)
    return 200, {"message": "Order deleted.", "orderId": order_id}


def encode_token(key):
    if not key:
        return None
    raw = json.dumps(key, separators=(",", ":"), default=json_default).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def decode_token(token):
    if not token:
        return None
    if not isinstance(token, str) or len(token) > 4096:
        raise ApiError(400, "VALIDATION_ERROR", "'nextToken' is invalid.")
    try:
        raw = base64.urlsafe_b64decode(token + "=" * (-len(token) % 4))
        value = json.loads(raw)
        if not isinstance(value, dict) or set(value) != {"orderId", "customerId", "createdAtOrder"}:
            raise ValueError("unexpected key shape")
        if any(not isinstance(item, str) for item in value.values()):
            raise ValueError("unexpected key values")
        return value
    except (ValueError, json.JSONDecodeError, UnicodeDecodeError):
        raise ApiError(400, "VALIDATION_ERROR", "'nextToken' is invalid.")


# LIST CUSTOMER ORDERS
# Query CustomerCreatedIndex by customerId instead of scanning the whole table.
def list_orders(event):
    params = event.get("queryStringParameters") or {}
    customer_id = required_string(params.get("customerId"), "customerId")
    try:
        limit = int(params.get("limit", "20"))
    except (TypeError, ValueError):
        raise ApiError(400, "VALIDATION_ERROR", "'limit' must be an integer from 1 to 100.")
    if not 1 <= limit <= 100:
        raise ApiError(400, "VALIDATION_ERROR", "'limit' must be an integer from 1 to 100.")
    query_args = {
        "IndexName": "CustomerCreatedIndex",
        "KeyConditionExpression": Key("customerId").eq(customer_id),
        "ScanIndexForward": False,
        "Limit": limit,
    }
    start_key = decode_token(params.get("nextToken"))
    if start_key:
        query_args["ExclusiveStartKey"] = start_key
    result = TABLE.query(**query_args)
    return 200, {"items": result.get("Items", []), "nextToken": encode_token(result.get("LastEvaluatedKey"))}


# UPDATE ORDER STATUS SAFELY
# Validate an allowed transition, then condition the write on current status/version.
def update_status(event):
    order_id = path_order_id(event)
    body = parse_json_body(event)
    expected = required_string(body.get("expectedStatus"), "expectedStatus", 32).upper()
    new_status = required_string(body.get("newStatus"), "newStatus", 32).upper()
    if expected not in STATUSES or new_status not in STATUSES:
        raise ApiError(400, "VALIDATION_ERROR", "Status must be one of: " + ", ".join(sorted(STATUSES)) + ".")
    expected_version = body.get("expectedVersion")
    if isinstance(expected_version, bool) or not isinstance(expected_version, int) or expected_version < 1:
        raise ApiError(400, "VALIDATION_ERROR", "'expectedVersion' must be a positive integer.")
    if new_status not in ALLOWED_TRANSITIONS[expected]:
        raise ApiError(400, "INVALID_TRANSITION", f"Transition from {expected} to {new_status} is not allowed.")
    now = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    try:
        result = TABLE.update_item(
            Key={"orderId": order_id},
            UpdateExpression="SET #status = :newStatus, updatedAt = :updatedAt, #version = #version + :one",
            ConditionExpression="attribute_exists(orderId) AND #status = :expectedStatus AND #version = :expectedVersion",
            ExpressionAttributeNames={"#status": "status", "#version": "version"},
            ExpressionAttributeValues={
                ":newStatus": new_status,
                ":expectedStatus": expected,
                ":expectedVersion": expected_version,
                ":updatedAt": now,
                ":one": 1,
            },
            ReturnValues="ALL_NEW",
        )
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            existing = TABLE.get_item(Key={"orderId": order_id}, ConsistentRead=True).get("Item")
            if not existing:
                raise ApiError(404, "ORDER_NOT_FOUND", "No order was found with that ID.")
            raise ApiError(409, "STATUS_CONFLICT", "The order changed; retrieve it and retry with its current status and version.")
        raise
    order = result["Attributes"]
    LOG.info("order_status_updated orderId=%s status=%s version=%s", order_id, new_status, order["version"])
    return 200, {"order": order}
