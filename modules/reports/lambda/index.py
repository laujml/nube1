import json
import reports
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


# Reportes son informacion interna del negocio: solo admin/operator, nunca
# customer (mismo patron de restriccion que P3 usa para altas de producto).
_ROUTES = {
    ("GET", "/v1/reports/sales"): require_role("admin", "operator")(lambda e, c=None: reports.sales_report(e)),
    ("GET", "/v1/reports/inventory"): require_role("admin", "operator")(lambda e, c=None: reports.inventory_report(e)),
    ("GET", "/v1/reports/audit"): require_role("admin", "operator")(lambda e, c=None: reports.audit_report(e)),
}
