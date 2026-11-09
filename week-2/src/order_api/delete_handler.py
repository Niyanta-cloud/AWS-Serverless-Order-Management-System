# DELETE LAMBDA HANDLER
# API Gateway sends DELETE /orders/{orderId} here to remove the DynamoDB item.
from .common import api_handler, delete_order


def handler(event, context):
    return api_handler(event, delete_order)
