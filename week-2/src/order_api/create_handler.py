# CREATE LAMBDA HANDLER
# API Gateway sends POST /orders here; shared code validates and stores the order.
from .common import api_handler, create_order


def handler(event, context):
    return api_handler(event, create_order)
