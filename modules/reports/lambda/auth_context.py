import json
from functools import wraps

# El Lambda Authorizer JWT (modulo auth) ya valido el token antes de invocar
# esta Lambda, e inyecta user_id/role/email en requestContext.authorizer.
# Mismo patron que P3/P4/P5 para no volver a decodificar el JWT.


def get_auth(event: dict) -> dict:
    authorizer = (event.get("requestContext") or {}).get("authorizer") or {}
    return {
        "user_id": authorizer.get("user_id"),
        "role": authorizer.get("role"),
        "email": authorizer.get("email"),
    }


def require_role(*allowed_roles):
    def decorator(func):
        @wraps(func)
        def wrapper(event, context):
            auth = get_auth(event)
            if not auth.get("user_id"):
                return _error_response("Token requerido", 401)
            if allowed_roles and auth.get("role") not in allowed_roles:
                return _error_response("No autorizado para este recurso", 403)
            event["_auth"] = auth
            return func(event, context)
        return wrapper
    return decorator


def _error_response(message: str, status_code: int) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({"error": message}),
    }
