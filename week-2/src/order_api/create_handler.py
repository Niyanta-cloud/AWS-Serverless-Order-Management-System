from .common import api_handler, create_order


def handler(event, context):
    return api_handler(event, create_order)
