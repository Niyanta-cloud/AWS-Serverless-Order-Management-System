from .common import api_handler, update_status


def handler(event, context):
    return api_handler(event, update_status)
