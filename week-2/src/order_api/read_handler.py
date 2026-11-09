# READ/LIST LAMBDA HANDLER
# GET /orders/{orderId} retrieves one order; GET /orders lists customer orders.
from .common import api_handler, get_order, list_orders


def handler(event, context):
    if event.get("httpMethod") == "GET" and (event.get("pathParameters") or {}).get("orderId"):
        return api_handler(event, get_order)
    return api_handler(event, list_orders)
