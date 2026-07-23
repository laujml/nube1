import os
import boto3

dynamodb = boto3.resource("dynamodb")

orders_table = dynamodb.Table(os.environ["ORDERS_TABLE"])
products_table = dynamodb.Table(os.environ["PRODUCTS_TABLE"])
audit_table = dynamodb.Table(os.environ["AUDIT_TABLE"])
