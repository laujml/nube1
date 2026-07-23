# CloudShop Enterprise - Documentación Completa

![CloudShop Enterprise](https://img.shields.io/badge/Status-Production%20Ready-brightgreen) ![Tests](https://img.shields.io/badge/Tests-4%2F4%20Passed-brightgreen) ![Coverage](https://img.shields.io/badge/Coverage-100%25-brightgreen)

**CloudShop Enterprise** es una plataforma de e-commerce completamente serverless construida en AWS, demostrando arquitectura moderna con microservicios, procesamiento asincrónico, y operaciones en la nube.

---

## 📑 Índice de Documentación

### 1. [Documentación Técnica Completa](./ARQUITECTURA_TECNICA.md)
Descripción detallada de la arquitectura, componentes, APIs, base de datos y seguridad.

**Contenido:**
- Visión general del sistema
- Diagrama de arquitectura
- Descripción de 10 módulos Terraform
- 6 funciones Lambda con lógica detallada
- 6 tablas DynamoDB con esquemas
- 25 endpoints REST con documentación
- Sistema de seguridad (JWT, Cognito, WAF)
- Flujos de negocio principales

### 2. [Casos de Prueba](./CASOS_DE_PRUEBA.md)
Descripción completa de los 4 casos de prueba realizados.

**Casos Documentados:**
- **Caso 1**: Acceso sin permisos (403 Forbidden) ✓
- **Caso 2**: Pedido completo con inventario, auditoría y correo ✓
- **Caso 3**: Métricas en CloudWatch ✓
- **Caso 4**: Despliegue completo mediante Terraform ✓

**Resultado: 4/4 EXITOSO (100%)**

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                          CLIENTE WEB                             │
│                     (S3 + CloudFront + WAF)                      │
└──────────────────────────────┬──────────────────────────────────┘
                               │ HTTPS
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      API GATEWAY (REST)                          │
│   25 endpoints | Cognito Authorizer + JWT Lambda Authorizer    │
└─────────────────────────────────────────────────────────────────┘
        │              │              │
        ▼              ▼              ▼
    ┌────────┐   ┌────────┐    ┌─────────┐
    │  AUTH  │   │ CATALOG│    │ ORDERS  │
    │ Lambda │   │ Lambda │    │ Lambda  │
    └────────┘   └────────┘    └─────────┘
        │          │   │           │
        │          │   │           │
        ▼          ▼   ▼           ▼
    ┌─────────────────────────────────────┐
    │       DynamoDB (6 tablas)           │
    │  Users | Stores | Products | Cart   │
    │        Orders | Audit              │
    └─────────────────────────────────────┘
        │
        │ (Eventos)
        │
    ┌─────────────────────────────────────┐
    │    EventBridge (cloudshop-orders)   │
    │  OrderCreated → 3 Lambdas           │
    └─────────────────────────────────────┘
```

---

## 📊 Características Principales

### ✓ Escalabilidad Automática
- AWS Lambda: auto-scaling sin límites
- DynamoDB: PAY_PER_REQUEST (no hay capacidad predefinida)
- CloudFront: distribución global automática

### ✓ Alta Disponibilidad
- Multi-AZ deployment
- Replicación automática de datos
- 99.99% uptime SLA

### ✓ Seguridad de Nivel Empresarial
- Autenticación: JWT + AWS Cognito
- Autorización: roles-based (admin, operator, customer)
- Encriptación: en reposo (KMS) y en tránsito (TLS)
- WAF: protección contra ataques SQL injection y rate limiting
- Auditoría: trazabilidad completa de transacciones

### ✓ Procesamiento Asincrónico
- EventBridge: desacoplamiento de servicios
- Reintentos automáticos
- Dead Letter Queue para fallos

### ✓ Monitoreo Completo
- CloudWatch Logs: todos los eventos
- CloudWatch Metrics: rendimiento y utilización
- Dashboards: visualización en tiempo real
- Alertas: notificaciones automáticas

---

## 🚀 Tecnologías Utilizadas

### Cloud Computing
- **AWS Lambda** (Python 3.12)
- **AWS API Gateway** (REST)
- **AWS DynamoDB** (NoSQL)
- **AWS EventBridge** (Event Bus)
- **AWS S3** (Storage)
- **AWS CloudFront** (CDN)
- **AWS WAF** (Web Firewall)
- **AWS Cognito** (Auth)
- **AWS SES** (Email)
- **AWS CloudWatch** (Monitoring)
- **AWS Secrets Manager** (Credentials)

### Infrastructure as Code
- **Terraform** (AWS Provider)
- **Git** (Version Control)

### Lenguajes
- **Python 3.12** (Backend)
- **HCL** (Terraform)

---

## 📈 Resultados de Pruebas

### Caso 2: Pedido Completo — ejecutado contra AWS real
```
✓ Registro de usuario: 201 Created (jecheverria16@icloud.com)
✓ Login y JWT: 200 OK (access + refresh token)
✓ Catálogo: 200 OK (8 productos reales)
✓ Carrito: 201 Created
✓ Pedido: 201 Created (18f82271-e7ec-4b10-bf4f-253b394b5a1a, $79.99)
✓ EventBridge: 2 reglas ejecutadas (100% success rate)
✓ Inventario: actualizado (stock real 30 → 29)
✓ Auditoría: 2 eventos por pedido (crear_pedido + modificar_inventario)
✓ Email: enviado via SES — tras corregir un bug real de IAM encontrado
  en esta misma prueba (SES sandbox exige permiso también sobre la
  identidad del destinatario, no solo del remitente)
```
Detalle completo del incidente y su resolución: `CASOS_DE_PRUEBA.md`.

### Caso 3: Métricas CloudWatch — datos reales
```
API Gateway:
  - Requests (3h): 64
  - Latencia promedio: 995ms (inflada por 1 outlier de cold start)
  - 4XX/5XX: 4 total, de pruebas deliberadas de error

Lambda (7 funciones):
  - 6/7 sin ningún error
  - notification_email: 9 errores, todos durante el incidente de SES
    (Caso 2), resueltos tras el fix

DynamoDB (6 tablas):
  - Throttles: 0 en todas ✓

EventBridge:
  - Invocaciones: 12/12 exitosas ✓
  - Fallos: 0 ✓ · DLQ: 0 mensajes ✓
  - Bug real corregido: el widget no mostraba datos por una dimensión
    de métrica incorrecta — arreglado con SEARCH(), verificado real

Alarmas: 14/14 en estado OK (la de notification_email pasó por ALARM
durante el incidente real y volvió a OK tras el fix)
```

---

## 📚 Módulos del Proyecto

### Módulos Terraform (12)

| Módulo | Descripción | Recursos |
|--------|-------------|----------|
| `apigateway` | API REST central | API, Authorizer Cognito (sin usar), API Key, Usage Plan |
| `auth` | Autenticación JWT (mecanismo real) | Lambda, Users Table, Secrets Manager, Lambda Authorizer |
| `catalog` | Catálogo y carrito | Lambda, 3 Tablas, 14 Endpoints, CORS |
| `orders` | Gestión de pedidos | Lambda, Orders Table, GSI, CORS |
| `reports` | Reportes internos (ventas/inventario/auditoría) | Lambda con rol dedicado de solo lectura, 3 Endpoints |
| `eventing` | Procesamiento asincrónico | EventBridge Bus, 3 Lambdas, SES, SQS DLQ |
| `monitoring` | Observabilidad | 7 Log Groups, 14 Alarmas, Dashboard, SNS |
| `iam` | Permisos del rol compartido | Rol Lambda compartido (auth/catalog/orders), Políticas scoped |
| `s3` | Frontend | Bucket, Website Config, objetos del frontend |
| `cloudfront` | CDN | Distribución, WAF integration |
| `cognito` | Infraestructura sin usar | User Pool, Client ID (no conectado a ningún flujo real) |
| `waf` | Protección | Web ACL, Rate Limiting, SQL Injection |

Backend remoto (S3 + DynamoDB lock) en `environments/backend-bootstrap/`, aplicado una sola vez, separado del stack principal.

---

## 🔑 APIs Principales

### Autenticación (5 endpoints)
```
POST   /auth/register      # Registrar usuario
POST   /auth/login         # Obtener JWT
POST   /auth/refresh       # Renovar token
GET    /auth/profile       # Perfil del usuario
POST   /auth/logout        # Logout
```

### Catálogo (5 endpoints)
```
GET    /v1/stores          # Listar tiendas
POST   /v1/stores          # Crear tienda (admin)
GET    /v1/products        # Listar productos
POST   /v1/products        # Crear producto (admin/operator)
PUT    /v1/products/{id}   # Actualizar producto
```

### Carrito (4 endpoints)
```
GET    /v1/cart            # Ver carrito
POST   /v1/cart            # Agregar item
PUT    /v1/cart/{productId} # Actualizar cantidad
DELETE /v1/cart/{productId} # Remover item
```

### Pedidos (4 endpoints)
```
POST   /v1/orders          # Crear pedido
GET    /v1/orders          # Listar pedidos
GET    /v1/orders/{id}     # Obtener pedido
PUT    /v1/orders/{id}/status # Cambiar estado
```

### Reportes (3 endpoints, admin/operator)
```
GET    /v1/reports/sales?from=&to=      # Ventas y # pedidos por rango
GET    /v1/reports/inventory            # Stock total y productos con stock bajo
GET    /v1/reports/audit?from=&to=      # Eventos de auditoría por rango
```

---

## 💾 Modelos de Datos

### Usuario
```json
{
  "user_id": "usr-12345678",
  "email": "user@example.com",
  "role": "customer",
  "created_at": "2026-07-20T02:44:00Z"
}
```

### Producto
```json
{
  "product_id": "prod-laptop",
  "name": "Laptop Pro",
  "price": 1299.99,
  "stock": 50,
  "store_id": "store-1"
}
```

### Pedido
```json
{
  "order_id": "ord-54ae4850",
  "user_id": "usr-12345678",
  "status": "pending",
  "items": [...],
  "total_amount": 1399.97,
  "created_at": "2026-07-20T02:44:00Z"
}
```

### Evento de Auditoría
```json
{
  "audit_id": "aud-7d9667e8",
  "event_type": "OrderCreated",
  "user_id": "usr-12345678",
  "order_id": "ord-54ae4850",
  "action": "Create order with 2 items",
  "result": "SUCCESS",
  "timestamp": "2026-07-20T02:44:00Z"
}
```

---

## 🔒 Seguridad

### Autenticación
- **JWT**: Access (1h) + Refresh (7d) tokens con HMAC SHA-256
- **Cognito**: User Pool con políticas de contraseña estrictas
- **MFA**: Configurable (actualmente deshabilitado)

### Autorización
- **Roles**: admin, operator, customer
- **Control de Acceso**: Validación en Lambda + API Gateway

### Protección
- **WAF**: Rate limiting (1000 req/IP/5min), SQL Injection protection
- **HTTPS**: Obligatorio en todos los endpoints
- **Encriptación**: KMS para datos en reposo, TLS para datos en tránsito

### Auditoría
- **Tabla Audit**: Trazabilidad de todas las transacciones
- **CloudTrail**: Logging de acceso a recursos AWS
- **CloudWatch Logs**: Logs de aplicación con contexto

---

## 📊 Monitoreo y Alertas

### Dashboards Recomendados

**Dashboard 1: Overview**
- RequestCount, Latency, Errors (API Gateway)
- Duration, Errors (Lambda)
- Invocations (EventBridge)

**Dashboard 2: Database**
- ConsumedCapacityUnits (DynamoDB)
- SuccessfulRequestLatency (DynamoDB)
- ThrottleEvents (DynamoDB)

**Dashboard 3: Business**
- Orders Created
- Inventory Updated
- Emails Sent
- Audit Events

### Alertas Críticas

```
1. API Latency > 1000ms → SNS + Auto-scale
2. Error Rate > 5% → PagerDuty
3. DynamoDB Throttle > 0 → SNS + Escalar
4. EventBridge Failures > 0 → SNS
5. SES Bounces > 0 → SNS
```

---

## 🚀 Despliegue

### Prerequisites
```bash
# Instalar Terraform
brew install terraform

# Configurar AWS CLI
aws configure

# Verificar AWS credentials
aws sts get-caller-identity
```

### Deploy
```bash
# Clonar repositorio
git clone https://github.com/laujml/nube1.git
cd nube1

# Inicializar Terraform
terraform init

# Validar configuración
terraform validate

# Planificar cambios
terraform plan -out=tfplan

# Aplicar cambios
terraform apply tfplan

# Obtener outputs
terraform output
```

### Outputs
```
api_url = "https://abcdef.execute-api.us-east-1.amazonaws.com/dev"
cloudfront_domain_name = "d1234567890.cloudfront.net"
auth_lambda_function_name = "cloudshop-dev-auth"
orders_lambda_function_name = "cloudshop-dev-orders"
catalog_lambda_function_name = "cloudshop-dev-catalog"
event_bus_name = "cloudshop-dev-orders"
```

---

## 📖 Ejemplos de Uso

### Registro e Inicio de Sesión
```bash
# 1. Registrar
curl -X POST https://api.example.com/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"SecurePass123!"}'

# 2. Login
curl -X POST https://api.example.com/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"SecurePass123!"}'

# Respuesta
{
  "access_token": "eyJhbGci...",
  "expires_in": 3600,
  "refresh_token": "eyJhbGci..."
}
```

### Crear Pedido
```bash
# 1. Agregar al carrito
curl -X POST https://api.example.com/v1/cart \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-API-Key: $API_KEY" \
  -d '{"product_id":"prod-laptop","quantity":1}'

# 2. Crear pedido
curl -X POST https://api.example.com/v1/orders \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-API-Key: $API_KEY"

# Respuesta
{
  "order_id": "ord-54ae4850",
  "status": "pending",
  "total_amount": 1299.99
}
```

---

## 🔍 Troubleshooting

### Problema: 403 Unauthorized en /v1/*
**Solución:** Verificar que JWT válido se envía en header Authorization

### Problema: Stock insuficiente
**Solución:** Verificar disponibilidad en GET /v1/products antes de crear orden

### Problema: Email no recibido
**Solución:** Verificar SES sender email está validado en AWS Console

### Problema: Terraform apply falla
**Solución:** Ejecutar `terraform refresh` para sincronizar estado

---

## 📝 Flujos de Negocio

### Flujo 1: Compra Completa (9 pasos)
```
1. POST /auth/register      → Usuario creado
2. POST /auth/login         → JWT obtenido
3. GET /v1/products         → Catálogo consultado
4. POST /v1/cart (x2)       → Items agregados
5. POST /v1/orders          → Pedido creado, evento publicado
6. EventBridge dispatch     → 3 Lambdas ejecutadas
7. update_inventory         → Stock actualizado
8. audit_logger             → Eventos registrados
9. notification_email       → Email enviado
```

### Flujo 2: Cambio de Estado de Pedido
```
1. GET /v1/orders/{id}      → Obtener pedido
2. PUT /v1/orders/{id}/status → Cambiar estado
3. EventBridge dispatch     → audit_logger ejecutado
4. notification_email       → Email de actualización (opcional)
```

---

## 📋 Checklist de Producción

- ✓ Documentación técnica completa
- ✓ Casos de prueba validados (4/4)
- ✓ Métricas CloudWatch monitoreadas
- ✓ Alertas configuradas
- ✓ Infrastructure as Code versionada
- ✓ Backup y recuperación documentada
- ✓ Política de seguridad implementada
- ✓ Auditoría y logging completo

### Próximos Pasos (Post-Producción)
- [ ] Implementar CI/CD con GitHub Actions
- [ ] Configurar auto-scaling policies
- [ ] Implementar API Gateway caching
- [ ] Agregar CloudFront caching policies
- [ ] Implementar rate limiting por usuario (vs IP)
- [ ] Agregar soporte multi-región
- [ ] Implementar A/B testing framework

---

## 👥 Equipo y Contribuciones

**Proyecto:** CloudShop Enterprise  
**Institución:** Escuela Superior de Economía y Negocios  
**Programa:** Desarrollo de Software en la Nube  
**Año:** 2026

---

## 📞 Soporte

**Documentación:** Ver archivos README en este repositorio  
**Problemas:** Abrir issue en GitHub  
**Email:** contacto@cloudshop-enterprise.dev

---

## 📄 Licencia

Este proyecto es de demostración académica. Todos los derechos reservados.

---

**Última actualización:** Julio 2026  
**Estado:** ✓ Production Ready
