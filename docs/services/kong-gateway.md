# Kong Gateway

**API gateway** for the O'Connors AI Platform. Kong acts as the single public entry point — all frontend traffic routes through Kong, and backend services are not directly exposed.

## Responsibility

- Routes incoming HTTP/WebSocket traffic to the correct backend service (authentication, chat, document, chatbot).
- Enforces **rate limiting** on all routes to protect backend services from overload.
- Adds **CORS headers** so the Vue.js frontend can call APIs from the browser.
- Runs in **DB-less mode** — configuration is loaded from a YAML file at startup (no database required).

## Route Map

| Frontend calls                    | Kong forwards to                       | Rate limit  |
|-----------------------------------|----------------------------------------|-------------|
| `POST /api/auth/**`               | authentication-service (port 8081)     | 20 req/min  |
| `GET/PUT/POST/DELETE /api/chat-sessions/**` | chat-service (port 8082)   | 60 req/min  |
| `WS /ws`                          | chat-service WebSocket                 | 60 req/min  |
| `GET /documents/**`               | document-service (port 8083)           | 30 req/min  |
| `GET /ocr-trigger`                | document-service                       | 30 req/min  |
| `POST /api/chatbot/**`            | chatbot-service FastAPI (port 8000)    | 30 req/min  |

> The `/api/chatbot` prefix is **stripped** before forwarding to the chatbot-service (Kong `strip_path: true`), so `/api/chatbot/ask` becomes `/ask` on the upstream.

## File Structure

```
kong-gateway/
├── kong.yaml.template      # Route/service/plugin config template (env var substitution)
├── kong-gateway.yaml       # Kubernetes deployment manifest
├── entrypoint.sh           # Docker entrypoint (renders template → runs Kong)
└── Dockerfile              # Kong image with custom entrypoint
```

## Configuration

Routes and upstream URLs are defined in `kong.yaml.template`. The `entrypoint.sh` script substitutes environment variables before starting Kong:

```bash
# Key environment variables
AUTHENTICATION_SERVICE_URL=https://authentication-service.<cluster>.azurecontainerapps.io
CHAT_SERVICE_URL=https://chat-service.<cluster>.azurecontainerapps.io
DOCUMENT_SERVICE_URL=https://document-service.<cluster>.azurecontainerapps.io
CHATBOT_SERVICE_URL=https://chatbot-service.<cluster>.azurecontainerapps.io
```

## Plugins Applied

### CORS

Applied to all routes. Allows the Vue.js frontend to call APIs cross-origin:
```yaml
- name: cors
  config:
    origins: ["*"]           # Replace with frontend domain in production
    credentials: true
    max_age: 3600
```

### Rate Limiting

Per-service limits to prevent overload:
```yaml
- name: rate-limiting
  config:
    minute: 60               # Requests per minute per client IP
    policy: local
```

## Running Locally (Docker)

```bash
docker build -t kong-gateway .
docker run -p 8000:8000 -p 8443:8443 \
  -e AUTHENTICATION_SERVICE_URL=http://localhost:8081 \
  -e CHAT_SERVICE_URL=http://localhost:8082 \
  -e DOCUMENT_SERVICE_URL=http://localhost:8083 \
  -e CHATBOT_SERVICE_URL=http://localhost:8000 \
  kong-gateway
```

Kong admin API is available on port 8001 (if exposed).

## Production Deployment

Kong is deployed to Azure Container Apps via `kong-gateway.yaml`. The deployment reads upstream service URLs from environment variables set in the container app configuration.

## DB-less Mode

This Kong instance runs in DB-less mode (`KONG_DATABASE=off`). The entire configuration lives in the YAML template — no `kong admin` CLI or Admin API writes are needed. Changes require a container restart.
