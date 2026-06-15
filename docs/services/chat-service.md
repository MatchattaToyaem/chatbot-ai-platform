# Chat Service

Spring Boot service that manages **real-time chat sessions** for the O'Connors AI Platform. It acts as the gateway between the frontend user interface and the Python chatbot service.

## Responsibility

- Provides a **WebSocket (STOMP)** endpoint for real-time Q&A streaming from the browser.
- Manages **chat sessions** (create, read, update, delete) and persists conversation history in PostgreSQL.
- Forwards each user question to the **chatbot-service via gRPC** and returns the AI-generated answer.
- Supports **answer rating** so users can score individual AI responses.

## Endpoints

### WebSocket (STOMP)

| Direction  | Destination            | Description                                               |
|------------|------------------------|-----------------------------------------------------------|
| Client → Server | `/app/chat`     | Send a message with `{ message, sessionId, sender }`     |
| Server → Client | `/user/queue/message` | Receive AI reply with answer, sources, confidence |

### REST — Chat Session Management

| Method | Path                                    | Description                              |
|--------|-----------------------------------------|------------------------------------------|
| GET    | `/api/chat-sessions`                    | List all sessions                        |
| GET    | `/api/chat-sessions/{id}`               | Get a session by UUID                    |
| GET    | `/api/chat-sessions/user/{userName}`    | List sessions for a specific user        |
| POST   | `/api/chat-sessions`                    | Create a new chat session                |
| PUT    | `/api/chat-sessions/{id}`               | Update session name or status            |
| DELETE | `/api/chat-sessions/{id}`               | Delete a session                         |
| PUT    | `/api/chat-sessions/answer-rating/{id}` | Rate an AI answer within a session       |

## Message Flow

```
Browser (Vue.js)
    │  STOMP /app/chat  { message, sessionId }
    ▼
ChatController.sendMessage()
    │  gRPC PromptRequest { prompt, session_id }
    ▼
chatbot-service (Python gRPC server on port 50051)
    │  InferenceReply { result, confidence, sources[], model }
    ▼
ChatController
    │  1. Convert sources to SourceDto[]
    │  2. Append Q&A to chat history in PostgreSQL
    │  3. Build MessageResponse
    ▼
Browser via /user/queue/message
```

## Key Components

| File                          | Responsibility                                                         |
|-------------------------------|------------------------------------------------------------------------|
| `ChatController`              | STOMP message handler — routes questions to chatbot, saves history    |
| `ChatSessionController`       | REST CRUD for chat sessions and answer ratings                         |
| `ChatSessionService`          | Business logic for session management and history updates              |
| `ChatbotIntegrationService`   | Thin gRPC client stub wrapper for the Python chatbot service          |
| `ChatWebsocketHandler`        | Low-level WebSocket text handler (raw fallback, not the main path)    |
| `WebsocketConfiguration`      | STOMP broker and endpoint registration                                 |

## Configuration

```properties
server.port=8082

# gRPC client — address of the Python chatbot service
grpc.client.chatbot-server.address=static://<host>:443
grpc.client.chatbot-server.negotiation-type=tls

# PostgreSQL — chat session storage
spring.datasource.url=jdbc:postgresql://localhost:5432/oconnor
spring.datasource.username=postgres
spring.datasource.password=<password>

# Platform JWT validation (shared secret with authentication-service)
app.jwt.secret=<base64-encoded-secret>

# SharePoint base folder — prefixed to document paths in source references
sharepoint.base-folder=IMS
```

## Database Schema

Chat sessions are stored in the `chat_sessions` table:

```sql
CREATE TABLE chat_sessions (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_name    VARCHAR(255),
    user_name    VARCHAR(255),
    chat_history JSONB,     -- array of ChatHistoryEntry objects
    created_by   VARCHAR(255),
    last_access  TIMESTAMPTZ,
    status       VARCHAR(50)
);
```

Each `chat_history` entry contains:
```json
{
  "answerId": "uuid",
  "question": "...",
  "answer": "...",
  "confidence": 0.85,
  "model": "llama3.2:3b",
  "sources": [...],
  "responseTime": "320ms",
  "responseDate": "2026-06-11T12:00:00Z",
  "rating": 5
}
```

## Build & Run

```bash
cd chat-service
./gradlew bootRun
```

The service starts on port **8082**. WebSocket endpoint: `ws://localhost:8082/ws`.

## Dependencies

- Spring Boot 3 (Web, WebSocket, STOMP, Security)
- grpc-spring-boot-starter (gRPC client)
- Spring Data JPA + PostgreSQL driver
- `shared-security` (platform JWT filter, WebSocket auth interceptor)
