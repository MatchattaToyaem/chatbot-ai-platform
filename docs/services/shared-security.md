# Shared Security

Spring Boot auto-configuration library providing **shared JWT validation, WebSocket security, and request logging** for all Java backend services in the O'Connors AI Platform.

## Responsibility

This is an internal library (not a deployed service). It is included as a Gradle dependency by the authentication-service, chat-service, document-service, and evaluation-service to ensure consistent security behaviour across the platform.

- Validates platform JWTs issued by the authentication-service (HS256, shared secret).
- Secures REST endpoints — anonymous access to `/api/auth/**` and actuator; all other paths require a valid JWT.
- Intercepts incoming WebSocket (STOMP) connections and validates the `Authorization` header before the connection is accepted.
- Adds structured request/response logging (HTTP method, path, status, duration) via a servlet filter.

## Auto-Configured Components

| Class                                  | Responsibility                                                         |
|----------------------------------------|------------------------------------------------------------------------|
| `PlatformJwtAutoConfiguration`         | Registers a `JwtDecoder` bean that verifies HS256 platform tokens     |
| `SecurityConfig`                       | Configures Spring Security HTTP rules (public vs. protected paths)    |
| `WebSocketSecurityAutoConfiguration`   | Registers the WebSocket channel interceptor                            |
| `WebSocketSecurityConfig`              | STOMP message security policy (require authenticated principal)        |
| `WebSocketAuthChannelInterceptor`      | Reads the JWT from the STOMP `Authorization` header and authenticates |
| `LoggingAutoConfiguration`             | Registers the request logging filter                                   |
| `RequestLoggingFilter`                 | Logs each request: method, URI, status, duration in ms                |

## How to Use

Add the dependency in your service's `build.gradle`:

```groovy
dependencies {
    implementation project(':shared-security')
}
```

Then set the shared JWT secret in `application.properties`:

```properties
app.jwt.secret=<same-base64-secret-as-authentication-service>
```

The library auto-configures everything via `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`. No `@Import` or `@EnableXxx` annotation is needed.

## Security Rules (default)

```
/api/auth/**     → permitAll (authentication endpoints issue tokens)
/actuator/**     → permitAll (health checks)
/ws/**           → permitAll at HTTP level (WebSocket handshake)
everything else  → requireAuthenticated (platform JWT required)
```

## Build

```bash
cd shared-security
./gradlew build
```

The resulting JAR is published to the local Maven cache and picked up by dependent services via `implementation project(':shared-security')`.
