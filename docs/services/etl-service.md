# ETL Service

Python service that **extracts documents from SharePoint, processes them, and loads vector embeddings into ChromaDB** for the O'Connors AI Platform.

## Responsibility

- Connects to SharePoint via Microsoft Graph API and scans a target folder (e.g. `IMS` or `Service`).
- Filters to only the **latest version** of each document (version-aware deduplication by filename).
- Downloads files locally, extracts text (PDF, DOCX, XLSX), chunks the text, and embeds it with **BGE-M3**.
- Stores chunks + embeddings in a remote ChromaDB instance (Azure Container Apps).
- Tags every chunk with a `domain` field (`IMS` or `Service`) for per-domain retrieval filtering.
- Tracks processed files in PostgreSQL (`etl_file_tracker`) so the document-service can report failures.

## Pipeline Steps

```
[Step 1] Scan SharePoint target folder
    │  Microsoft Graph API → list of file records
    ▼
[Step 2] Version filter
    │  Group by base filename, keep only the latest (by version number + date)
    │  Amendments (AmdX) are always kept alongside the main document
    ▼
[Step 3] Download files
    │  Save to local ./data/downloads/ directory
    ▼
[Step 4] Extract text
    │  PDF: pdfplumber → PaddleOCR fallback for scanned pages
    │  DOCX/XLSX: python-docx / openpyxl
    │  HEIC/JPG/PNG: skipped (metadata-only fallback chunk)
    ▼
[Step 5] Chunk + tag + store
    │  RecursiveCharacterTextSplitter (1200 chars, 200 overlap)
    │  Section-aware prefix prepended to each chunk (document name + heading)
    │  MSDS chunks get GHS section labels (Section 1–16)
    │  domain metadata injected into every chunk
    │  delete_by_source() old chunks → store() new chunks in ChromaDB
    ▼
[Verify] Count total chunks in ChromaDB collection
```

## Module Structure

```
etl-service/
├── src/
│   ├── main.py                          # Entry point
│   ├── config.py                        # Global config (env vars)
│   ├── pipeline_module/
│   │   ├── pipeline_runner.py           # Main pipeline orchestrator
│   │   ├── sharepoint_pipeline.py       # SharePoint scan + download (mock-capable)
│   │   ├── document_extractor.py        # PDF/DOCX/XLSX text extraction
│   │   ├── vector_store_writer.py       # Chunk → embed → store in ChromaDB
│   │   ├── chroma_client.py             # ChromaDB client factory
│   │   ├── resilience.py                # @with_resilience retry decorator
│   │   ├── config.py                    # Pipeline-specific config
│   │   └── _service_loader.py           # Loads SharePointConnection from src/service/
│   ├── file_tracking_module/
│   │   ├── db_tracker.py                # PostgreSQL file status tracking
│   │   └── sharepoint_connection.py     # Low-level Graph API SharePoint client
│   └── rag_module/
│       ├── chunker.py                   # Text chunking
│       ├── extractor.py                 # Text extraction
│       └── db.py                        # Database helpers
├── tests/                               # Unit tests
└── requirements.txt
```

## Environment Variables

Copy `.env.example` to `.env` (or set as container env vars):

```env
# SharePoint connection
SHAREPOINT_TENANT_ID=<tenant-id>
SHAREPOINT_CLIENT_ID=<client-id>
SHAREPOINT_CLIENT_SECRET=<client-secret>
SHAREPOINT_HOST=<tenant>.sharepoint.com
SHAREPOINT_SITE_NAME=<site-name>

# Target folder to scan (determines the domain tag)
SHAREPOINT_TARGET_FOLDER=IMS      # or "Service"
SHAREPOINT_DOWNLOAD_DIR=./src/data/downloads

# ChromaDB (remote Azure instance)
CHROMA_HOST=<azure-chroma-host>
CHROMA_PORT=443
CHROMA_SSL=true
CHROMA_COLLECTION=oconnors_ims

# Embedding model (must match chatbot-service)
EMBEDDING_MODEL=BAAI/bge-m3
CHUNK_SIZE=1200
CHUNK_OVERLAP=200

# PostgreSQL — file tracking
POSTGRES_HOST=localhost
POSTGRES_DB=oconnor
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<password>

# Pipeline mode: live | mock
PIPELINE_MODE=live
```

## Version Filter Logic

Documents are grouped by **base filename** (version numbers, dates, and amendment tags stripped).

- Within each group, amendments (`AmdX`) are always kept.
- For main documents, the one with the highest `(version, date)` score wins.
- For the `Service` folder, files inside year subdirectories (e.g. `.../2026/file.docx`) are grouped by `(building_path, base_name)` so the same filename in different buildings is not collapsed.

Example:
```
SF33 - After Hours Contact Details.docx       → kept (2026/)
SF33 - After Hours Contact Details 2026.docx  → merged with above
SF33 - After Hours Contact Details 2025.docx  → skipped (older year folder)
```

## Domain Tagging

Every chunk gets a `domain` metadata field set to the first segment of `SHAREPOINT_TARGET_FOLDER`:

| Target Folder  | domain tag  |
|----------------|-------------|
| `IMS`          | `IMS`       |
| `Service`      | `Service`   |
| `Service/CBD`  | `Service`   |

The `RAG_DOMAIN` env var in the chatbot-service uses this field to restrict retrieval.

## Running

```bash
cd etl-service
pip install -r requirements.txt
cp .env.example .env   # edit with your credentials
python src/main.py
```

## Mock Mode

Set `PIPELINE_MODE=mock` to run without hitting SharePoint. The pipeline will use a local JSON fixture and PDF files from `MOCK_LOCAL_PDF_DIR` instead.

## Dependencies

- office365-REST-Python-Client / MSAL (SharePoint / Graph API)
- sentence-transformers + BAAI/bge-m3 (embeddings)
- chromadb (vector store client)
- langchain (text splitting)
- pdfplumber + PaddleOCR (PDF extraction)
- python-docx, openpyxl (DOCX/XLSX extraction)
- psycopg2 (PostgreSQL file tracking)
