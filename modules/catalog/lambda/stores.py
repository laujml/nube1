import time
import uuid
import dynamo
import jsonutil


def create_store(event) -> dict:
    body = jsonutil.parse_body(event)
    if not body.get("name"):
        return _err("El campo 'name' es requerido", 400)

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    store = {
        "store_id": str(uuid.uuid4()),
        "name": body["name"],
        "description": body.get("description", ""),
        "owner_id": event["_auth"]["user_id"],
        "created_at": now,
        "updated_at": now,
    }
    dynamo.stores_table.put_item(Item=store)
    return _ok(201, store)


def list_stores(event) -> dict:
    resp = dynamo.stores_table.scan()
    return _ok(200, {"stores": resp.get("Items", [])})


def get_store(event) -> dict:
    store_id = event["pathParameters"]["id"]
    resp = dynamo.stores_table.get_item(Key={"store_id": store_id})
    item = resp.get("Item")
    if not item:
        return _err("Tienda no encontrada", 404)
    return _ok(200, item)


def update_store(event) -> dict:
    store_id = event["pathParameters"]["id"]
    body = jsonutil.parse_body(event)
    resp = dynamo.stores_table.get_item(Key={"store_id": store_id})
    if not resp.get("Item"):
        return _err("Tienda no encontrada", 404)

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    dynamo.stores_table.update_item(
        Key={"store_id": store_id},
        UpdateExpression="SET #n = :n, description = :d, updated_at = :u",
        ExpressionAttributeNames={"#n": "name"},
        ExpressionAttributeValues={
            ":n": body.get("name", resp["Item"]["name"]),
            ":d": body.get("description", resp["Item"].get("description", "")),
            ":u": now,
        },
    )
    return _ok(200, {"message": "Tienda actualizada"})


def delete_store(event) -> dict:
    store_id = event["pathParameters"]["id"]
    dynamo.stores_table.delete_item(Key={"store_id": store_id})
    return _ok(200, {"message": "Tienda eliminada"})


def _ok(status_code: int, data) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": jsonutil.dumps(data),
    }


def _err(message: str, status_code: int) -> dict:
    return _ok(status_code, {"error": message})
