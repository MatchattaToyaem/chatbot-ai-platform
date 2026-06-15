# User Interface

Vue 3 + TypeScript frontend for the O'Connors AI Platform. Provides a chat-based interface for querying IMS documents via the platform's RAG pipeline.

## Features

- **Microsoft SSO login** via Azure AD (MSAL.js).
- **Real-time chat** with the AI via WebSocket (STOMP over SockJS).
- **Chat session management** — create, rename, switch between, and delete conversation sessions with persistent history.
- **Answer rating** — users can thumbs-up/down individual AI responses.
- **Document viewer** — view source documents referenced in AI answers (fetched from SharePoint via document-service).
- **Document library** — browse and search ingested IMS documents.
- **Theme switching** — light and dark themes.

## Architecture

```
Login.vue
  │  MSAL redirect → Azure AD
  ▼
authService.ts
  │  Exchange Azure token for platform JWT
  ▼
Chat.vue
  ├── websocketService.ts  →  chat-service /ws (STOMP)
  │     sends: { message, sessionId, sender }
  │     receives: { answer, sources, confidence, model }
  ├── chatSessionService.ts →  chat-service /api/chat-sessions
  │     create/read/update/delete sessions
  └── DocViewer.vue  →  document-service /documents/file?path=
        streams SharePoint file bytes for inline preview
```

## Project Structure

```
user-interface/
├── src/
│   ├── main.ts                     # App entry point + MSAL init
│   ├── App.vue                     # Root component with router-view
│   ├── router/
│   │   └── index.ts                # Vue Router — /login, /chat, /documents
│   ├── views/
│   │   ├── Login.vue               # Microsoft login page
│   │   ├── Chat.vue                # Main chat interface
│   │   └── DocumentLibrary.vue     # Document browsing
│   ├── components/
│   │   ├── ChatInput.vue           # Message input + send button
│   │   ├── ChatMessages.vue        # Message thread display
│   │   ├── ChatSidebar.vue         # Session list sidebar
│   │   ├── ChatTopbar.vue          # Top bar with session name + controls
│   │   ├── DocViewer.vue           # Inline document viewer (PDF/DOCX)
│   │   ├── Intro.vue               # Welcome/onboarding overlay
│   │   ├── LightTheme.vue          # Light theme styles
│   │   ├── ThemeEffects.vue        # Animated theme effects
│   │   ├── MeadowBanner.vue        # Decorative banner
│   │   └── AIPetModal.vue          # AI personality modal
│   ├── services/
│   │   ├── authService.ts          # MSAL + platform token management
│   │   ├── websocketService.ts     # STOMP WebSocket composable
│   │   └── chatSessionService.ts   # Chat session REST API client
│   ├── stores/
│   │   └── userStore.ts            # Pinia store for current user
│   └── models/
│       ├── messageRequest.ts       # Outgoing message type
│       └── messageResponse.ts      # Incoming AI reply type
└── public/
```

## Environment Variables

Create `.env.local`:

```env
VITE_AZURE_CLIENT_ID=<client-id>
VITE_AZURE_AUTHORITY=https://login.microsoftonline.com/<tenant-id>
VITE_AZURE_REDIRECT_URI=http://localhost:5173
VITE_AZURE_SCOPE=api://<client-id>/access_as_user

VITE_AUTH_SERVICE_URL=http://localhost:8081
VITE_CHAT_SERVICE_URL=http://localhost:8082
VITE_DOCUMENT_SERVICE_URL=http://localhost:8083
```

## Authentication Flow

1. User clicks "Login with Microsoft" on `Login.vue`.
2. MSAL redirects to Azure AD; user authenticates.
3. Azure AD redirects back with an access token.
4. `authService.exchangeToken()` sends the Azure token to authentication-service (`POST /api/auth/token`).
5. The platform access JWT and refresh token are stored in `sessionStorage`.
6. `websocketService.ts` attaches the platform JWT as the STOMP `Authorization` header.
7. The JWT is proactively refreshed 2 minutes before expiry to avoid mid-session disconnects.

## Setup & Run

```bash
cd user-interface
npm install
npm run dev
```

The app runs on `http://localhost:5173` by default.

## Build for Production

```bash
npm run build
```

Output is in `dist/`. Serve with any static host or Nginx.

## Dependencies

- Vue 3 + TypeScript + Vite
- Vue Router 4 (SPA routing)
- Pinia (user state store)
- `@azure/msal-browser` (Microsoft SSO)
- `@stomp/stompjs` (WebSocket / STOMP client)
- `sockjs-client` (WebSocket fallback transport)
