import time
import uuid
from decimal import Decimal
from boto3.dynamodb.conditions import Key
import dynamo
import jsonutil


def create_product(event) -> dict:
    body = jsonutil.parse_body(event)
    required = ["name", "price", "store_id"]
    missing = [f for f in required if body.get(f) in (None, "")]
    if missing:
        return _err(f"Campos requeridos: {', '.join(missing)}", 400)

    if not dynamo.stores_table.get_item(Key={"store_id": body["store_id"]}).get("Item"):
        return _err("La tienda indicada no existe", 404)

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    product = {
        "product_id": str(uuid.uuid4()),
        "store_id": body["store_id"],
        "name": body["name"],
        "description": body.get("description", ""),
        "price": Decimal(str(body["price"])),
        "stock": int(body.get("stock", 0)),
        "category": body.get("category", ""),
        "created_at": now,
        "updated_at": now,
    }
    dynamo.products_table.put_item(Item=product)
    return _ok(201, product)


def list_products(event) -> dict:
    store_id = (event.get("queryStringParameters") or {}).get("store_id")
    if store_id:
        resp = dynamo.products_table.query(
            IndexName="store_id-index",
            KeyConditionExpression=Key("store_id").eq(store_id),
        )
    else:
        resp = dynamo.products_table.scan()
    return _ok(200, {"products": resp.get("Items", [])})


def get_product(event) -> dict:
    product_id = event["pathParameters"]["id"]
    resp = dynamo.products_table.get_item(Key={"product_id": product_id})
    item = resp.get("Item")
    if not item:
        return _err("Producto no encontrado", 404)
    return _ok(200, item)


def update_product(event) -> dict:
    product_id = event["pathParameters"]["id"]
    resp = dynamo.products_table.get_item(Key={"product_id": product_id})
    current = resp.get("Item")
    if not current:
        return _err("Producto no encontrado", 404)

    body = jsonutil.parse_body(event)
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    price = Decimal(str(body["price"])) if "price" in body else current["price"]
    stock = int(body["stock"]) if "stock" in body else current.get("stock", 0)

    dynamo.products_table.update_item(
        Key={"product_id": product_id},
        UpdateExpression="SET #n = :n, description = :d, price = :p, stock = :s, category = :c, updated_at = :u",
        ExpressionAttributeNames={"#n": "name"},
        ExpressionAttributeValues={
            ":n": body.get("name", current["name"]),
            ":d": body.get("description", current.get("description", "")),
            ":p": price,
            ":s": stock,
            ":c": body.get("category", current.get("category", "")),
            ":u": now,
        },
    )
    return _ok(200, {"message": "Producto actualizado"})


def delete_product(event) -> dict:
    product_id = event["pathParameters"]["id"]
    dynamo.products_table.delete_item(Key={"product_id": product_id})
    return _ok(200, {"message": "Producto eliminado"})


def _ok(status_code: int, data) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": jsonutil.dumps(data),
    }


def _err(message: str, status_code: int) -> dict:
    return _ok(status_code, {"error": message})
