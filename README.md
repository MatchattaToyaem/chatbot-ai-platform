# O'Connors AI Platform

RAG-powered AI assistant for O'Connors Services IMS documents. Users ask questions in natural language and receive answers grounded in source documents, with clickable links to the original SharePoint files.

## Architecture Overview

```
Browser (Vue 3)
    │  Microsoft SSO (MSAL)
    ▼
Kong Gateway  ←─ single public entry point (CORS, rate limiting)
    │
    ├── POST /api/auth/**  ──────────►  Authentication Service (Java)
    │                                   Azure AD token → Platform JWT
    │
    ├── WS   /ws                    ┐
    ├── REST /api/chat-sessions/**  ├─►  Chat Service (Java)
    │                               ┘   STOMP chat + session history
    │                                        │ gRPC
    │                                        ▼
    │                                   Chatbot Service (Python)
    │                                   RAG pipeline (BGE-M3 + Ollama)
    │                                        │
    │                                        ▼
    │                                   ChromaDB (Azure)
    │
    ├── GET  /documents/**  ─────────►  Document Service (Java)
    │                                   SharePoint file retrieval
    │
    └── POST /api/chatbot/**  ───────►  Chatbot Service (Python)
                                        FastAPI HTTP endpoint
```

## Services

| Service | Language | Port | Docs |
|---|---|---|---|
| [authentication-service](authentication-service) | Java 21 | 8081 | [docs/services/authentication-service.md](docs/services/authentication-service.md) |
| [chat-service](chat-service) | Java 21 | 8082 | [docs/services/chat-service.md](docs/services/chat-service.md) |
| [chatbot-service](chatbot-service) | Python | 8000 / 50051 | [docs/services/chatbot-service.md](docs/services/chatbot-service.md) |
| [document-service](document-service) | Java 21 | 8083 | [docs/services/document-service.md](docs/services/document-service.md) |
| [etl-service](etl-service) | Python | — | [docs/services/etl-service.md](docs/services/etl-service.md) |
| [evaluation-service](evaluation-service) | Java 17 | 8084 | [docs/services/evaluation-service.md](docs/services/evaluation-service.md) |
| [kong-gateway](kong-gateway) | Kong 3.7 | 8000 | [docs/services/kong-gateway.md](docs/services/kong-gateway.md) |
| [ollama-service](ollama-service) | Shell/Docker | 11434 | [docs/services/ollama-service.md](docs/services/ollama-service.md) |
| [shared-security](shared-security) | Java (lib) | — | [docs/services/shared-security.md](docs/services/shared-security.md) |
| [user-interface](user-interface) | Vue 3 / TS | 3000 | [docs/services/user-interface.md](docs/services/user-interface.md) |

## Service Documentation

- [Authentication Service](docs/services/authentication-service.md) — Azure AD → platform JWT token exchange, refresh token rotation, PostgreSQL schema
- [Chat Service](docs/services/chat-service.md) — WebSocket/STOMP chat, session management, gRPC integration with chatbot-service
- [Chatbot Service](docs/services/chatbot-service.md) — RAG pipeline, hybrid retrieval (BM25 + BGE-M3), Ollama/HuggingFace/Azure Foundry LLM support
- [Document Service](docs/services/document-service.md) — SharePoint file retrieval via Microsoft Graph API, failed ETL document reporting
- [ETL Service](docs/services/etl-service.md) — SharePoint → ChromaDB ingestion, version filtering, domain tagging
- [Evaluation Service](docs/services/evaluation-service.md) — AI response quality evaluation (faithfulness, retrieval accuracy)
- [Kong Gateway](docs/services/kong-gateway.md) — DB-less API gateway, CORS, rate limiting, route map
- [Ollama Service](docs/services/ollama-service.md) — Self-hosted LLM server, model configuration, GPU support
- [Shared Security](docs/services/shared-security.md) — Shared JWT validation and request logging library for Java services
- [User Interface](docs/services/user-interface.md) — Vue 3 frontend, MSAL SSO, STOMP chat, session management

## Quick Start (Local Development)

See **[LOCAL_SETUP.md](LOCAL_SETUP.md)** for the full Docker Compose setup guide.

```bash
cp .env.example .env          # fill in Azure credentials
docker compose build           # build all images
docker compose up -d           # start the full stack
```

Frontend: http://localhost:3000  
API gateway: http://localhost:8000

To ingest documents into ChromaDB:
```bash
docker compose --profile etl up etl-service
```

## Production Deployment

All services are deployed as Azure Container Apps. The Kong gateway is the only publicly exposed endpoint.

## Design Documents

- [DESIGN_DOCUMENT.md](docs/DESIGN_DOCUMENT.md) — detailed architecture and technical decisions
- [CONCEPT_DESIGN_REPORT.md](docs/CONCEPT_DESIGN_REPORT.md) — project concept and requirements
- [docs/diagrams/](docs/diagrams/) — architecture diagrams (`.drawio`, `.jpeg`)
- [docs/services/](docs/services/) — per-service documentation
