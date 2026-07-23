import os
import re
from decimal import Decimal
from boto3.dynamodb.conditions import Attr
import dynamo
import jsonutil

_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# Estados de pedido que no cuentan como venta real para total_sales_amount
# (el pedido sigue contando en total_orders, solo se excluye del monto).
_NON_SALE_STATUSES = {"cancelled"}


def _scan_all(table, **kwargs) -> list:
    """Scan completo siguiendo LastEvaluatedKey: un reporte con paginas a medias
    seria un reporte incorrecto, no solo lento."""
    items = []
    while True:
        resp = table.scan(**kwargs)
        items.extend(resp.get("Items", []))
        last_key = resp.get("LastEvaluatedKey")
        if not last_key:
            return items
        kwargs["ExclusiveStartKey"] = last_key


def _parse_date_range(params: dict):
    date_from = (params or {}).get("from", "")
    date_to = (params or {}).get("to", "")
    if not _DATE_RE.match(date_from) or not _DATE_RE.match(date_to):
        return None, None, "Parametros 'from' y 'to' son requeridos, formato YYYY-MM-DD"
    if date_from > date_to:
        return None, None, "'from' no puede ser posterior a 'to'"
    return f"{date_from}T00:00:00Z", f"{date_to}T23:59:59Z", None


def sales_report(event) -> dict:
    params = event.get("queryStringParameters") or {}
    start, end, error = _parse_date_range(params)
    if error:
        return _err(error, 400)

    orders = _scan_all(
        dynamo.orders_table,
        FilterExpression=Attr("created_at").between(start, end),
    )

    total_orders = len(orders)
    total_sales_amount = Decimal(0)
    orders_by_status = {}
    for order in orders:
        status = order.get("status", "unknown")
        orders_by_status[status] = orders_by_status.get(status, 0) + 1
        if status not in _NON_SALE_STATUSES:
            total_sales_amount += order.get("total_amount", 0)

    return _ok(200, {
        "from": params["from"],
        "to": params["to"],
        "total_orders": total_orders,
        "total_sales_amount": total_sales_amount,
        "orders_by_status": orders_by_status,
    })


def inventory_report(event) -> dict:
    threshold = int(os.environ.get("LOW_STOCK_THRESHOLD", "10"))
    products = _scan_all(dynamo.products_table)

    total_stock = sum(p.get("stock", 0) for p in products)
    low_stock = [
        {
            "product_id": p.get("product_id"),
            "name": p.get("name"),
            "store_id": p.get("store_id"),
            "stock": p.get("stock", 0),
        }
        for p in products
        if p.get("stock", 0) <= threshold
    ]

    return _ok(200, {
        "low_stock_threshold": threshold,
        "total_products": len(products),
        "total_stock": total_stock,
        "low_stock_products": low_stock,
    })


def audit_report(event) -> dict:
    params = event.get("queryStringParameters") or {}
    start, end, error = _parse_date_range(params)
    if error:
        return _err(error, 400)

    events = _scan_all(
        dynamo.audit_table,
        FilterExpression=Attr("fecha").between(start, end),
    )
    events.sort(key=lambda e: e.get("fecha", ""))

    return _ok(200, {
        "from": params["from"],
        "to": params["to"],
        "total_events": len(events),
        "events": events,
    })


def _ok(status_code: int, data) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": jsonutil.dumps(data),
    }


def _err(message: str, status_code: int) -> dict:
    return _ok(status_code, {"error": message})
