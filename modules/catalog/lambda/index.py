import json
import stores
import products
import cart
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


def _public(func):
    def wrapper(event, context=None):
        return func(event)
    return wrapper


_ROUTES = {
    ("GET", "/v1/stores"): _public(stores.list_stores),
    ("POST", "/v1/stores"): require_role("admin")(lambda e, c=None: stores.create_store(e)),
    ("GET", "/v1/stores/{id}"): _public(stores.get_store),
    ("PUT", "/v1/stores/{id}"): require_role("admin")(lambda e, c=None: stores.update_store(e)),
    ("DELETE", "/v1/stores/{id}"): require_role("admin")(lambda e, c=None: stores.delete_store(e)),

    ("GET", "/v1/products"): _public(products.list_products),
    ("POST", "/v1/products"): require_role("admin", "operator")(lambda e, c=None: products.create_product(e)),
    ("GET", "/v1/products/{id}"): _public(products.get_product),
    ("PUT", "/v1/products/{id}"): require_role("admin", "operator")(lambda e, c=None: products.update_product(e)),
    ("DELETE", "/v1/products/{id}"): require_role("admin")(lambda e, c=None: products.delete_product(e)),

    ("GET", "/v1/cart"): require_role("customer")(lambda e, c=None: cart.get_cart(e)),
    ("POST", "/v1/cart"): require_role("customer")(lambda e, c=None: cart.add_item(e)),
    ("PUT", "/v1/cart/{productId}"): require_role("customer")(lambda e, c=None: cart.update_item(e)),
    ("DELETE", "/v1/cart/{productId}"): require_role("customer")(lambda e, c=None: cart.remove_item(e)),
}
