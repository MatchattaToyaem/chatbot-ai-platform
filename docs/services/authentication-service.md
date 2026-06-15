# Authentication Service

Spring Boot service that handles the **Azure AD → platform JWT** token exchange flow for the O'Connors AI Platform.

## Responsibility

The platform uses a two-token architecture:

1. Users authenticate with **Microsoft Azure AD** (via MSAL in the frontend).
2. The frontend sends the Azure AD access token to this service in exchange for a short-lived **platform access JWT** and a long-lived **refresh token**.
3. All other backend services validate the platform JWT (via `shared-security`) — they never see the Azure AD token.

## Endpoints

| Method | Path               | Auth Required | Description                                                      |
|--------|--------------------|---------------|------------------------------------------------------------------|
| POST   | `/api/auth/token`  | No            | Exchange an Azure AD access token for platform access + refresh tokens |
| POST   | `/api/auth/refresh`| No            | Rotate a refresh token to obtain a new access + refresh pair    |
| POST   | `/api/auth/logout` | No            | Revoke a refresh token (client-initiated logout)                |
| GET    | `/`                | No            | Public landing page with Microsoft login link                   |
| GET    | `/secure-data`     | Platform JWT  | Test endpoint — echoes name and email from token claims         |

## Token Exchange Flow

```
Frontend (MSAL)
    │  Azure AD access token
    ▼
POST /api/auth/token
    │  1. Validate Azure AD token signature (issuer URI)
    │  2. Extract claims: sub, oid, preferred_username, name
    │  3. Fetch Azure AD directory roles via Graph API (using oid)
    │  4. Issue platform JWT (HS256, 15 min expiry)
    │  5. Create and store refresh token (SHA-256 hash in PostgreSQL)
    ▼
TokenResponse { accessToken, refreshToken, expiresIn }
```

## Token Rotation (Refresh Flow)

```
Frontend
    │  refresh token (plaintext)
    ▼
POST /api/auth/refresh
    │  1. Hash the token with SHA-256
    │  2. Look up hash in refresh_tokens table
    │  3. Check not revoked and not expired
    │  4. Revoke old refresh token
    │  5. Issue new access JWT + new refresh token
    ▼
TokenResponse { newAccessToken, newRefreshToken, expiresIn }
```

## Key Components

| File                      | Responsibility                                                        |
|---------------------------|-----------------------------------------------------------------------|
| `AuthController`          | REST endpoints: token exchange, refresh, logout                      |
| `UserController`          | Landing page + `/secure-data` test endpoint                          |
| `JwtTokenProvider`        | Sign/verify platform JWTs (HS256) and generate opaque refresh tokens |
| `RefreshTokenService`     | Store, validate, rotate, and revoke refresh tokens in PostgreSQL     |
| `AzureGraphService`       | Fetch Azure AD directory role names via Microsoft Graph API          |
| `TokenConfiguration`      | Spring beans wiring for the above components                         |

## Configuration

Copy `application.properties` and populate:

```properties
server.port=8081

# Azure AD — validates incoming Azure tokens
spring.security.oauth2.resourceserver.jwt.issuer-uri=https://login.microsoftonline.com/<tenant-id>/v2.0

# PostgreSQL — stores refresh token hashes
spring.datasource.url=jdbc:postgresql://localhost:5432/oconnor
spring.datasource.username=postgres
spring.datasource.password=<password>

# Platform JWT signing
app.jwt.secret=<base64-encoded-secret>
app.jwt.access-token-expiry=900        # seconds (15 minutes)
app.jwt.refresh-token-expiry=604800    # seconds (7 days)

# Azure AD app registration — for Graph API role lookup
azure.tenant-id=<tenant-id>
azure.client-id=<client-id>
azure.client-secret=<client-secret>
```

## Database Schema

The service uses a `refresh_tokens` table (in the shared `oconnor` PostgreSQL database):

```sql
CREATE TABLE refresh_tokens (
    id          BIGSERIAL PRIMARY KEY,
    token_hash  VARCHAR(64) UNIQUE NOT NULL,  -- SHA-256 hex
    user_id     VARCHAR(255) NOT NULL,
    user_email  VARCHAR(255),
    user_name   VARCHAR(255),
    user_roles  TEXT,                          -- comma-separated
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked     BOOLEAN DEFAULT FALSE,
    revoked_at  TIMESTAMPTZ
);
```

## Build & Run

```bash
cd authentication-service
./gradlew bootRun
```

The service starts on port **8081**.

## Dependencies

- Spring Boot 3 (Web, Security, OAuth2 Resource Server)
- Nimbus JOSE + JWT (HS256 signing)
- MSAL4J (Azure AD token validation)
- Spring JDBC + PostgreSQL driver (refresh token storage)
- `shared-security` (platform JWT filter, request logging)
