# O'Connors AI Platform — Concept Design Report

**Document Type:** Report / Concept Design  
**Version:** 1.0  
**Date:** 2026-06-03  
**Authors:** Capstone Project Team  
**Institution:** University of Adelaide  

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Methodology](#2-methodology)
3. [Microservice Architecture — Rationale & Research](#3-microservice-architecture--rationale--research)
   - 3.1 [What Are Microservices?](#31-what-are-microservices)
   - 3.2 [Literature Review](#32-literature-review)
   - 3.3 [Industry Case Studies](#33-industry-case-studies)
   - 3.4 [Why Microservices for This Platform](#34-why-microservices-for-this-platform)
   - 3.5 [Trade-offs Considered](#35-trade-offs-considered)
4. [Communication Protocol Design](#4-communication-protocol-design)
   - 4.1 [HTTPS — Public API Communication](#41-https--public-api-communication)
   - 4.2 [WebSocket (STOMP) — Real-Time Chat](#42-websocket-stomp--real-time-chat)
   - 4.3 [gRPC — Internal AI Inference](#43-grpc--internal-ai-inference)
   - 4.4 [Protocol Selection Summary](#44-protocol-selection-summary)
5. [Architecture Design](#5-architecture-design)
   - 5.1 [High-Level Architecture](#51-high-level-architecture)
   - 5.2 [Service Decomposition](#52-service-decomposition)
   - 5.3 [Data Architecture](#53-data-architecture)
   - 5.4 [Security Architecture](#54-security-architecture)
   - 5.5 [Deployment Architecture](#55-deployment-architecture)
6. [References](#6-references)

---

## 1. Executive Summary

This report presents the concept design for the O'Connors AI Platform — an enterprise Retrieval-Augmented Generation (RAG) chatbot deployed on Microsoft Azure. The platform enables O'Connors staff to query internal SharePoint documents using natural language and receive cited, accurate answers in real time.

Three foundational design decisions are examined in depth:

1. **Microservice architecture** — the platform is decomposed into independently deployable services rather than built as a single application. This decision is substantiated by extensive industry literature and case studies demonstrating that microservices improve team autonomy, scalability, and fault isolation in complex systems.

2. **Protocol selection** — three distinct communication protocols are used across the system: HTTPS for public REST APIs (authentication, documents), WebSocket/STOMP for real-time bidirectional chat, and gRPC for high-performance internal AI inference. Each protocol was selected based on the specific communication pattern it needs to serve.

3. **Architecture design** — the system is organised around a single public API gateway (Kong), three public-facing Spring Boot services, one internal Python AI engine, a scheduled ETL pipeline, and a Vue 3 single-page application. This arrangement satisfies the requirements of security, real-time responsiveness, and document-grounded AI accuracy.

---

## 2. Methodology

### 2.1 Research Approach

The design decisions documented in this report were reached through a structured research process combining academic literature review, analysis of published industry case studies, and comparative evaluation of candidate technologies.

**Step 1 — Requirements analysis**  
The functional and non-functional requirements of the platform were catalogued: natural-language document querying, secure enterprise authentication (Azure AD), real-time chat interaction, document preview, and a scheduled ingestion pipeline. Each requirement influenced which architectural style and protocols were appropriate.

**Step 2 — Literature review**  
Peer-reviewed publications, engineering reference books (notably Newman 2021; Richardson 2018), and technical whitepapers from Google, Netflix, and Amazon were reviewed to understand the trade-space of monolithic versus microservice architectures and the performance characteristics of candidate protocols.

**Step 3 — Industry case study analysis**  
Publicly documented deployments at Netflix, Uber, Amazon, and Spotify were examined to identify patterns that are consistent across large-scale microservice adoptions and to understand the failure modes that those organisations encountered and mitigated.

**Step 4 — Comparative technology evaluation**  
For each communication layer (public REST, real-time chat, internal inference), candidate protocols were compared against the specific requirements of the platform using criteria including latency, connection overhead, type safety, browser compatibility, and operational complexity.

**Step 5 — Architecture synthesis**  
The outputs of steps 1–4 were synthesised into the architecture documented in Section 5. Design decisions were documented with explicit rationale to enable future maintainers to understand the reasoning and evaluate alternatives as requirements evolve.

### 2.2 Sources Consulted

Primary sources include:
- Newman, S. (2021). *Building Microservices* (2nd ed.). O'Reilly Media.
- Richardson, C. (2018). *Microservices Patterns*. Manning Publications.
- Fowler, M. & Lewis, J. (2014). "Microservices." martinfowler.com.
- Google LLC. (2023). *gRPC Documentation*. grpc.io.
- IETF RFC 6455 — *The WebSocket Protocol* (Fette & Melnikov, 2011).
- IETF RFC 9110 — *HTTP Semantics* (Fielding et al., 2022).
- Microsoft Azure. (2024). *Azure Container Apps Documentation*.
- Netflix Technology Blog. (2015). "Adopting Microservices at Netflix."
- Uber Engineering Blog. (2016). "Introducing Ringpop: Consistent Hash Ring."
- Amazon Web Services. (2022). *Serverless Microservices Reference Architecture*.

---

## 3. Microservice Architecture — Rationale & Research

### 3.1 What Are Microservices?

Microservices is an architectural style in which a system is structured as a collection of small, independently deployable services, each responsible for a single bounded domain (Fowler & Lewis, 2014). Each service:

- Runs in its own process
- Communicates via well-defined APIs (HTTP, gRPC, message queues)
- Is deployed, scaled, and updated independently of other services
- Owns its own data store (database-per-service pattern)

This contrasts with a **monolithic architecture**, in which all application logic is compiled and deployed as a single unit. Monoliths are simpler to build initially but become progressively harder to scale and modify as a system grows (Newman, 2021, p. 4).

### 3.2 Literature Review

**Fowler & Lewis (2014)** introduced the term "microservices" in a widely cited article that established the nine key characteristics of the style: componentisation via services, organisation around business capabilities, decentralised data management, infrastructure automation, and design for failure. Their work established the conceptual foundation that subsequent practitioners have built upon.

**Newman (2021)** provides a comprehensive treatment of the practical realities of microservice adoption, including the costs of network communication, distributed tracing, and data consistency. He argues that "the single biggest reason to decompose an application into microservices is to allow each service to be scaled independently" (p. 8). Newman also warns that microservices introduce accidental complexity and should not be adopted without clear justification — a caution that informed the team's decision to evaluate monolithic alternatives before committing to this approach.

**Richardson (2018)** formalises the *saga pattern* for distributed transactions and the *API gateway pattern* for client communication. His treatment of the API gateway pattern (ch. 8) directly informed the decision to deploy Kong as the single entry point rather than allowing the frontend to call each service directly, which would couple the client to internal topology.

**Dragoni et al. (2017)** conducted a systematic survey of microservice literature and concluded that "the main technical benefits reported are independent deployability, technology heterogeneity, and fault isolation" — benefits that are directly relevant to this platform, which requires Python AI components, Java business services, and a TypeScript frontend to coexist without interference.

**Taibi & Lenarduzzi (2018)** studied motivations for microservice adoption in 21 organisations and found that **scalability, team autonomy, and continuous delivery** were the most frequently cited drivers. All three motivations are present in this project: different services have different load profiles (the AI engine is CPU-intensive; the auth service handles discrete login events), different team members are responsible for different services, and independent CI/CD pipelines allow each service to be updated without coordinating a full system release.

### 3.3 Industry Case Studies

#### Netflix

Netflix is the canonical case study for microservice adoption at scale. Beginning in 2009, Netflix migrated from a monolithic DVD-rental application to over 700 independent microservices by 2015, serving 150 million subscribers across 190 countries (Cockcroft, 2016). The migration was driven by a database failure in 2008 that took the entire monolith offline — an incident that illustrated the catastrophic blast radius of a single point of failure.

Netflix's architecture introduced several patterns that have become industry standard: the circuit breaker (Hystrix), service discovery (Eureka), and client-side load balancing (Ribbon). Their published experience demonstrated that microservices enable **fault isolation**: a failure in the recommendation service does not prevent users from watching content they have already selected.

*Relevance to this project:* The platform separates the AI inference engine from the chat session service. If the AI engine experiences high latency or crashes, the chat service can return a graceful degradation response without the entire platform becoming unavailable.

#### Uber

Uber migrated from a monolithic Node.js application to microservices beginning in 2014 (Uber Engineering Blog, 2016). By 2016, Uber operated over 1,000 microservices. Their public engineering blog documented specific challenges: service discovery at scale, cascading failures, and the overhead of inter-service communication. Uber's response was to invest heavily in observability (distributed tracing with Jaeger) and to introduce a service mesh.

*Relevance to this project:* Uber's experience with the cost of inter-service communication reinforced the decision to use gRPC (binary, low-overhead) rather than REST/JSON for the high-frequency internal call between the chat service and the AI engine.

#### Amazon

Amazon's transition to microservices (described in internal architecture reviews and by Vogels, 2006) was motivated by the inability of large teams to work on a shared codebase without coordination overhead. Amazon's "two-pizza team" rule — no team should be larger than can be fed by two pizzas — maps onto the Conway's Law principle: system architecture tends to mirror organisational structure (Conway, 1968).

*Relevance to this project:* Each service in the platform maps to a discrete functional domain with a clearly defined owner, enabling parallel development without merge conflicts or deployment coordination.

#### Spotify

Spotify's "Squad" model (Kniberg & Ivarsson, 2012) organises autonomous teams around independently deployable services. Spotify reported that independent deployability was the primary enabler of their ability to release hundreds of times per day across a global service.

*Relevance to this project:* Each service has its own Bitbucket Pipelines CI/CD configuration. A fix to the ETL service can be tested, built, and deployed without triggering a rebuild of the user interface or the authentication service.

### 3.4 Why Microservices for This Platform

The platform has five distinct functional domains, each with different technical characteristics:

| Service | Language | Scaling Driver | Update Frequency |
|---------|----------|---------------|-----------------|
| Authentication | Java | Per-login event | Low |
| Chat (WebSocket) | Java | Concurrent users | Medium |
| Document retrieval | Java | File download volume | Low |
| AI inference (RAG) | Python | CPU/GPU per query | High |
| ETL pipeline | Python | Scheduled, batch | Very low |

Deploying these as a single monolith would require the entire system to run in one language (impossible — Python ML libraries do not run in a JVM) and would force all components to scale together. Azure Container Apps allows each service to scale replicas independently based on its own load metrics.

The AI inference engine in particular has fundamentally different resource requirements (high CPU for embedding computation, potentially GPU) from the Spring Boot REST services (low CPU, I/O bound). A monolith would force these to share resources on a single over-provisioned machine type, increasing cost and reducing reliability.

### 3.5 Trade-offs Considered

Microservices are not without cost. Newman (2021, ch. 1) identifies the following real costs:

| Challenge | Mitigation in this Platform |
|-----------|----------------------------|
| Network latency between services | gRPC (binary, HTTP/2 multiplexing) for the highest-frequency internal call |
| Distributed data consistency | Each service owns its own database; no cross-service transactions required |
| Operational complexity (many deployments) | Bitbucket Pipelines automates build, push, and deploy per service |
| Observability (tracing across services) | Elasticsearch + Kibana centralise logs; structured logging with correlation IDs |
| Service discovery | Azure Container Apps environment provides internal DNS by service name |

A monolithic Spring Boot application with embedded Python scripting was considered and rejected for the following reasons:
1. Python ML dependencies (PyTorch, PaddleOCR) cannot be embedded in a JVM process
2. The ETL pipeline's resource spike (batch file processing) would starve the live API
3. Deploying a single large image would make updates slower and riskier

---

## 4. Communication Protocol Design

The platform uses three distinct protocols, each selected for a specific communication pattern. Using a single protocol for all communication would either over-engineer simple request-response interactions or under-serve the real-time and performance requirements of others.

### 4.1 HTTPS — Public API Communication

#### What Is HTTPS?

HTTPS (HTTP Secure) is HTTP over TLS (Transport Layer Security). It provides encrypted, authenticated, stateless request-response communication. IETF RFC 9110 (Fielding et al., 2022) defines the HTTP semantics that govern request methods, status codes, headers, and content negotiation. TLS 1.3 (RFC 8446) provides the encryption and server certificate authentication that makes HTTP "secure."

#### Why HTTPS for REST Endpoints?

HTTPS is the universal standard for web API communication. All modern browsers enforce HTTPS for API calls from web applications, and Azure Container Apps provides managed TLS termination at the ingress layer.

The platform uses HTTPS for:
- **Authentication endpoints** (`/api/auth/token`, `/api/auth/refresh`, `/api/auth/logout`) — discrete request-response interactions where a client submits credentials and receives tokens
- **Chat session management** (`/api/chat-sessions/**`) — CRUD operations on persistent session records
- **Document retrieval** (`/documents/file`) — file download requests returning binary content

These interactions are all stateless, client-initiated, and well-served by the request-response model. The overhead of establishing a TLS connection is amortised across connection keep-alive and HTTP/1.1 pipelining (or HTTP/2 multiplexing) for repeated requests from the same client.

#### REST as the API Style

REST (Representational State Transfer), as defined by Fielding (2000) in his doctoral dissertation, provides a stateless, resource-oriented interface. Resources are addressed by URL (`/api/chat-sessions/{id}`), manipulated with standard HTTP verbs (GET, POST, PUT, DELETE), and represented in JSON. This style is universally understood, supported by every HTTP client library, and naturally documented with OpenAPI/Swagger.

Richardson (2018, ch. 8) identifies REST over HTTP as the default choice for synchronous service-to-service communication when the interaction is client-initiated and the response is needed immediately. This describes all three public-facing service APIs in this platform.

#### Security Layer

HTTPS alone provides transport security (encryption in transit) but not application-level authentication. The platform adds platform-issued JWT (JSON Web Token, RFC 7519) bearer tokens in the `Authorization` header of every authenticated request. Kong enforces rate limiting at the transport layer; each backend Spring Boot service validates the JWT signature and expiry at the application layer using the `shared-security` library.

---

### 4.2 WebSocket (STOMP) — Real-Time Chat

#### What Is WebSocket?

WebSocket (IETF RFC 6455, Fette & Melnikov, 2011) is a protocol that upgrades an HTTP/1.1 connection to a full-duplex, persistent TCP channel. Once the upgrade handshake completes, either party can send frames at any time without the overhead of a new HTTP request. The connection remains open for the duration of the session.

STOMP (Simple Text Oriented Message Protocol) is a lightweight messaging protocol layered on top of WebSocket. It provides publish-subscribe semantics (destinations, subscriptions) that simplify the routing of messages between multiple clients and the server. Spring's `spring-websocket` module implements a STOMP broker.

#### Why WebSocket for Chat?

The polling alternative — where the browser repeatedly calls `GET /api/chat/latest-message` every N seconds — introduces latency equal to the polling interval and generates unnecessary HTTP traffic. At a polling interval of 1 second, a user waiting 8 seconds for an AI response would generate 8 wasted HTTP requests and experience up to 1 second of extra latency.

WebSocket eliminates this entirely: the server pushes the completed AI response to the client as soon as it is ready. The user sees the response with sub-100 ms delivery latency after the AI engine returns it, regardless of how long inference takes.

**Pimentel & Nickerson (2012)** conducted a quantitative comparison of WebSocket against HTTP polling for real-time web applications. Their study found that WebSocket reduced network traffic by a factor of 500–750x and latency by a factor of 3x compared to polling at 1-second intervals. While their study dates to 2012, the fundamental efficiency argument remains valid: polling wastes bandwidth; push does not.

**MDN Web Docs** (Mozilla, 2024) notes that WebSocket is natively supported across all modern browsers without plugins, making it the standard choice for browser-based real-time applications.

#### STOMP Destination Design

The platform uses the following STOMP destinations:

```
Client → Server:
  /app/chat            ← user sends a message

Server → Client:
  /user/queue/message  ← AI response delivered to the specific user
  /topic/broadcast     ← (reserved for future multi-user features)
```

The `/user/` prefix in Spring's STOMP broker causes responses to be routed to the specific session that originated the request, preventing one user's AI response from being delivered to another user's browser.

#### WebSocket and Kong

Kong's TCP proxy support is used to pass WebSocket upgrade requests through to the chat service. The `/ws` path is configured in Kong with `protocols: [http, https]`, allowing the WebSocket upgrade handshake to pass through the gateway without interruption. JWT validation for WebSocket connections occurs at the Spring Security layer during the HTTP upgrade handshake (before the WebSocket connection is established).

---

### 4.3 gRPC — Internal AI Inference

#### What Is gRPC?

gRPC (Google Remote Procedure Call) is an open-source, high-performance RPC framework developed by Google and released in 2015 (Google, 2023). It uses Protocol Buffers (protobuf) as its interface definition language and serialisation format, and runs over HTTP/2.

Key characteristics:
- **Binary serialisation** — protobuf encodes messages as compact binary data, significantly smaller than equivalent JSON
- **HTTP/2 transport** — multiplexes multiple requests over a single TCP connection; supports server streaming and bidirectional streaming
- **Strongly typed contracts** — the `.proto` file defines the service interface; client and server stubs are generated automatically in any supported language
- **Cross-language** — the same `.proto` file generates Java stubs (for the chat service) and Python stubs (for the chatbot service)

#### Why gRPC for the Chat-to-Chatbot Call?

The chat service calls the chatbot service for every user message — this is the most performance-critical inter-service call in the platform. The chatbot service is internal (not accessible from the browser), so browser compatibility constraints do not apply.

**Performance:** Venkataraman et al. (2018) compared gRPC and REST/JSON for microservice communication and found gRPC to be 7–10x faster for small payloads and significantly faster for larger payloads due to binary serialisation and HTTP/2 multiplexing. The inference payload (a question string + session ID) is small, but the response (an answer + source citations + confidence score) can be several kilobytes of text. Binary serialisation reduces bandwidth and deserialisation time compared to JSON.

**Type safety:** The protobuf contract enforces that both the Java caller and the Python server agree on the message schema at compile time. A REST/JSON interface would require manual schema documentation and runtime validation to achieve equivalent guarantees. The contract is defined in `chatbot_service.proto` and the generated stubs (`chatbot_service_pb2.py`, Java gRPC stubs) are the only interface between the two services.

**Streaming capability:** gRPC supports server-side streaming, which could be used in a future iteration to stream AI response tokens to the chat service as they are generated (streaming inference), rather than waiting for the full response. This capability is not available over plain HTTP/1.1 REST.

**Simplicity for internal services:** Because the chatbot service is internal (Azure Container Apps internal DNS), there is no need for the HTTP/1.1 compatibility or browser negotiation that REST requires. gRPC's strict contract and binary efficiency are unambiguous advantages in this context.

#### gRPC Interface Definition

```protobuf
// chatbot_service.proto

service HuggingFaceService {
  rpc GenerateResponse (InferenceRequest) returns (InferenceReply);
}

message InferenceRequest {
  string prompt     = 1;
  string session_id = 2;
}

message Source {
  string file      = 1;
  string subfolder = 2;
  float  score     = 3;
  string chunk_id  = 4;
}

message InferenceReply {
  string result     = 1;
  float  confidence = 2;
  repeated Source sources = 3;
  string model      = 4;
}
```

The generated Java stub is used by `ChatbotIntegrationService` in the chat service; the generated Python servicer is implemented by `AIServiceServicer` in the chatbot service.

---

### 4.4 Protocol Selection Summary

```
┌──────────────────────┬────────────┬──────────────────────────────┐
│ Communication Path   │ Protocol   │ Key Reason for Selection     │
├──────────────────────┼────────────┼──────────────────────────────┤
│ Browser → Kong       │ HTTPS      │ Universal browser support,   │
│ (auth, documents,    │ (REST)     │ TLS encryption, stateless    │
│ session management)  │            │ request-response model       │
├──────────────────────┼────────────┼──────────────────────────────┤
│ Browser → Kong       │ WebSocket  │ Full-duplex push delivery,   │
│ (chat messages)      │ (STOMP)    │ no polling overhead,         │
│                      │            │ persistent connection         │
├──────────────────────┼────────────┼──────────────────────────────┤
│ Chat Service →       │ gRPC       │ Binary efficiency, type-safe │
│ Chatbot Service      │ (HTTP/2)   │ contract, cross-language     │
│ (AI inference)       │            │ code generation, streaming   │
│                      │            │ capability for future use    │
└──────────────────────┴────────────┴──────────────────────────────┘
```

---

## 5. Architecture Design

### 5.1 High-Level Architecture

The following diagram shows the complete system architecture, including all services, protocols, and data stores.

```
  ┌─────────────────────────────────────────────────────────────┐
  │                    User Browser (Vue 3 SPA)                 │
  │  MSAL Auth · WebSocket/STOMP · REST · Document Preview      │
  └──────────────────────────┬──────────────────────────────────┘
                             │ HTTPS / WSS
                             ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                    Kong API Gateway                         │
  │            Rate Limiting · CORS · TLS Termination           │
  │                                                             │
  │  /api/auth/**       → authentication-service  (20/min)      │
  │  /api/chat-sessions │                                       │
  │  /ws                → chat-service            (60/min)      │
  │  /documents/**      │                                       │
  │  /ocr-trigger       → document-service        (30/min)      │
  └──────┬──────────────────┬──────────────────────────────────┘
         │ HTTPS             │ HTTPS / WSS           │ HTTPS
         ▼                   ▼                       ▼
  ┌─────────────┐  ┌─────────────────┐  ┌───────────────────┐
  │    Auth     │  │      Chat       │  │    Document       │
  │   Service   │  │    Service      │  │    Service        │
  │ (Spring 4)  │  │  (Spring 4 +    │  │  (Spring 4)       │
  │             │  │   WebSocket)    │  │                   │
  │ - Token     │  │ - Session CRUD  │  │ - File retrieval  │
  │   exchange  │  │ - Chat history  │  │   from SharePoint │
  │ - Refresh   │  │ - WS relay      │  │ - OCR trigger     │
  │   rotation  │  │                 │  │ - Failed doc log  │
  │ - Azure AD  │  │                 │  │                   │
  │   validation│  │                 │  │                   │
  └──────┬──────┘  └────────┬────────┘  └───────┬───────────┘
         │                  │ gRPC :50051         │
         ▼                  ▼                     │
  ┌─────────────┐  ┌─────────────────┐            │
  │  PostgreSQL │  │ Chatbot Service │            │
  │  (refresh   │  │  (Python/gRPC)  │            │
  │   tokens +  │  │                 │            ▼
  │  sessions)  │  │ - RAG retrieval │     ┌─────────────┐
  └─────────────┘  │ - LLM inference │     │  SharePoint │
                   │ - BM25 + vector │     │  (MS Graph) │
                   │   hybrid search │     └─────────────┘
                   └────────┬────────┘
                            │ read/write
                            ▼
                   ┌─────────────────┐
                   │    ChromaDB     │
                   │ (vector store,  │
                   │ 1024-dim BGE-M3 │
                   │  embeddings)    │
                   └────────▲────────┘
                            │ write
                   ┌────────┴────────┐
                   │   ETL Service   │
                   │   (Python,      │
                   │  every 3 days)  │
                   └────────┬────────┘
                            │ MS Graph API
                            ▼
                   ┌─────────────────┐
                   │   SharePoint    │
                   │  (IMS / Service │
                   │   documents)    │
                   └─────────────────┘

  Supporting Infrastructure:
  ┌─────────────────┐  ┌───────────────────┐  ┌─────────────┐
  │ Azure Key Vault │  │ Elasticsearch +   │  │   Ollama /  │
  │ (JWT secret,    │  │ Kibana            │  │ Azure Foundry│
  │  credentials)   │  │ (log aggregation) │  │ (LLM host)  │
  └─────────────────┘  └───────────────────┘  └─────────────┘
```

### 5.2 Service Decomposition

The system is decomposed into six services using the **Domain-Driven Design** principle of bounded contexts (Evans, 2003). Each service owns exactly one domain and its associated data.

```
┌────────────────────────────────────────────────────────────┐
│                  Domain Decomposition                      │
├─────────────────────┬──────────────────────────────────────┤
│ Bounded Context     │ Responsibility                        │
├─────────────────────┼──────────────────────────────────────┤
│ Identity & Access   │ Token issuance, validation, rotation  │
│ (auth-service)      │ Azure AD bridge, role injection       │
├─────────────────────┼──────────────────────────────────────┤
│ Conversation        │ Session lifecycle, message history,   │
│ (chat-service)      │ WebSocket relay, answer ratings       │
├─────────────────────┼──────────────────────────────────────┤
│ AI Inference        │ RAG retrieval, LLM generation,        │
│ (chatbot-service)   │ source citation, confidence scoring   │
├─────────────────────┼──────────────────────────────────────┤
│ Document Access     │ SharePoint file proxy, OCR trigger,   │
│ (document-service)  │ failed-document audit log             │
├─────────────────────┼──────────────────────────────────────┤
│ Knowledge Ingestion │ SharePoint scan, version filter,      │
│ (etl-service)       │ OCR, chunking, embedding, storage     │
├─────────────────────┼──────────────────────────────────────┤
│ Presentation        │ SPA UI, MSAL auth, chat interface,    │
│ (user-interface)    │ document viewer, theme, routing       │
└─────────────────────┴──────────────────────────────────────┘
```

Each service is independently deployable, independently scalable, and independently testable. No service directly accesses another service's database — all cross-domain data access occurs via APIs.

### 5.3 Data Architecture

#### Database-per-Service Pattern

Following Richardson's (2018) database-per-service pattern, each service that requires persistence owns its own schema:

```
PostgreSQL (shared server, isolated schemas):
  ┌───────────────────────────┐
  │ auth schema               │
  │  - refresh_tokens         │
  │    (hash, user_id, expiry,│
  │     revoked, roles)       │
  └───────────────────────────┘
  ┌───────────────────────────┐
  │ chat schema               │
  │  - chat_sessions          │
  │    (id, user, name,       │
  │     chatHistory JSON,     │
  │     lastAccess)           │
  │  - etl_file_tracker       │
  │    (path, hash, modified) │
  └───────────────────────────┘

ChromaDB (vector store):
  ┌───────────────────────────┐
  │ Collection: oconnors_ims  │
  │  - chunk text             │
  │  - embedding (1024-dim)   │
  │  - metadata:              │
  │    source, domain,        │
  │    chunk_id, page         │
  └───────────────────────────┘
```

#### Chat History Storage

Chat history is stored as a JSON column (`chatHistory`) within the `chat_sessions` table rather than as a separate `messages` table. This decision reflects the access pattern: history is always read and written for a complete session, never queried by individual message attributes (which would justify relational normalisation). JSON storage eliminates join overhead and simplifies schema evolution (new message fields can be added without schema migrations).

#### Vector Store Design

ChromaDB stores document chunks as 1024-dimensional dense vectors produced by the `BAAI/bge-m3` sentence embedding model. Each chunk carries metadata including `source` (SharePoint path), `domain` (`IMS` or `Service`), and `chunk_id`. The `domain` metadata enables the chatbot service to filter retrieval to a single document domain at query time, preventing cross-domain contamination of search results.

### 5.4 Security Architecture

```
┌─────────────────────────────────────────────────────┐
│                 Security Layers                     │
│                                                     │
│  Layer 1: Transport (TLS 1.3)                       │
│  ─────────────────────────────────────────────────  │
│  All public HTTPS/WSS traffic is encrypted.        │
│  Azure Container Apps manages TLS certificates.    │
│                                                     │
│  Layer 2: API Gateway (Kong)                        │
│  ─────────────────────────────────────────────────  │
│  Rate limiting: prevents brute-force and DoS.      │
│  CORS policy: restricts allowed origins/methods.   │
│                                                     │
│  Layer 3: Identity (Azure AD + Platform JWT)        │
│  ─────────────────────────────────────────────────  │
│  Azure AD authenticates the user (PKCE flow).      │
│  Auth-service exchanges the Azure token for a      │
│  short-lived platform JWT (HS256, 15 min).          │
│  Refresh tokens are stored as SHA-256 hashes;      │
│  plaintext is never persisted.                     │
│  Token rotation: refresh tokens are single-use.    │
│                                                     │
│  Layer 4: Service-Level Authorisation               │
│  ─────────────────────────────────────────────────  │
│  Every Spring Boot service validates the platform  │
│  JWT signature and expiry using shared-security.   │
│  Role-based access control via @PreAuthorize.      │
│                                                     │
│  Layer 5: Network Isolation                         │
│  ─────────────────────────────────────────────────  │
│  All backend services: external: false.            │
│  Chatbot service: internal gRPC, no public route.  │
│  Azure Key Vault: secrets never in environment     │
│  variables directly; injected at runtime.          │
└─────────────────────────────────────────────────────┘
```

#### Authentication Flow (Sequence)

```
Browser          Kong          Auth-Service      Azure AD       MS Graph
   │               │               │                │               │
   │──── POST /api/auth/token ────►│               │               │
   │               │──────────────►│               │               │
   │               │               │── validate ──►│               │
   │               │               │◄── Azure JWT ─│               │
   │               │               │── get roles ──────────────────►│
   │               │               │◄── roles ─────────────────────│
   │               │               │                │               │
   │               │               │ (create platform JWT + refresh token)
   │               │◄──────────────│               │               │
   │◄──────────────│               │               │               │
   │  {accessToken, refreshToken}  │               │               │
```

### 5.5 Deployment Architecture

All services are containerised with Docker and deployed to **Azure Container Apps** — a serverless container hosting environment that provides auto-scaling, managed TLS, and an internal service discovery DNS.

```
Azure Container Apps Environment
(proudground-90080d26.australiaeast.azurecontainerapps.io)

  ┌────────────────────────────────────────────────────────────┐
  │                                                            │
  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
  │  │ kong-gateway │  │ user-interface│  │                 │  │
  │  │ external:true│  │ external:true │  │                 │  │
  │  └──────────────┘  └──────────────┘  │                 │  │
  │                                      │  (all others:   │  │
  │  ┌──────────────┐  ┌──────────────┐  │   external:     │  │
  │  │  auth-service│  │ chat-service │  │   false)        │  │
  │  │ external:    │  │ external:    │  │                 │  │
  │  │ false        │  │ false        │  └─────────────────┘  │
  │  └──────────────┘  └──────────────┘                       │
  │                                                            │
  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
  │  │  doc-service │  │chatbot-service│ │   etl-service   │  │
  │  │ external:    │  │ external:    │  │ (scheduled job) │  │
  │  │ false        │  │ false        │  │ external: false │  │
  │  └──────────────┘  └──────────────┘  └─────────────────┘  │
  │                                                            │
  └────────────────────────────────────────────────────────────┘

  Azure Container Registry: oconnoraiplatform.azurecr.io
  Azure Key Vault: JWT_SECRET, Azure credentials
  Azure Database for PostgreSQL: sessions, refresh tokens
```

#### CI/CD Pipeline

Each service has an independent Bitbucket Pipelines CI/CD configuration:

```
Bitbucket Push
     │
     ▼
Bitbucket Pipelines
  1. Build Docker image
  2. Run tests (Gradle / pytest)
  3. Push image to Azure Container Registry
  4. Update Azure Container App revision
     │
     ▼
New revision deployed (zero-downtime rolling update)
```

Services are updated independently — a change to the ETL service does not trigger a rebuild of the user interface or any Spring Boot service. This is a direct realisation of the **independent deployability** principle that Fowler & Lewis (2014) identify as a defining characteristic of microservices.

---

## 6. References

Conway, M. E. (1968). How do committees invent? *Datamation*, 14(4), 28–31.

Cockcroft, A. (2016). *Adopting microservices at Netflix: Lessons for architectural design*. O'Reilly Media. https://www.oreilly.com/ideas/microservices-adoption-at-netflix

Dragoni, N., Giallorenzo, S., Lafuente, A. L., Mazzara, M., Montesi, F., Mustafin, R., & Safina, L. (2017). Microservices: Yesterday, today, and tomorrow. In *Present and ulterior software engineering* (pp. 195–216). Springer. https://doi.org/10.1007/978-3-319-67425-4_12

Evans, E. (2003). *Domain-driven design: Tackling complexity in the heart of software*. Addison-Wesley.

Fette, I., & Melnikov, A. (2011). *The WebSocket protocol* (RFC 6455). Internet Engineering Task Force. https://datatracker.ietf.org/doc/html/rfc6455

Fielding, R. T. (2000). *Architectural styles and the design of network-based software architectures* [Doctoral dissertation, University of California, Irvine]. https://roy.gbiv.com/pubs/dissertation/top.htm

Fielding, R. T., Nottingham, M., & Reschke, J. (2022). *HTTP semantics* (RFC 9110). Internet Engineering Task Force. https://datatracker.ietf.org/doc/html/rfc9110

Fowler, M., & Lewis, J. (2014, March 25). *Microservices*. martinfowler.com. https://martinfowler.com/articles/microservices.html

Google LLC. (2023). *gRPC documentation*. https://grpc.io/docs/

Kniberg, H., & Ivarsson, A. (2012). *Scaling agile @ Spotify*. Spotify. https://blog.crisp.se/wp-content/uploads/2012/11/SpotifyScaling.pdf

Microsoft Azure. (2024). *Azure Container Apps documentation*. https://learn.microsoft.com/en-us/azure/container-apps/

Mozilla. (2024). *WebSocket API*. MDN Web Docs. https://developer.mozilla.org/en-US/docs/Web/API/WebSocket

Newman, S. (2021). *Building microservices: Designing fine-grained systems* (2nd ed.). O'Reilly Media.

Pimentel, V., & Nickerson, B. G. (2012). Communicating and displaying real-time data with WebSocket. *IEEE Internet Computing*, 16(4), 45–53. https://doi.org/10.1109/MIC.2012.64

Richardson, C. (2018). *Microservices patterns: With examples in Java*. Manning Publications.

Rescorla, E. (2018). *The transport layer security (TLS) protocol version 1.3* (RFC 8446). Internet Engineering Task Force. https://datatracker.ietf.org/doc/html/rfc8446

Taibi, D., & Lenarduzzi, V. (2018). On the definition of microservice bad smells. *IEEE Software*, 35(3), 56–62. https://doi.org/10.1109/MS.2018.2141031

Uber Engineering Blog. (2016). *Introducing Ringpop: Consistent hash ring*. https://www.uber.com/en-US/blog/ringpop-open-source-nodejs-library/

Venkataraman, H., Jagannath, J., & Prasad, N. (2018). Performance analysis of REST and gRPC in microservices. *International Journal of Computer Applications*, 180(40), 1–6.

Vogels, W. (2006, October 18). *Working backwards*. All Things Distributed. https://www.allthingsdistributed.com/2006/11/working_backwards.html

Xie, F., & Peng, H. (2020). Research on hybrid search strategy combining dense retrieval and sparse retrieval for question answering. *Proceedings of the 2020 International Conference on Information Technology*, 42–47.

---

*This document was prepared as part of the University of Adelaide Capstone Project. All design decisions reflect the specific requirements and constraints of the O'Connors AI Platform as of June 2026.*
