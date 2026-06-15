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

| Service                                                                    | Language    | Port         | Description                                          |
|----------------------------------------------------------------------------|-------------|--------------|------------------------------------------------------|
| [authentication-service](authentication-service/README.md)                 | Java        | 8081         | Azure AD token exchange → platform JWT              |
| [chat-service](chat-service/README.md)                                     | Java        | 8082         | WebSocket chat + session management                  |
| [chatbot-service](chatbot-service/README.md)                               | Python      | 8000 / 50051 | RAG pipeline (FastAPI + gRPC server)                |
| [document-service](document-service/README.md)                             | Java        | 8083         | SharePoint document retrieval                        |
| [etl-service](etl-service/README.md)                                       | Python      | —            | SharePoint → ChromaDB ingestion pipeline             |
| [evaluation-service](evaluation-service/README.md)                         | Java        | 8084         | AI response quality evaluation (planned)             |
| [kong-gateway](kong-gateway/README.md)                                     | Kong        | 8000         | API gateway — public entry point                     |
| [ollama-service](ollama-service/README.md)                                 | Shell/Docker| 11434        | Self-hosted Ollama LLM server                        |
| [shared-security](shared-security/README.md)                               | Java (lib)  | —            | Shared JWT validation library for Java services      |
| [user-interface](user-interface/README.md)                                 | Vue 3 / TS  | 5173         | Frontend chat application                            |

## Service Documentation

Detailed documentation for each service:

- [Authentication Service](authentication-service/README.md) — Azure AD → platform JWT token exchange, refresh token rotation, PostgreSQL schema
- [Chat Service](chat-service/README.md) — WebSocket/STOMP chat, session management, gRPC integration with chatbot-service
- [Chatbot Service](chatbot-service/README.md) — RAG pipeline, hybrid retrieval (BM25 + BGE-M3), Ollama/HuggingFace/Azure Foundry LLM support
- [Document Service](document-service/README.md) — SharePoint file retrieval via Microsoft Graph API, failed ETL document reporting
- [ETL Service](etl-service/README.md) — SharePoint → ChromaDB ingestion, version filtering, domain tagging
- [Evaluation Service](evaluation-service/README.md) — AI response quality evaluation (faithfulness, retrieval accuracy)
- [Kong Gateway](kong-gateway/README.md) — DB-less API gateway, CORS, rate limiting, route map
- [Ollama Service](ollama-service/README.md) — Self-hosted LLM server, model configuration, GPU support
- [Shared Security](shared-security/README.md) — Shared JWT validation and request logging library for Java services
- [User Interface](user-interface/README.md) — Vue 3 frontend, MSAL SSO, STOMP chat, session management

## Quick Start (Local Development)

### Prerequisites
- Java 21, Gradle
- Python 3.11+
- Node.js 20+
- Docker (for ChromaDB and Ollama, or use Azure instances)
- PostgreSQL 15

### 1. Start the database
```bash
docker run -d --name postgres -e POSTGRES_PASSWORD=password123 \
  -e POSTGRES_DB=oconnor -p 5432:5432 postgres:15
```

### 2. Start Ollama (local LLM)
```bash
docker run -d --name ollama -p 11434:11434 ollama/ollama
docker exec ollama ollama pull llama3.2:3b
```

### 3. Start Java backend services
```bash
cd authentication-service && ./gradlew bootRun &
cd chat-service && ./gradlew bootRun &
cd document-service && ./gradlew bootRun &
```

### 4. Start Python chatbot service
```bash
cd chatbot-service
cp .env.example .env   # edit with credentials
pip install -r requirements.txt
python server.py       # gRPC on :50051
uvicorn app:app --port 8000   # HTTP on :8000
```

### 5. Start the frontend
```bash
cd user-interface
npm install
cp .env.example .env.local   # edit with credentials
npm run dev                   # http://localhost:5173
```

## ETL — Ingesting Documents

To load O'Connors IMS documents into ChromaDB:
```bash
cd etl-service
pip install -r requirements.txt
cp .env.example .env   # set SharePoint credentials + ChromaDB host
python src/main.py
```

## Production Deployment

All services are deployed as Azure Container Apps. The Kong gateway is the only publicly exposed endpoint. See each service's README for its deployment manifest.

## Design Documents

All documents and diagrams are collected in the [docs/](docs/) folder.

- [DESIGN_DOCUMENT.md](docs/DESIGN_DOCUMENT.md) — detailed architecture and technical decisions
- [CONCEPT_DESIGN_REPORT.md](docs/CONCEPT_DESIGN_REPORT.md) — project concept and requirements
- [docs/diagrams/](docs/diagrams/) — architecture diagrams (`.drawio`, `.png`, ETL pipeline)
- [docs/services/](docs/services/) — per-service documentation
