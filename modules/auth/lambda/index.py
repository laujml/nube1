import json
from middleware import require_role, decode_token, AuthError
import auth_service


def handler(event, context):
    if "methodArn" in event:
        return _authorize(event)

    method = event.get("httpMethod", "")

    # El recurso /auth usa ANY (autorizacion NONE) en vez de metodos
    # explicitos, asi que a diferencia de catalog/orders/reports (que
    # resuelven el preflight con una integracion MOCK en API Gateway) el
    # OPTIONS de CORS del frontend (P6) llega hasta aca y hay que
    # responderlo directamente en vez de dejarlo caer al 404 default.
    if method == "OPTIONS":
        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "Content-Type,Authorization",
                "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            },
            "body": "",
        }

    path = event.get("path", "")

    path_part = path.rstrip("/").split("/")[-1] if path.rstrip("/") else ""

    routes = {
        ("POST", "register"): _public_register,
        ("POST", "login"): _public_login,
        ("POST", "refresh"): _public_refresh,
        ("GET", "profile"): _protected_profile,
        ("POST", "logout"): _protected_logout,
    }

    route_key = (method, path_part)
    route = routes.get(route_key)
    if route:
        return route(event, context)

    return {
        "statusCode": 404,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({"error": "Endpoint no encontrado"}),
    }


def _parse_body(event: dict) -> dict:
    body = event.get("body")
    if body and isinstance(body, str):
        try:
            return json.loads(body)
        except json.JSONDecodeError:
            return {}
    return body if isinstance(body, dict) else {}


def _public_register(event, context=None):
    body = _parse_body(event)
    return auth_service.register(body)


def _public_login(event, context=None):
    body = _parse_body(event)
    return auth_service.login(body)


def _public_refresh(event, context=None):
    body = _parse_body(event)
    return auth_service.refresh(body)


@require_role("admin", "operator", "customer")
def _protected_profile(event, context=None):
    return auth_service.profile(event)


@require_role("admin", "operator", "customer")
def _protected_logout(event, context=None):
    return auth_service.logout(event)


def _authorize(event):
    """Lambda Authorizer (TOKEN) para API Gateway: valida el JWT de acceso
    y expone user_id/role/email en el contexto del request."""
    token = event.get("authorizationToken", "")
    if token.startswith("Bearer "):
        token = token.split(" ", 1)[1]

    try:
        payload = decode_token(token, "access")
    except AuthError:
        raise Exception("Unauthorized")

    return _build_policy(payload["sub"], "Allow", event["methodArn"], payload)


def _wildcard_resource(method_arn: str) -> str:
    arn_base, stage = method_arn.split("/")[0], method_arn.split("/")[1]
    return f"{arn_base}/{stage}/*"


def _build_policy(principal_id, effect, method_arn, payload=None):
    policy = {
        "principalId": principal_id,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": _wildcard_resource(method_arn),
                }
            ],
        },
    }
    if payload:
        policy["context"] = {
            "user_id": payload["sub"],
            "role": payload.get("role", ""),
            "email": payload.get("email", ""),
        }
    return policy
