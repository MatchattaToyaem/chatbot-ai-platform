# O'Connors AI Platform — Design Document

**Version:** 2.2  
**Date:** 2026-06-03  
**Authors:** Capstone Project Team  
**Institution:** University of Adelaide  

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture Overview](#2-architecture-overview)
3. [Service Design & Core Functionality](#3-service-design--core-functionality)
   - 3.1 [Kong API Gateway](#31-kong-api-gateway)
   - 3.2 [Authentication Service](#32-authentication-service)
   - 3.3 [Chat Service](#33-chat-service)
   - 3.4 [Chatbot Service (RAG Engine)](#34-chatbot-service-rag-engine)
   - 3.5 [ETL Service](#35-etl-service)
   - 3.6 [Document Service](#36-document-service)
   - 3.7 [User Interface](#37-user-interface)
4. [System Workflows](#4-system-workflows)
5. [Data Flow Diagrams](#5-data-flow-diagrams)
6. [External Libraries & Attribution](#6-external-libraries--attribution)
7. [Assumptions & Significant Decisions](#7-assumptions--significant-decisions)
8. [Version Control](#8-version-control)
9. [Test Cases, Results & Debugging Notes](#9-test-cases-results--debugging-notes)

---

## 1. Project Overview

The O'Connors AI Platform is a cloud-deployed, enterprise-grade Retrieval-Augmented Generation (RAG) chatbot system. It allows O'Connors staff to query internal documents stored in Microsoft SharePoint using natural language. The platform ingests documents from SharePoint, converts them to vector embeddings, and serves answers through a conversational chat interface backed by a large language model.

**Core capabilities:**
- Secure single-sign-on via Microsoft Azure Active Directory (Entra ID), bridged to a platform JWT
- Real-time WebSocket chat with streaming "typing" animation
- RAG pipeline with hybrid BM25 + vector search, domain-filtered retrieval
- In-browser document preview (PDF, Word, Excel, images) linked to AI source citations
- Persistent chat session history with per-answer quality ratings
- Scheduled ETL pipeline that ingests updated SharePoint documents every 3 days

**Deployment target:** Azure Container Apps (`proudground-90080d26.australiaeast.azurecontainerapps.io`)

---

## 2. Architecture Overview

```
User Browser (Vue 3 SPA)
        │  HTTPS / WSS
        ▼
┌──────────────────────────────────────────┐
│         Kong API Gateway                 │  ← single public ingress
│  Rate limiting · CORS                    │
└────┬──────────┬──────────────────────────┘
     │          │          │
     ▼          ▼          ▼
  Auth       Chat      Document
 Service    Service    Service
(Spring)   (Spring)   (Spring)
     │          │
     ▼          │ gRPC (internal only)
PostgreSQL      ▼
(refresh   Chatbot Service
 tokens)   (Python / gRPC :50051)
                │
                ▼
           ChromaDB          SharePoint
         (vector store)    (MS Graph API)
                ▲                │
                └── ETL Service ─┘
                    (Python, scheduled)

                 Ollama / Azure Foundry
                 / HuggingFace (LLM)
```

All backend services are deployed as Azure Container Apps with `external: false`; Kong is the only publicly accessible container. The chatbot service is strictly internal — it is not routed through Kong and is only reachable by the chat service via gRPC on port 50051.

---

## 3. Service Design & Core Functionality

### 3.1 Kong API Gateway

**Technology:** Kong 3.7, DB-less mode, custom Docker image  
**Source:** `kong-gateway/`

#### Purpose
Acts as the single public entry point for all client requests. Centralises JWT verification, rate limiting, and CORS so backend services do not need to implement these independently.

#### Configuration
Configuration is templated at startup (`kong.yaml.template` → `kong.yaml`) using `envsubst` via `entrypoint.sh`. The two substituted variables are `JWT_SECRET` and `JWT_ISSUER_URI`, injected from Azure Key Vault.

#### Routes and Plugins

| Route | Upstream | JWT Required | Rate Limit |
|-------|----------|:---:|:---:|
| `/api/auth/**` | authentication-service | No | 20 req/min |
| `/api/chat-sessions/**`, `/ws/**` | chat-service | No (Kong level) | 60 req/min |
| `/documents/**`, `/ocr-trigger/**` | document-service | No (Kong level) | 30 req/min |

The chatbot service does **not** have a Kong route. It is an internal gRPC service (port 50051) reachable only by the chat service within the Azure Container Apps environment.

**Decision:** JWT validation is handled at the Spring Security layer within each service rather than at Kong, because services need the JWT claims (user email, roles) to perform business logic. Kong enforces rate limiting and acts as the CORS boundary. The auth endpoints are deliberately exempt from JWT requirements — they are the token issuance endpoints themselves.

---

### 3.2 Authentication Service

**Technology:** Java 21, Spring Boot 4.0.4, Spring Security OAuth2, PostgreSQL  
**Source:** `authentication-service/src/`  
**Dependency:** `edu.oconnor:shared-security:1.0.7` (internal shared library)

#### Purpose
Bridges Microsoft Azure AD (Entra ID) OAuth2 with the platform's own short-lived JWT + refresh token pair. This decouples the frontend from Azure AD token lifetimes and allows platform-specific role injection.

#### Key Components

**`AuthController`** (`controller/AuthController.java`)  
Exposes three REST endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/auth/token` | POST | Accepts an Azure AD access token; validates it; issues a platform access JWT + refresh token |
| `/api/auth/refresh` | POST | Accepts a refresh token; rotates it (revoke old, issue new); returns a new pair |
| `/api/auth/logout` | POST | Revokes a refresh token (client-initiated logout) |

**`JwtTokenProvider`** (`service/JwtTokenProvider.java`)  
Handles signing and verification of platform JWTs using HMAC-SHA256 (`HS256`). Refresh tokens are generated as UUID strings and stored as SHA-256 hashes in PostgreSQL (so the plaintext is never persisted).

Token claims embedded in the access JWT:
- `sub` — Azure AD user ID
- `email` — `preferred_username` from Azure AD
- `name` — display name
- `roles` — list of roles fetched from Azure Graph API
- `iss` — `oconnor-platform`

**`RefreshTokenService`** (`service/RefreshTokenService.java`)  
Manages the refresh token lifecycle: `createAndStore`, `validate`, `revoke`, and `revokeAllForUser`. Tokens are validated by hashing the incoming plaintext and comparing against the stored hash, checking `revoked = FALSE` and `expires_at > CURRENT_TIMESTAMP`.

**`AzureGraphService`** (`service/AzureGraphService.java`)  
Calls the Microsoft Graph API to fetch the user's group memberships (roles) at token exchange time. Roles are embedded in the platform JWT so downstream services do not need to call Graph API themselves.

#### Token Expiry (Configurable via `application.yml`)
- Access token: short-lived (e.g., 15 minutes)
- Refresh token: longer-lived (e.g., 7 days), rotated on use

---

### 3.3 Chat Service

**Technology:** Java 21, Spring Boot 4.0.4, Spring WebSocket (STOMP), PostgreSQL  
**Source:** `chat-service/src/`  
**Dependency:** `edu.oconnor:shared-security:1.0.7`

#### Purpose
Manages chat sessions and acts as the WebSocket relay between the frontend and the chatbot service. Maintains persistent conversation history including AI answers, source citations, confidence scores, model name, response time, and user ratings.

#### Key Components

**`ChatController`** (`controller/ChatController.java`)  
Handles WebSocket STOMP messages:
- Listens at `/app/chat` (STOMP destination)
- Calls `ChatbotIntegrationService` to forward the question to the chatbot via gRPC
- Appends the result (question + answer + sources + metadata) to the session's chat history
- Returns a `MessageResponse` to the user's personal STOMP queue `/queue/message`

**`ChatSessionController`** (`controller/ChatSessionController.java`)  
REST API for session management: create, read, update, delete sessions; retrieve sessions by user; update answer ratings.

**`ChatbotIntegrationService`** (`service/ChatbotIntegrationService.java`)  
Wraps the gRPC stub for the chatbot service. Translates `MessageRequest` → gRPC `InferenceRequest` → `InferenceReply` → `MessageResponse`.

**`ChatSessionRepository`** (`repository/ChatSessionRepository.java`)  
Spring Data repository for `ChatSession` entities. Chat history is stored as a JSON column (`chatHistory`) in PostgreSQL.

#### WebSocket Configuration
`WebsocketConfiguration.java` configures a STOMP broker with `/queue` and `/topic` destinations, application prefix `/app`, and CORS permitted origins. Security is handled by the shared security library, which validates the platform JWT on WebSocket handshake.

---

### 3.4 Chatbot Service (RAG Engine)

**Technology:** Python, gRPC (port 50051), ChromaDB, LangChain  
**Source:** `chatbot-service/`  
**Access:** Internal only — exposed exclusively to the chat service via gRPC. Not routed through Kong; not reachable from the browser.

#### Purpose
The AI inference engine. Receives questions from the chat service via gRPC, performs Retrieval-Augmented Generation (hybrid BM25 + vector search), and returns answers with source document citations, confidence scores, and model name. No external HTTP surface is exposed in production.

#### Key Components

**`server.py`** — gRPC server entry point  
- Validates LLM provider configuration on startup (`sanity_check`)
- Supports three LLM backends switchable via `LLM_PROVIDER` environment variable:
  - `ollama` (default) — local/self-hosted Llama model via Ollama HTTP API
  - `huggingface` — HuggingFace Hub inference
  - `azure-foundry` — Azure AI Foundry endpoint
- Applies an optional `RAG_DOMAIN` filter to restrict retrieval to a specific document domain (`IMS` or `Service`)
- Pre-warms the BM25 index on startup to eliminate cold-start latency on the first query

**`AIServiceServicer.GenerateResponse`**  
Core handler: receives a `prompt` + `session_id`, delegates to `RAGService.ask()`, maps source metadata to gRPC `Source` messages, and returns an `InferenceReply` with `result`, `confidence`, `sources`, and `model`.

**RAG Retrieval Strategy**  
Hybrid search: BM25 keyword match + dense vector similarity via `BAAI/bge-m3` (1024-dimensional embeddings). Results are re-ranked using a cross-encoder and top-k chunks are assembled into a context prompt for the LLM.

---

### 3.5 ETL Service

**Technology:** Python 3.12, LangChain, ChromaDB, PaddleOCR, Microsoft Graph API (MSAL)  
**Source:** `etl-service/src/`

#### Purpose
Scheduled background pipeline that discovers documents in SharePoint, downloads them, extracts text (with OCR fallback for scanned PDFs), chunks them, embeds them using BGE-M3, and stores them in ChromaDB. Runs every 3 days.

#### Pipeline Steps (v2.2)

**Step 1 — Scan SharePoint** (`pipeline_module/sharepoint_pipeline.py`)  
`SharePointPipeline.scan()` calls Microsoft Graph API via the `MatSharePointConnection` (composition, not inheritance). Supports a mock mode (`PIPELINE_MODE=mock`) that reads from a local JSON fixture for development without Azure credentials.

**Step 2 — Version filter** (`pipeline_module/pipeline_runner.py`)  
`filter_latest_versions()` groups documents by base filename (stripping version numbers, dates, revision markers). For folders with a year sub-folder structure (Service domain), groups by `(building_path, base_name)` to avoid collapsing same-named files across different buildings. Keeps only the latest version of each document group; amendments are always kept alongside.

**Step 3 — Download**  
Batch downloads via `SharePointPipeline.download_all()`. Each individual download is wrapped with the `@with_resilience` decorator (exponential back-off for HTTP 429/5xx/timeout).

**Step 4 — Text extraction** (`pipeline_module/document_extractor.py`)  
Uses LangChain document loaders for `.pdf`, `.docx`, `.txt`. Falls back to PaddleOCR for scanned PDFs that yield no extractable text.

**Step 5 — Chunk, tag, embed, store** (`pipeline_module/vector_store_writer.py`)  
- `enrich_chunk_text()` prepends a context header to each chunk (document title + detected section heading, or MSDS section number for Safety Data Sheets)
- Every chunk receives a `domain` metadata field (`IMS` or `Service`) derived from `SHAREPOINT_TARGET_FOLDER`
- Old chunks for a document are deleted before re-ingestion (`delete_by_source`) to prevent stale duplicates
- Embedding model: `BAAI/bge-m3` (1024-dim). A mismatched model aborts the pipeline with a warning.

**`pipeline_module/resilience.py`** — `@with_resilience` decorator  
Retries retryable HTTP errors (429, 503, timeout, connection errors) with exponential back-off up to `HTTP_MAX_RETRIES` attempts. Fails fast on non-retryable errors (403, 404, unknown).

**`file_tracking_module/db_tracker.py`**  
Tracks processed files in a PostgreSQL `etl_file_tracker` table to support incremental processing.

---

### 3.6 Document Service

**Technology:** Java 21, Spring Boot 4.0.4, Spring Security  
**Source:** `document-service/src/`  
**Dependency:** `edu.oconnor:shared-security:1.0.7`

#### Purpose
Proxies document retrieval from SharePoint and serves raw document bytes to the frontend for in-browser preview. Also exposes an OCR trigger endpoint and a failed-document audit log.

#### Key Components

**`DocumentRetrievalController`** (`controller/DocumentRetrievalController.java`)  
`GET /documents/file?path=<sharepoint-path>` — fetches the binary content of a SharePoint file and returns it with the correct `Content-Type` header and `Content-Disposition: inline` for browser rendering. Requires authentication.

**`OcrTriggerController`** (`controller/OcrTriggerController.java`)  
`GET /ocr-trigger` — triggers OCR processing for documents that failed text extraction.

**`FailedDocumentController`** (`controller/FailedDocumentController.java`)  
`GET /documents/failed` — paginated list of documents that failed ETL processing, with date-range filtering for audit purposes.

---

### 3.7 User Interface

**Technology:** Vue 3 (Composition API), TypeScript, Vite, Pinia, MSAL Browser, STOMP.js, Bootstrap 5  
**Source:** `user-interface/src/`

#### Purpose
Single-page application (SPA) providing the chat interface, document viewer, and session management. Deployed as a static Nginx container.

#### Key Components

**`views/Chat.vue`** — main chat view  
The primary view, containing all chat logic:
- Connects to the chat service WebSocket via STOMP on mount
- Manages multiple named chat sessions (create, rename, delete, search)
- Sends messages via `wsSendMessage`; receives AI responses via `handleWsMessage`
- Animates AI responses character-by-character at 18 ms/character (skippable)
- Loads session history from the chat service REST API on session selection
- Fetches cited documents from the document service for inline preview
- Supports light/dark theme toggle with animated wipe transition and fireworks effect

**`views/Login.vue`**  
MSAL-based Azure AD sign-in with PKCE flow. On success, calls `authService.exchangeToken()` to swap the Azure AD token for a platform JWT.

**`views/DocumentLibrary.vue`**  
Browsable document library view.

**`services/authService.ts`**  
Wraps MSAL Browser. Handles sign-in, token acquisition (silent then interactive), platform token exchange, token refresh, and logout.

**`services/websocketService.ts`**  
Manages the STOMP WebSocket connection to the chat service. Subscribes to `/user/queue/message` for incoming AI responses.

**`services/chatSessionService.ts`**  
REST client for the chat session API (CRUD, history retrieval, answer rating).

**`stores/userStore.ts`**  
Pinia store holding the MSAL account object (name, email, roles).

**`router/index.ts`**  
Vue Router with a navigation guard: redirects to `/login` if no authenticated user is found in the MSAL cache.

#### Comparison Prompt (A/B Evaluation)
After the first AI reply, there is a 30% chance each subsequent reply is shown as a comparison prompt (`Response A` / `Response B`) to collect implicit quality preference data. This is a UI-only feature; it does not invoke the LLM twice.

---

## 4. System Workflows

### 4.1 User Authentication Flow

```
1. User opens the app → Vue Router guard redirects to /login
2. User clicks "Sign in with Microsoft"
3. MSAL Browser opens Azure AD PKCE login popup
4. Azure AD returns an access token (Azure JWT)
5. authService.exchangeToken() calls POST /api/auth/token
   with the Azure JWT in the request body
6. AuthController validates the Azure JWT via azureJwtDecoder
7. AzureGraphService fetches the user's group roles from MS Graph
8. JwtTokenProvider creates a platform access JWT (HS256, short-lived)
9. RefreshTokenService creates a UUID refresh token,
   stores its SHA-256 hash in PostgreSQL
10. TokenResponse { accessToken, refreshToken, expiresIn }
    is returned to the frontend
11. Frontend stores tokens in memory / localStorage
12. All subsequent requests carry "Authorization: Bearer <accessToken>"
```

### 4.2 Token Refresh Flow

```
1. authService detects the access JWT is expired (or a 401 is received)
2. POST /api/auth/refresh { refreshToken }
3. RefreshTokenService.validate() hashes the token,
   checks revoked=FALSE, expires_at > NOW
4. Old refresh token is revoked
5. New access JWT + new refresh token are issued (token rotation)
6. Frontend updates its stored tokens
```

### 4.3 Chat Message Flow

```
1. User types a message in ChatInput.vue and clicks Send
2. Chat.vue.sendMessage() pushes the user message to the local
   messages array immediately (optimistic UI)
3. A "thinking" placeholder message is inserted
4. wsSendMessage({ sessionId, message, sender }) sends a STOMP
   frame to /app/chat on the chat service
5. ChatController.sendMessage() receives the STOMP frame
6. ChatbotIntegrationService.askChatbot() sends a gRPC
   InferenceRequest { prompt, session_id } to the chatbot service
7. AIServiceServicer.GenerateResponse() retrieves relevant chunks
   from ChromaDB via hybrid search, assembles a context prompt,
   calls the LLM, and returns an InferenceReply
8. ChatController assembles a MessageResponse (answer, sources,
   confidence, model, responseTime)
9. ChatSessionService.appendChatHistory() persists the exchange
   to PostgreSQL
10. The response is sent to the user's STOMP queue /queue/message
11. Chat.vue.handleWsMessage() replaces the "thinking" placeholder
    with the assistant message and begins the character-by-character
    typing animation
12. Source document citations are displayed as clickable badges
13. Clicking a source badge calls fetchDocumentBlob(), which calls
    GET /documents/file?path=<path> on the document service
14. The document binary is rendered in the embedded DocViewer panel
```

### 4.4 ETL Pipeline Flow (Runs Every 3 Days)

```
1. sanity_check() validates Azure credentials, PostgreSQL
   connectivity, ChromaDB connectivity, write permissions
2. SharePointPipeline.scan(SHAREPOINT_TARGET_FOLDER) calls
   the MS Graph API to list all accessible files
3. filter_latest_versions() removes older revisions,
   keeping amendments alongside their parent documents
4. SharePointPipeline.download_all() downloads files locally
   (each download wrapped with @with_resilience retry logic)
5. DocumentExtractor.extract() parses each file:
   - PDF: pdfplumber → text extraction
   - PDF (scanned/no text): PaddleOCR → text extraction
   - DOCX: unstructured loader
6. enrich_chunk_text() prepends a context header to each chunk
   (document name + detected heading / MSDS section)
7. VectorStoreWriter.delete_by_source() removes stale chunks
   for each document before re-ingestion
8. Chunk metadata.domain is set to the target folder's first
   path segment (e.g., "IMS" or "Service")
9. BGE-M3 embeddings (1024-dim) are computed for each chunk
10. Chunks are upserted into ChromaDB
11. Loop sleeps 3 days before next run
```

---

## 5. Data Flow Diagrams

### Request Authentication at Kong

```
Client Request
    │
    ▼
Kong Gateway
    ├─ /api/auth/* ──────────────────► auth-service (no JWT check, rate-limit 20/min)
    ├─ /api/chat-sessions/* / /ws/* ─► chat-service (rate-limit 60/min)
    └─ /documents/* / /ocr-trigger ─► document-service (rate-limit 30/min)

Chatbot service: NOT behind Kong.
    chat-service ──gRPC :50051──► chatbot-service (internal only)

Each public-facing service validates the Authorization header independently
using the shared-security library (Spring Security OAuth2 Resource Server,
HS256, issuer=oconnor-platform).
```

### Document Ingestion Pipeline

```
SharePoint (MS Graph API)
         │
         ▼
SharePointPipeline.scan()     ← file list (name, path, id, eTag, modified)
         │
         ▼
filter_latest_versions()      ← deduplicates by base_name / (building_path, base_name)
         │
         ▼
SharePointPipeline.download() ← local files in SHAREPOINT_DOWNLOAD_DIR
         │
         ▼
DocumentExtractor.extract()   ← pdfplumber / PaddleOCR / unstructured → LangChain Documents
         │
         ▼
enrich_chunk_text()           ← prepend context header, add domain metadata
         │
         ▼
VectorStoreWriter.store()     ← BGE-M3 embed + ChromaDB upsert
```

---

## 6. External Libraries & Attribution

### Java Services (Spring Boot)

| Library | Version | Purpose | Source |
|---------|---------|---------|--------|
| Spring Boot | 4.0.4 | Application framework | https://spring.io/projects/spring-boot |
| Spring Security | (managed) | Authentication / authorisation | https://spring.io/projects/spring-security |
| Spring OAuth2 Resource Server | (managed) | JWT validation | https://spring.io/projects/spring-security |
| Nimbus JOSE + JWT | (managed) | JWT encoding/decoding (HS256) | https://connect2id.com/products/nimbus-jose-jwt |
| Spring WebSocket + STOMP | (managed) | Real-time chat relay | https://spring.io/guides/gs/messaging-stomp-websocket/ |
| Spring Data JPA / JDBC | (managed) | Database access | https://spring.io/projects/spring-data |
| PostgreSQL JDBC Driver | (managed) | Database connectivity | https://jdbc.postgresql.org/ |
| Lombok | (managed) | Boilerplate reduction | https://projectlombok.org/ |
| Micrometer Prometheus | (managed) | Metrics export | https://micrometer.io/ |
| `edu.oconnor:shared-security` | 1.0.7 | Shared JWT filter, CORS, WebSocket security | Internal (Azure Artifacts feed) |

### Python Services (ETL & Chatbot)

| Library | Version | Purpose | Source |
|---------|---------|---------|--------|
| LangChain | 0.3.7 | RAG orchestration, document loaders, text splitters | https://www.langchain.com/ |
| LangChain Community | 0.3.5 | ChromaDB integration, HuggingFace loaders | https://github.com/langchain-ai/langchain |
| LangChain HuggingFace | 0.1.2 | HuggingFace embedding integration | https://github.com/langchain-ai/langchain |
| ChromaDB | 0.5.15 | Vector store (embedding storage + ANN retrieval) | https://www.trychroma.com/ |
| sentence-transformers | 3.2.1 | BGE-M3 embeddings (1024-dim) | https://www.sbert.net/ |
| BAAI/bge-m3 | — | Embedding model | https://huggingface.co/BAAI/bge-m3 |
| transformers | 4.45.2 | HuggingFace model loading | https://huggingface.co/docs/transformers/ |
| PyTorch | 2.2.2 | Tensor computation for embeddings | https://pytorch.org/ |
| pdfplumber | 0.11.4 | PDF text extraction | https://github.com/jsvine/pdfplumber |
| PaddleOCR | 2.9.1 | OCR for scanned PDFs | https://github.com/PaddlePaddle/PaddleOCR |
| PaddlePaddle | 2.6.2 | Deep learning backend for PaddleOCR | https://www.paddlepaddle.org.cn/en |
| unstructured | 0.15.13 | DOCX and structured document loading | https://unstructured.io/ |
| MSAL | 1.31.0 | Microsoft identity (SharePoint auth) | https://github.com/AzureAD/microsoft-authentication-library-for-python |
| grpcio / grpcio-tools | — | gRPC client/server for chatbot service | https://grpc.io/ |
| FastAPI | — | REST API used for local development and health checks (not exposed in production) | https://fastapi.tiangolo.com/ |
| psycopg2-binary | 2.9.9 | PostgreSQL driver | https://www.psycopg.org/ |
| tenacity | 9.0.0 | Retry logic with exponential back-off | https://tenacity.readthedocs.io/ |
| httpx | 0.27.2 | Async HTTP client (Graph API calls) | https://www.python-httpx.org/ |
| pytest | 8.3.3 | Test framework | https://docs.pytest.org/ |

### Frontend (Vue 3 / TypeScript)

| Library | Version | Purpose | Source |
|---------|---------|---------|--------|
| Vue 3 | ^3.5.30 | Reactive UI framework | https://vuejs.org/ |
| Vue Router | ^5.0.3 | Client-side routing | https://router.vuejs.org/ |
| Pinia | ^3.0.4 | State management | https://pinia.vuejs.org/ |
| Vite | ^7.3.1 | Build tool and dev server | https://vitejs.dev/ |
| @azure/msal-browser | ^5.6.3 | Azure AD authentication (PKCE) | https://github.com/AzureAD/microsoft-authentication-library-for-js |
| @stomp/stompjs | ^7.3.0 | STOMP WebSocket client | https://stomp-js.github.io/ |
| marked | ^18.0.4 | Markdown rendering for AI responses | https://marked.js.org/ |
| dompurify | ^3.4.6 | HTML sanitisation (XSS prevention) | https://github.com/cure53/DOMPurify |
| Bootstrap 5 | ^5.3.8 | CSS framework | https://getbootstrap.com/ |
| bootstrap-vue-next | ^0.44.0 | Vue 3 Bootstrap components | https://bootstrap-vue-next.github.io/ |
| lucide-vue-next | ^0.577.0 | Icon set | https://lucide.dev/ |
| TypeScript | ~5.9.3 | Type safety | https://www.typescriptlang.org/ |
| Vitest | ^4.0.18 | Unit testing | https://vitest.dev/ |
| @vue/test-utils | ^2.4.6 | Vue component testing utilities | https://test-utils.vuejs.org/ |

### Infrastructure

| Tool | Version | Purpose | Source |
|------|---------|---------|--------|
| Kong | 3.7 | API gateway (DB-less mode) | https://konghq.com/ |
| Nginx | (alpine) | SPA static file server | https://nginx.org/ |
| Docker | — | Containerisation | https://www.docker.com/ |
| Azure Container Apps | — | Serverless container hosting | https://azure.microsoft.com/en-au/products/container-apps |
| Azure Container Registry | — | Docker image registry (`oconnoraiplatform.azurecr.io`) | https://azure.microsoft.com/en-au/products/container-registry |
| Azure Key Vault | — | Secret management (JWT secret, credentials) | https://azure.microsoft.com/en-au/products/key-vault |
| PostgreSQL | — | Relational database (sessions, refresh tokens, ETL tracking) | https://www.postgresql.org/ |
| Ollama | — | Self-hosted LLM server (default: `llama3.2:3b`) | https://ollama.com/ |
| Elasticsearch + Kibana | — | Log aggregation and visualisation | https://www.elastic.co/ |
| Bitbucket Pipelines | — | CI/CD | https://bitbucket.org/product/features/pipelines |

---

## 7. Assumptions & Significant Decisions

### 7.1 Architecture Decisions

**Decision: Kong as the sole public ingress (not individual service ingress)**  
*Rationale:* Centralises JWT rate limiting, CORS, and future auth plugin configuration in one place. All backend services are marked `external: false` in Azure Container Apps so they are unreachable without going through Kong. New services default to internal and receive a Kong route entry rather than being independently exposed.

**Decision: Platform JWT instead of passing Azure AD tokens to downstream services**  
*Rationale:* Azure AD tokens have variable lifetimes and expose Azure internals to every service. A short-lived platform JWT lets us embed exactly the claims we need (email, roles) and rotate them on our own schedule. It also decouples the backend from Azure AD specifics.

**Decision: Refresh token rotation (revoke on use)**  
*Rationale:* Prevents refresh token theft — if a stolen token is used, the legitimate client's next refresh will fail (the old token is already revoked). Accepted trade-off: simultaneous requests with the same refresh token can cause a race condition; mitigated by the short access token lifetime.

**Decision: SHA-256 hash storage for refresh tokens**  
*Rationale:* Storing plaintext refresh tokens in the database creates a high-impact secret if the database is breached. The hash is one-way; the plaintext is only ever sent over TLS to the client and never persisted.

**Decision: Composition over inheritance for `SharePointPipeline`**  
*Rationale:* `MatSharePointConnection` (a colleague's class) is used as a collaborator, not a parent class, to reduce coupling and allow both to evolve independently. Mock mode defers construction of the real client so development can proceed without Azure credentials.

**Decision: Domain-tagged vector chunks (`metadata.domain`)**  
*Rationale:* The platform serves two document domains (`IMS` — internal management system, `Service` — field service documents). Without domain tagging, a question about an IMS procedure could surface unrelated service records. The `RAG_DOMAIN` environment variable on the chatbot service container filters retrieval to one domain at query time.

**Decision: Version filter before ingest**  
*Rationale:* SharePoint often contains multiple versions of the same document (e.g., `Procedure v1 01.01.22.pdf`, `Procedure v2 15.06.23.pdf`). Ingesting all versions bloats the vector store and degrades retrieval precision (older content competes with current). The filter keeps only the most recent revision. Amendments (e.g., `Procedure Amdt 1.pdf`) are always kept alongside the parent because they contain legally binding addenda.

**Decision: `BAAI/bge-m3` embedding model (1024-dim)**  
*Rationale:* Outperforms smaller models on multilingual and domain-specific retrieval benchmarks. The pipeline validates the configured model at startup and aborts if a mismatched model is detected, preventing a silent collection corruption where old 1024-dim vectors coexist with new differently-dimensioned vectors.

**Decision: gRPC between chat-service and chatbot-service**  
*Rationale:* gRPC provides strongly typed contracts (`.proto` schema) and efficient binary serialisation for the potentially large inference payloads. The contract is shared via generated `chatbot_service_pb2.py` and Java stubs.

### 7.2 Assumptions

- Users authenticate via Azure AD. No username/password authentication is implemented or planned.
- All SharePoint documents are in English or use English headings. The OCR and heading detection logic targets English text patterns.
- The `BAAI/bge-m3` model is used consistently across both the ETL service (embedding) and the chatbot service (retrieval). Swapping the model requires re-ingesting all documents.
- The ETL service runs as a single instance. Concurrent ETL runs are not protected against and could result in duplicate chunk IDs. Scheduled interval of 3 days makes this unlikely in practice.
- PaddleOCR 2.x is pinned and must not be upgraded to 3.x without re-verification. Version 3.x has a `pir::ArrayAttribute` bug that causes `.predict()` to fail silently.
- The `shared-security` library handles all JWT filter configuration. Individual services do not define their own `SecurityFilterChain` except `LocalDevSecurityConfig` (which disables security for local development only and is excluded from production profiles).

---

## 8. Version Control

The project uses **Git** for version control, hosted on Bitbucket. Each service has its own `bitbucket-pipelines.yml` for CI/CD, which builds a Docker image and pushes it to Azure Container Registry (`oconnoraiplatform.azurecr.io`).

### Repository Structure
Each service directory contains its own `.gitignore` and `.gitattributes`. The monorepo root holds shared infrastructure files (`kong-gateway/`, `kibana/`, `ollama-service/`).

### Branching Convention
Feature branches are created per SCRUM ticket (e.g., `SCRUM-91` — resilience decorator). Pull requests are required before merging to the main branch.

### Pipeline Versioning (ETL)
The ETL `pipeline_runner.py` uses in-file changelogs to document significant algorithm changes with version numbers and dates:
- v2.0 (24 Apr 2026) — version filter, section-aware chunking, delete-before-update, BGE-M3
- v2.1 (11 May 2026) — folder-structure-aware version filter for Service domain
- v2.2 (11 May 2026) — domain metadata tagging per chunk

### Shared Security Library
`shared-security` is versioned independently and published to an internal Azure Artifacts feed. Services pin a specific version (currently `1.0.7`) in `build.gradle`.

---

## 9. Test Cases, Results & Debugging Notes

### 9.1 ETL Service — Resilience Decorator Tests

**File:** `etl-service/tests/pipeline_module/test_resilience.py`  
**Framework:** pytest 8.3.3  
**SCRUM Ticket:** SCRUM-91

| Test Case | Input / Scenario | Expected | Result |
|-----------|-----------------|----------|--------|
| `test_extract_status_code_from_mat_message` | Exception message `"Cannot list children. Status: 429, Response: {}"` | Parses status code `429` | Pass |
| `test_extract_status_code_alt_format` | Exception message `"Status code: 503, Response: {}"` | Parses status code `503` | Pass |
| `test_extract_status_code_missing` | Exception message `"KeyError on 'foo'"` | Returns `None` | Pass |
| `test_is_retryable_429` | HTTP 429 (Too Many Requests) | Retryable = `True` | Pass |
| `test_is_retryable_503` | HTTP 503 (Service Unavailable) | Retryable = `True` | Pass |
| `test_not_retryable_403` | HTTP 403 (Forbidden) | Retryable = `False` | Pass |
| `test_not_retryable_404` | HTTP 404 (Not Found) | Retryable = `False` | Pass |
| `test_not_retryable_unknown_error` | Non-HTTP exception | Retryable = `False` | Pass |
| `test_retryable_timeout` | `httpx.TimeoutException` | Retryable = `True` | Pass |
| `test_retryable_connect_error` | `httpx.ConnectError` | Retryable = `True` | Pass |
| `test_decorator_succeeds_first_try` | Function succeeds on call 1 | Returns result; 1 call total | Pass |
| `test_decorator_retries_then_succeeds` | Function raises 503 twice, then succeeds | Returns result; 3 calls total | Pass |
| `test_decorator_exhausts_retries` | Function always raises 429 | Raises after `HTTP_MAX_RETRIES` calls | Pass |
| `test_decorator_fails_fast_on_403` | Function raises 403 | Raises immediately; 1 call only | Pass |

**Run command:** `pytest etl-service/tests/pipeline_module/test_resilience.py -v`

**Debugging notes:**
- Mock mode (`PIPELINE_MODE=mock`) is essential for running ETL tests without Azure credentials. The `SharePointPipeline` defers creation of `MatSharePointConnection` in mock mode to avoid calling MSAL `__init__`.
- `monkeypatch.setattr(time, "sleep", lambda s: None)` eliminates real wait times in retry tests. Without this patch, the exponential back-off would make the test suite take minutes.
- Status code parsing uses a regex on the exception message string, not an HTTP response object, because Microsoft Graph SDK exceptions embed the status code in the message text.

---

### 9.2 Frontend — Unit Tests

**File:** `user-interface/src/__tests__/App.spec.ts`  
**Framework:** Vitest 4.0.18, @vue/test-utils  
**Run command:** `npm run test:unit` (inside `user-interface/`)

The frontend test suite covers component mounting and basic rendering. UI integration testing is performed manually against the deployed dev environment.

---

### 9.3 Authentication Service — Spring Boot Tests

**File:** `authentication-service/src/test/java/.../AuthenticationServiceApplicationTests.java`  
**Framework:** JUnit 5

The Spring context load test is currently disabled (commented out) pending a test PostgreSQL datasource configuration. Manual API testing via `curl` / Postman was used to validate:
- Token exchange with a real Azure AD access token returns a valid platform JWT
- Token refresh rotates the refresh token correctly
- Logout revokes the token (subsequent refresh attempts return 401)
- Invalid or expired Azure tokens return 401 with a warning log

---

### 9.4 Chatbot Service — Manual Integration Tests

The chatbot service was tested end-to-end by:
1. Ingesting a set of known documents via the ETL service
2. Querying questions whose answers appear verbatim in the ingested documents
3. Verifying retrieved sources match the expected documents

**Test queries and observations:**

| Query | Expected source document | Retrieved? | Notes |
|-------|-------------------------|:---:|-------|
| "What PPE is required for chemical handling?" | `MSDS Chemical Handling Procedure` | Yes | MSDS section detection correctly labelled chunk as Section 8: Exposure Controls |
| "What is the inspection interval for fire extinguishers?" | `Fire Safety Inspection Checklist` | Yes | — |
| (Out-of-domain query) | None relevant | N/A | LLM correctly stated it could not find relevant information |

**Debugging notes:**
- Pre-warming the BM25 index at startup (`self.rag.retrieve("warmup", ...)`) eliminated a 10–15 second latency on the first query after deployment.
- Domain filtering (`RAG_DOMAIN`) must match the `domain` metadata value stored during ETL. If the ETL service targets `Service/CBD`, the stored domain is `Service` (first path segment only); `RAG_DOMAIN` must be set to `Service` on the chatbot container, not `Service/CBD`.
- PaddleOCR 2.9.1 must be pinned. During development, upgrading to 3.x caused `pir::ArrayAttribute` errors and silent OCR failures where scanned PDFs returned empty strings.

---

### 9.5 Kong Gateway — Manual API Tests

| Test | Request | Expected | Result |
|------|---------|----------|--------|
| Rate limit enforcement | 21 rapid POST `/api/auth/token` requests | 21st request returns HTTP 429 | Pass |
| CORS preflight | OPTIONS `/api/chat-sessions` | `Access-Control-Allow-Origin: *` in response headers | Pass |
| Path routing — auth | POST `/api/auth/token` | Routes to authentication-service | Pass |
| Chatbot not publicly routed | Direct POST to `/api/chatbot/ask` (bypassing Kong) | No route exists; connection refused | Pass — chatbot is internal gRPC only |
| Backend unreachable | Chat service stopped | Kong returns HTTP 502 | Pass |

---
