import json
import orders
from auth_context import require_role


def handler(event, context):
    method = event.get("httpMethod", "")
    resource = event.get("resource", "")

    route = _ROUTES.get((method, resource))
    if not route:
        return {
            "statusCode": 404,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": "Endpoint no encontrado"}),
        }
    return route(event, context)


_ROUTES = {
    ("POST", "/v1/orders"): require_role("customer")(lambda e, c=None: orders.create_order(e)),
    ("GET", "/v1/orders"): require_role()(lambda e, c=None: orders.list_orders(e)),
    ("GET", "/v1/orders/{id}"): require_role()(lambda e, c=None: orders.get_order(e)),
    ("PUT", "/v1/orders/{id}/status"): require_role()(lambda e, c=None: orders.update_status(e)),
}
