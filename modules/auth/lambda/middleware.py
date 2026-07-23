import os
import json
import time
import boto3
import jwt
from functools import wraps

secrets_client = boto3.client("secretsmanager")
_jwt_secret_cache = None


def _get_jwt_secret() -> str:
    global _jwt_secret_cache
    if _jwt_secret_cache is None:
        secret_arn = os.environ["JWT_SECRET_ARN"]
        resp = secrets_client.get_secret_value(SecretId=secret_arn)
        _jwt_secret_cache = resp["SecretString"]
    return _jwt_secret_cache


def generate_tokens(user_id: str, email: str, role: str) -> dict:
    secret = _get_jwt_secret()
    access_expiry = int(os.environ.get("JWT_ACCESS_EXPIRY_H", "1")) * 3600
    refresh_expiry = int(os.environ.get("JWT_REFRESH_EXPIRY_D", "7")) * 86400

    now = int(time.time())
    access_payload = {
        "sub": user_id,
        "email": email,
        "role": role,
        "type": "access",
        "iat": now,
        "exp": now + access_expiry,
    }
    refresh_payload = {
        "sub": user_id,
        "type": "refresh",
        "iat": now,
        "exp": now + refresh_expiry,
    }
    return {
        "access_token": jwt.encode(access_payload, secret, algorithm="HS256"),
        "refresh_token": jwt.encode(refresh_payload, secret, algorithm="HS256"),
        "expires_in": access_expiry,
    }


def decode_token(token: str, expected_type: str = "access") -> dict:
    secret = _get_jwt_secret()
    try:
        payload = jwt.decode(token, secret, algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise AuthError("Token expirado", 401)
    except jwt.InvalidTokenError:
        raise AuthError("Token invalido", 401)

    if payload.get("type") != expected_type:
        raise AuthError("Tipo de token invalido", 401)
    return payload


class AuthError(Exception):
    def __init__(self, message: str, status_code: int):
        self.message = message
        self.status_code = status_code


def require_role(*allowed_roles):
    def decorator(func):
        @wraps(func)
        def wrapper(event, context):
            auth_header = (event.get("headers") or {}).get("Authorization", "")
            if not auth_header.startswith("Bearer "):
                return _error_response("Token requerido", 401)

            token = auth_header.split(" ", 1)[1]
            try:
                payload = decode_token(token, "access")
            except AuthError as e:
                return _error_response(e.message, e.status_code)

            if allowed_roles and payload.get("role") not in allowed_roles:
                return _error_response("No autorizado para este recurso", 403)

            event["_auth"] = {
                "user_id": payload["sub"],
                "email": payload.get("email"),
                "role": payload.get("role"),
            }
            return func(event, context)
        return wrapper
    return decorator


def _error_response(message: str, status_code: int) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({"error": message}),
    }
