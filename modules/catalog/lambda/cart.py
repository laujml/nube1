import time
from decimal import Decimal
from boto3.dynamodb.conditions import Key
import dynamo
import jsonutil


def get_cart(event) -> dict:
    user_id = event["_auth"]["user_id"]
    resp = dynamo.cart_table.query(KeyConditionExpression=Key("user_id").eq(user_id))
    return _ok(200, {"items": resp.get("Items", [])})


def add_item(event) -> dict:
    user_id = event["_auth"]["user_id"]
    body = jsonutil.parse_body(event)
    product_id = body.get("product_id")
    quantity = int(body.get("quantity", 1))

    if not product_id or quantity < 1:
        return _err("product_id y quantity (>=1) son requeridos", 400)

    product = dynamo.products_table.get_item(Key={"product_id": product_id}).get("Item")
    if not product:
        return _err("Producto no encontrado", 404)
    if product.get("stock", 0) < quantity:
        return _err("Stock insuficiente", 409)

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    dynamo.cart_table.put_item(Item={
        "user_id": user_id,
        "product_id": product_id,
        "quantity": quantity,
        "unit_price": product["price"],
        "added_at": now,
    })
    return _ok(201, {"message": "Producto agregado al carrito"})


def update_item(event) -> dict:
    user_id = event["_auth"]["user_id"]
    product_id = event["pathParameters"]["productId"]
    body = jsonutil.parse_body(event)
    quantity = int(body.get("quantity", 0))

    if quantity < 1:
        return _err("quantity debe ser >= 1 (usa DELETE para quitar el item)", 400)

    existing = dynamo.cart_table.get_item(
        Key={"user_id": user_id, "product_id": product_id}
    ).get("Item")
    if not existing:
        return _err("El producto no esta en el carrito", 404)

    dynamo.cart_table.update_item(
        Key={"user_id": user_id, "product_id": product_id},
        UpdateExpression="SET quantity = :q",
        ExpressionAttributeValues={":q": quantity},
    )
    return _ok(200, {"message": "Cantidad actualizada"})


def remove_item(event) -> dict:
    user_id = event["_auth"]["user_id"]
    product_id = event["pathParameters"]["productId"]
    dynamo.cart_table.delete_item(Key={"user_id": user_id, "product_id": product_id})
    return _ok(200, {"message": "Producto quitado del carrito"})


def _ok(status_code: int, data) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": jsonutil.dumps(data),
    }


def _err(message: str, status_code: int) -> dict:
    return _ok(status_code, {"error": message})
