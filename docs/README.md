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
| [authentication-service](services/authentication-service.md)               | Java        | 8081         | Azure AD token exchange → platform JWT              |
| [chat-service](services/chat-service.md)                                   | Java        | 8082         | WebSocket chat + session management                  |
| [chatbot-service](services/chatbot-service.md)                             | Python      | 8000 / 50051 | RAG pipeline (FastAPI + gRPC server)                |
| [document-service](services/document-service.md)                           | Java        | 8083         | SharePoint document retrieval                        |
| [etl-service](services/etl-service.md)                                     | Python      | —            | SharePoint → ChromaDB ingestion pipeline             |
| [evaluation-service](services/evaluation-service.md)                       | Java        | 8084         | AI response quality evaluation (planned)             |
| [kong-gateway](services/kong-gateway.md)                                   | Kong        | 8000         | API gateway — public entry point                     |
| [ollama-service](services/ollama-service.md)                               | Shell/Docker| 11434        | Self-hosted Ollama LLM server                        |
| [shared-security](services/shared-security.md)                             | Java (lib)  | —            | Shared JWT validation library for Java services      |
| [user-interface](services/user-interface.md)                               | Vue 3 / TS  | 5173         | Frontend chat application                            |

## Service Documentation

Detailed documentation for each service:

- [Authentication Service](services/authentication-service.md) — Azure AD → platform JWT token exchange, refresh token rotation, PostgreSQL schema
- [Chat Service](services/chat-service.md) — WebSocket/STOMP chat, session management, gRPC integration with chatbot-service
- [Chatbot Service](services/chatbot-service.md) — RAG pipeline, hybrid retrieval (BM25 + BGE-M3), Ollama/HuggingFace/Azure Foundry LLM support
- [Document Service](services/document-service.md) — SharePoint file retrieval via Microsoft Graph API, failed ETL document reporting
- [ETL Service](services/etl-service.md) — SharePoint → ChromaDB ingestion, version filtering, domain tagging
- [Evaluation Service](services/evaluation-service.md) — AI response quality evaluation (faithfulness, retrieval accuracy)
- [Kong Gateway](services/kong-gateway.md) — DB-less API gateway, CORS, rate limiting, route map
- [Ollama Service](services/ollama-service.md) — Self-hosted LLM server, model configuration, GPU support
- [Shared Security](services/shared-security.md) — Shared JWT validation and request logging library for Java services
- [User Interface](services/user-interface.md) — Vue 3 frontend, MSAL SSO, STOMP chat, session management

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

- [DESIGN_DOCUMENT.md](DESIGN_DOCUMENT.md) — detailed architecture and technical decisions
- [CONCEPT_DESIGN_REPORT.md](CONCEPT_DESIGN_REPORT.md) — project concept and requirements

### Diagrams

- [1 - System Architecture](diagrams/1-system-architecture.jpeg)
- [2 - Communication Protocols](diagrams/2-communication-protocols.jpeg)
- [3 - Security Architecture](diagrams/3-security-architecture.jpeg)
- [4 - Auth Sequence](diagrams/4-auth-sequence.jpeg)
- [5 - Deployment (Azure)](diagrams/5-deployment-azure.jpeg)
- [ETL Pipeline Architecture](diagrams/etl-pipeline-architecture.md)
- [Source file](diagrams/architecture.drawio) (`.drawio`)

### Service Documentation

- [Authentication Service](services/authentication-service.md)
- [Chat Service](services/chat-service.md)
- [Chatbot Service](services/chatbot-service.md)
- [Document Service](services/document-service.md)
- [ETL Service](services/etl-service.md)
- [Evaluation Service](services/evaluation-service.md)
- [Kong Gateway](services/kong-gateway.md)
- [Ollama Service](services/ollama-service.md)
- [Shared Security](services/shared-security.md)
- [User Interface](services/user-interface.md)
