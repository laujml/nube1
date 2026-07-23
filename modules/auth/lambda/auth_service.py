import os
import json
import uuid
import time
import bcrypt
import dynamo
from middleware import generate_tokens, decode_token, AuthError

VALID_ROLES = {"admin", "operator", "customer"}


def register(body: dict) -> dict:
    required = ["email", "password", "name", "role"]
    missing = [f for f in required if not body.get(f)]
    if missing:
        return _err(f"Campos requeridos: {', '.join(missing)}", 400)

    role = body["role"].lower()
    if role not in VALID_ROLES:
        return _err(f"Rol invalido. Valores permitidos: {', '.join(VALID_ROLES)}", 400)

    if dynamo.get_user_by_email(body["email"]):
        return _err("El email ya esta registrado", 409)

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    user_id = str(uuid.uuid4())
    password_hash = bcrypt.hashpw(
        body["password"].encode("utf-8"), bcrypt.gensalt(rounds=12)
    ).decode("utf-8")

    user = {
        "user_id": user_id,
        "email": body["email"],
        "password_hash": password_hash,
        "name": body["name"],
        "role": role,
        "refresh_token": "",
        "created_at": now,
        "updated_at": now,
    }
    dynamo.create_user(user)

    tokens = generate_tokens(user_id, body["email"], role)
    dynamo.update_refresh_token(user_id, tokens["refresh_token"])

    return {
        "statusCode": 201,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "message": "Usuario registrado exitosamente",
            "user_id": user_id,
            "role": role,
            **tokens,
        }),
    }


def login(body: dict) -> dict:
    if not body.get("email") or not body.get("password"):
        return _err("Email y password son requeridos", 400)

    user = dynamo.get_user_by_email(body["email"])
    if not user:
        return _err("Credenciales invalidas", 401)

    if not bcrypt.checkpw(body["password"].encode("utf-8"), user["password_hash"].encode("utf-8")):
        return _err("Credenciales invalidas", 401)

    tokens = generate_tokens(user["user_id"], user["email"], user["role"])
    dynamo.update_refresh_token(user["user_id"], tokens["refresh_token"])

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "message": "Login exitoso",
            "user_id": user["user_id"],
            "role": user["role"],
            **tokens,
        }),
    }


def refresh(body: dict) -> dict:
    if not body.get("refresh_token"):
        return _err("refresh_token requerido", 400)

    try:
        payload = decode_token(body["refresh_token"], "refresh")
    except AuthError as e:
        return _err(e.message, e.status_code)

    user = dynamo.get_user_by_id(payload["sub"])
    if not user or user.get("refresh_token") != body["refresh_token"]:
        return _err("Refresh token invalido o revocado", 401)

    tokens = generate_tokens(user["user_id"], user["email"], user["role"])
    dynamo.update_refresh_token(user["user_id"], tokens["refresh_token"])

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "message": "Token renovado",
            **tokens,
        }),
    }


def profile(event: dict) -> dict:
    auth = event["_auth"]
    user = dynamo.get_user_by_id(auth["user_id"])
    if not user:
        return _err("Usuario no encontrado", 404)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "user_id": user["user_id"],
            "email": user["email"],
            "name": user["name"],
            "role": user["role"],
            "created_at": user["created_at"],
        }),
    }


def logout(event: dict) -> dict:
    auth = event["_auth"]
    dynamo.update_refresh_token(auth["user_id"], "")

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({"message": "Sesion cerrada exitosamente"}),
    }


def _err(message: str, status_code: int) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({"error": message}),
    }
