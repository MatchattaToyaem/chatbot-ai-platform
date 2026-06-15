# Document Service

Spring Boot service that **fetches documents directly from SharePoint** on behalf of the frontend and exposes failed ETL document records for admin monitoring.

## Responsibility

- Authenticates with Microsoft Graph API using client credentials (app registration).
- Resolves a SharePoint file path to a binary download and streams it back to the caller with the correct `Content-Type`.
- Exposes a paginated endpoint for viewing documents that failed during the ETL ingestion pipeline.
- Provides an OCR trigger endpoint (placeholder for manual re-processing).

## Endpoints

| Method | Path                        | Auth Required | Description                                             |
|--------|-----------------------------|---------------|---------------------------------------------------------|
| GET    | `/documents/file?path=`     | Platform JWT  | Download a file from SharePoint by its relative path   |
| GET    | `/documents/failed`         | Platform JWT  | List documents that failed ETL ingestion (paginated)   |
| GET    | `/ocr-trigger`              | Platform JWT  | Trigger OCR re-processing (placeholder)                |

### Document Retrieval Example

```
GET /documents/file?path=IMS/Procedures/WHS-001 Work Health Safety Policy.pdf
```

The service:
1. Acquires an app-level token from Azure AD (client credentials flow).
2. Resolves the SharePoint site ID and drive ID via Graph API.
3. Fetches the file content from `drives/{driveId}/root:{path}:/content`.
4. Returns the binary with `Content-Disposition: inline` and the correct MIME type.

### Failed Documents Query Parameters

| Parameter | Type   | Default | Description                              |
|-----------|--------|---------|------------------------------------------|
| `page`    | int    | 0       | Zero-based page number                   |
| `size`    | int    | 20      | Page size                                |
| `from`    | date   | null    | Filter from date (ISO 8601, inclusive)   |
| `to`      | date   | null    | Filter to date (ISO 8601, inclusive)     |

## Key Components

| File                           | Responsibility                                                          |
|--------------------------------|-------------------------------------------------------------------------|
| `DocumentRetrievalController`  | REST endpoint — delegates to service, sets response headers            |
| `DocumentRetrievalService`     | Microsoft Graph API integration: token, site/drive lookup, file fetch  |
| `FailedDocumentController`     | REST endpoint for paginated failed document query                      |
| `FailedDocumentService`        | Queries `etl_file_tracker` table for failed ingestion records          |
| `OcrTriggerController`         | OCR re-trigger endpoint (placeholder)                                  |

## Supported File Types

| Extension | Content-Type                                                               |
|-----------|----------------------------------------------------------------------------|
| `.pdf`    | `application/pdf`                                                          |
| `.docx`   | `application/vnd.openxmlformats-officedocument.wordprocessingml.document` |
| `.xlsx`   | `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`       |
| `.png`    | `image/png`                                                                |
| `.jpg`    | `image/jpeg`                                                               |
| other     | `application/octet-stream`                                                 |

## Configuration

```properties
server.port=8083

# SharePoint connection (Microsoft Graph API)
sharepoint.tenant-id=<tenant-id>
sharepoint.client-id=<client-id>
sharepoint.client-secret=<client-secret>
sharepoint.host=<tenant>.sharepoint.com
sharepoint.site-name=<site-name>

# PostgreSQL — reads etl_file_tracker for failed documents
spring.datasource.url=jdbc:postgresql://localhost:5432/oconnor
spring.datasource.username=postgres
spring.datasource.password=<password>

# Platform JWT validation
app.jwt.secret=<base64-encoded-secret>
```

## Database (Read-Only)

Reads the `etl_file_tracker` table that is written by the ETL service:

```sql
-- example columns
SELECT file_path, status, error_message, last_updated
FROM etl_file_tracker
WHERE status = 'FAILED';
```

## Build & Run

```bash
cd document-service
./gradlew bootRun
```

## Dependencies

- Spring Boot 3 (Web, Security)
- MSAL4J (Microsoft Authentication Library — client credentials)
- Spring RestTemplate (Graph API calls)
- Spring Data JDBC + PostgreSQL driver
- `shared-security` (platform JWT filter)
