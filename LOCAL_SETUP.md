# Local Development Setup

This guide explains how to run the entire O'Connors AI Platform on a local machine using Docker Compose.

---

## Prerequisites

| Tool | Minimum Version | Install |
|---|---|---|
| Docker Desktop | 4.x | https://www.docker.com/products/docker-desktop |
| Docker Compose | v2.x (bundled with Desktop) | — |
| Git | any | — |

**Hardware:** Ollama (local LLM) requires at least **8 GB of free RAM**. The first run also downloads the `llama3.2:3b` model (~2 GB).

---

## 1. Clone and configure

```bash
# From the repository root
cp .env.example .env
```

Open `.env` and fill in the required values. Every value tagged **required** must be set before the stack will start correctly.

### Required credentials

| Variable | Where to get it |
|---|---|
| `AZURE_TENANT_ID` | Azure Portal → Azure Active Directory → Overview |
| `AZURE_CLIENT_ID` | Azure Portal → App Registrations → your backend app |
| `AZURE_CLIENT_SECRET` | Azure Portal → App Registrations → Certificates & secrets |
| `JWT_ISSUER_URI` | `https://login.microsoftonline.com/<AZURE_TENANT_ID>/v2.0` |
| `JWT_SECRET` | Any random string ≥ 32 characters |
| `SHAREPOINT_CLIENT_ID` | Same as `AZURE_CLIENT_ID` if using one app registration |
| `SHAREPOINT_CLIENT_SECRET` | Same as `AZURE_CLIENT_SECRET` if using one app registration |
| `VITE_AZURE_CLIENT_ID` | Azure Portal → App Registrations → your **SPA** app |
| `VITE_AZURE_AUTHORITY` | `https://login.microsoftonline.com/<AZURE_TENANT_ID>` |
| `VITE_AZURE_SCOPE` | `api://<AZURE_CLIENT_ID>/access_as_user` |

> **Note:** Authentication is backed by real Azure AD. The system will not work with a fake tenant ID. If you need an offline mode, ask the team for a dev Azure app registration.

---

## 2. Build images

Build all service images (this takes several minutes on first run):

```bash
docker compose build
```

To rebuild a single service after a code change:

```bash
docker compose build <service-name>
# e.g.
docker compose build chatbot-service
docker compose build authentication-service
```

---

## 3. Start the full stack

```bash
docker compose up -d
```

Services start in dependency order. The first time you run this, Ollama will download the LLM model (~2 GB) before the chatbot service becomes healthy. Allow 3–5 minutes for the full stack to be ready.

### Check status

```bash
docker compose ps
```

All services should show `running (healthy)` or `running` after startup.

### Watch logs for a service

```bash
docker compose logs -f authentication-service
docker compose logs -f chatbot-service
docker compose logs -f kong
```

---

## 4. Service endpoints

Once the stack is running, all traffic goes through **Kong Gateway** on port 8000.

| URL | Service |
|---|---|
| `http://localhost:8000` | Kong Gateway (public entry point) |
| `http://localhost:3000` | User Interface (Vue 3 frontend) |
| `http://localhost:8001` | Kong Admin API |
| `http://localhost:9200` | Elasticsearch |
| `http://localhost:5601` | Kibana (log dashboard) |
| `http://localhost:8001` (ChromaDB) | ChromaDB is exposed on **8001** on the host |
| `http://localhost:11434` | Ollama (LLM API) |

### API routes through Kong

| Path | Service |
|---|---|
| `POST /api/auth/token` | authentication-service — issue JWT |
| `POST /api/auth/refresh` | authentication-service — refresh JWT |
| `POST /api/auth/logout` | authentication-service — revoke token |
| `GET/POST /api/chat-sessions` | chat-service — session management |
| `WS /ws` | chat-service — STOMP WebSocket |
| `GET /documents/file` | document-service — SharePoint file |
| `POST /api/chatbot/ask` | chatbot-api — RAG Q&A |
| `POST /api/chatbot/search` | chatbot-api — retrieval only |
| `GET /api/chatbot/health` | chatbot-api — service health |

---

## 5. Ingest documents (ETL)

The chatbot requires documents to be ingested into ChromaDB before it can answer questions. Run the ETL pipeline:

```bash
docker compose --profile etl up etl-service
```

The ETL service:
1. Connects to SharePoint and downloads documents
2. Extracts text (PDF, DOCX, XLSX) using OCR where needed
3. Chunks and embeds documents using `BAAI/bge-m3`
4. Stores vectors in ChromaDB

The pipeline loops every 3 days by default. After the first successful run, stop it with `Ctrl+C` or:

```bash
docker compose --profile etl stop etl-service
```

> **First run can take 30–90 minutes** depending on the number of documents in SharePoint.

---

## 6. Stop the stack

```bash
# Stop all containers (keeps data volumes)
docker compose down

# Stop and delete all data (full reset)
docker compose down -v
```

---

## 7. Rebuild a specific service after code changes

```bash
# Example: rebuild and restart authentication-service
docker compose build authentication-service
docker compose up -d --no-deps authentication-service
```

---

## Port reference

| Host Port | Container | Description |
|---|---|---|
| 3000 | user-interface:80 | Frontend (nginx) |
| 5432 | postgres:5432 | PostgreSQL |
| 5601 | kibana:5601 | Kibana log UI |
| 6379 | redis:6379 | Redis |
| 8000 | kong:8000 | Kong proxy (public API) |
| 8001 | chromadb:8000 | ChromaDB HTTP API |
| 8001 | kong:8001 | Kong Admin API (shares host port with chromadb only if you remove one) |
| 8002 | chatbot-api:8000 | Chatbot FastAPI (direct, bypasses Kong) |
| 8081 | authentication-service:8081 | Auth service (direct) |
| 8082 | chat-service:8082 | Chat service (direct) |
| 8083 | document-service:8080 | Document service (direct) |
| 8084 | evaluation-service:8080 | Evaluation service (direct) |
| 9200 | elasticsearch:9200 | Elasticsearch |
| 11434 | ollama:11434 | Ollama LLM |
| 50051 | chatbot-service:50051 | Chatbot gRPC server |

> **Port conflict note:** ChromaDB and Kong Admin both map to host port 8001. If you need both simultaneously, change one by editing `docker-compose.yml`. For most development work, chromadb is accessed internally by the chatbot service and you do not need to expose it on the host.

---

## Troubleshooting

### Spring Boot service fails to start — database connection refused

PostgreSQL may still be initialising. Check its health:

```bash
docker compose ps postgres
```

Wait until it shows `healthy`, then restart the failing service:

```bash
docker compose restart authentication-service
```

### Chatbot service crashes — "Model not found in Ollama"

Ollama is still downloading the model. Watch the Ollama logs:

```bash
docker compose logs -f ollama
```

Wait until you see `Model ready. Ollama is running.`, then restart:

```bash
docker compose restart chatbot-service chatbot-api
```

### Kong returns 404 for all routes

Check that the local Kong config loaded correctly:

```bash
curl http://localhost:8001/services
```

If the response is empty, restart Kong:

```bash
docker compose restart kong
```

### User interface shows authentication error

Ensure `VITE_AZURE_CLIENT_ID`, `VITE_AZURE_AUTHORITY`, and `VITE_AZURE_REDIRECT_URI` in `.env` match the Azure AD app registration exactly. The redirect URI must be registered in Azure AD → App Registrations → your SPA app → Authentication → Redirect URIs.

After changing `.env`, rebuild the user-interface image (build args are baked in at build time):

```bash
docker compose build user-interface
docker compose up -d --no-deps user-interface
```

### ETL service — "Sanity check failed: cannot reach ChromaDB"

ChromaDB must be healthy before ETL starts:

```bash
docker compose ps chromadb
curl http://localhost:8001/api/v1/heartbeat
```

### View ChromaDB collections

```bash
curl http://localhost:8001/api/v1/collections
```

### Reset ChromaDB data only

```bash
docker compose stop chromadb
docker volume rm ai-platform_chromadb_data
docker compose up -d chromadb
```

---

## Architecture summary

```
Browser (http://localhost:3000)
    │  Azure AD SSO (MSAL)
    ▼
Kong Gateway (http://localhost:8000)
    │
    ├── /api/auth/**         → authentication-service:8081 (Java / Spring Boot)
    │                              ↕ PostgreSQL:5432
    │
    ├── /api/chat-sessions/** → chat-service:8082 (Java / Spring Boot)
    ├── /ws                   → chat-service:8082 (STOMP WebSocket)
    │                              ↕ PostgreSQL:5432
    │                              ↕ chatbot-service:50051 (gRPC)
    │                                       ↕ ChromaDB:8000 (vectors)
    │                                       ↕ Ollama:11434 (LLM)
    │
    ├── /documents/**        → document-service:8080 (Java / Spring Boot)
    │                              ↕ SharePoint (Microsoft Graph API)
    │
    └── /api/chatbot/**      → chatbot-api:8000 (Python / FastAPI)
                                       ↕ ChromaDB:8000
                                       ↕ Ollama:11434

ETL Service (batch, --profile etl)
    SharePoint → OCR/extract → ChromaDB
```
