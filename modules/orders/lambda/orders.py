import time
import uuid
from boto3.dynamodb.conditions import Key
import dynamo
import jsonutil
import events

# Estados del pedido y transiciones permitidas.
VALID_TRANSITIONS = {
    "pending": {"confirmed", "cancelled"},
    "confirmed": {"preparing", "cancelled"},
    "preparing": {"shipped", "cancelled"},
    "shipped": {"delivered"},
    "delivered": set(),
    "cancelled": set(),
}


def create_order(event) -> dict:
    user_id = event["_auth"]["user_id"]

    cart_items = dynamo.cart_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id)
    ).get("Items", [])
    if not cart_items:
        return _err("El carrito esta vacio", 400)

    order_items = []
    total_amount = 0
    for cart_item in cart_items:
        product_id = cart_item["product_id"]
        quantity = cart_item["quantity"]
        product = dynamo.products_table.get_item(Key={"product_id": product_id}).get("Item")
        if not product:
            return _err(f"El producto {product_id} ya no existe", 404)
        if product.get("stock", 0) < quantity:
            return _err(f"Stock insuficiente para {product.get('name', product_id)}", 409)

        unit_price = product["price"]
        order_items.append({
            "product_id": product_id,
            "store_id": product.get("store_id"),
            "name": product.get("name"),
            "quantity": quantity,
            "unit_price": unit_price,
        })
        total_amount += unit_price * quantity

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    order = {
        "order_id": str(uuid.uuid4()),
        "user_id": user_id,
        "items": order_items,
        "total_amount": total_amount,
        "status": "pending",
        "status_history": [{"status": "pending", "changed_at": now, "changed_by": user_id}],
        "created_at": now,
        "updated_at": now,
    }
    dynamo.orders_table.put_item(Item=order)

    for cart_item in cart_items:
        dynamo.cart_table.delete_item(
            Key={"user_id": user_id, "product_id": cart_item["product_id"]}
        )

    events.publish("OrderCreated", {
        "order_id": order["order_id"],
        "user_id": user_id,
        "customer_email": event["_auth"].get("email"),
        "items": order_items,
        "total_amount": total_amount,
    })

    return _ok(201, order)


def list_orders(event) -> dict:
    auth = event["_auth"]
    status_filter = (event.get("queryStringParameters") or {}).get("status")

    if auth["role"] == "customer":
        items = dynamo.orders_table.query(
            IndexName="user_id-index",
            KeyConditionExpression=Key("user_id").eq(auth["user_id"]),
        ).get("Items", [])
    else:
        items = dynamo.orders_table.scan().get("Items", [])

    if status_filter:
        items = [i for i in items if i.get("status") == status_filter]

    return _ok(200, {"orders": items})


def get_order(event) -> dict:
    auth = event["_auth"]
    order_id = event["pathParameters"]["id"]
    order = dynamo.orders_table.get_item(Key={"order_id": order_id}).get("Item")
    if not order:
        return _err("Pedido no encontrado", 404)
    if auth["role"] == "customer" and order["user_id"] != auth["user_id"]:
        return _err("No autorizado para ver este pedido", 403)
    return _ok(200, order)


def update_status(event) -> dict:
    auth = event["_auth"]
    order_id = event["pathParameters"]["id"]
    body = jsonutil.parse_body(event)
    new_status = str(body.get("status", "")).lower()

    if new_status not in VALID_TRANSITIONS:
        return _err(f"Estado invalido: {new_status}", 400)

    order = dynamo.orders_table.get_item(Key={"order_id": order_id}).get("Item")
    if not order:
        return _err("Pedido no encontrado", 404)

    current_status = order["status"]
    if new_status not in VALID_TRANSITIONS[current_status]:
        return _err(f"Transicion de estado invalida: {current_status} -> {new_status}", 409)

    if auth["role"] == "customer":
        if order["user_id"] != auth["user_id"]:
            return _err("No autorizado para modificar este pedido", 403)
        if new_status != "cancelled":
            return _err("El cliente solo puede cancelar su pedido", 403)

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    history_entry = {"status": new_status, "changed_at": now, "changed_by": auth["user_id"]}
    dynamo.orders_table.update_item(
        Key={"order_id": order_id},
        UpdateExpression="SET #s = :s, updated_at = :u, status_history = list_append(status_history, :h)",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":s": new_status,
            ":u": now,
            ":h": [history_entry],
        },
    )

    events.publish("OrderStatusChanged", {
        "order_id": order_id,
        "user_id": order["user_id"],
        "previous_status": current_status,
        "new_status": new_status,
        "changed_by": auth["user_id"],
    })

    return _ok(200, {"message": "Estado del pedido actualizado", "status": new_status})


def _ok(status_code: int, data) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": jsonutil.dumps(data),
    }


def _err(message: str, status_code: int) -> dict:
    return _ok(status_code, {"error": message})
