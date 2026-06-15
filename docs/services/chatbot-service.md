# Chatbot Service

Python service that powers the **RAG (Retrieval-Augmented Generation) Q&A pipeline** for the O'Connors IMS AI Platform. Exposes both a FastAPI HTTP API and a gRPC server so it can be called by both the chat-service backend and direct HTTP clients.

## Responsibility

- Answers natural-language questions about O'Connors IMS documents.
- Retrieves relevant document chunks from ChromaDB using **hybrid search** (BM25 keyword + BGE-M3 vector, fused with Reciprocal Rank Fusion).
- Generates grounded answers via an LLM (Ollama, HuggingFace, or Azure AI Foundry).
- Supports **conversational context**: maintains the last 3 Q&A turns per session so follow-up questions are understood.
- Detects O'Connors document codes (OF140, CF18, SOP-001, etc.) and boosts exact-match chunks to the top.

## Architecture

```
chat-service (Java)                  Frontend (direct HTTP)
        │  gRPC PromptRequest               │  POST /ask
        ▼                                   ▼
   server.py (gRPC)              app.py (FastAPI)
        │                               │
        └──────────┬────────────────────┘
                   ▼
            RAGService.ask()
                   │
        ┌──────────┼──────────────────┐
        │          │                  │
        ▼          ▼                  ▼
 QuestionRefiner  HybridRetriever  AnswerGenerator
 (LLM rewrites   (BM25 + Vector    (Ollama / HF /
  follow-ups)     + RRF fusion)     Azure Foundry)
        │
        ▼
   ChromaDB (Azure Container Apps or local)
```

## API Endpoints (FastAPI)

| Method | Path      | Description                                                       |
|--------|-----------|-------------------------------------------------------------------|
| POST   | `/ask`    | Full RAG Q&A: retrieve → rerank → generate answer (client-facing)|
| POST   | `/search` | Retrieval only — returns raw chunks with scores (debug/internal) |
| GET    | `/health` | System status: embedder, ChromaDB, LLM provider                  |
| GET    | `/`       | Service info and endpoint documentation                           |

### `/ask` Request

```json
{
  "question": "What is the after-hours call out procedure?",
  "top_k": 5,
  "session_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

### `/ask` Response

```json
{
  "question": "What is the after-hours call out procedure?",
  "answer": "The after-hours call out procedure requires...",
  "sources": [
    { "document": "AHP01 - After Hours Call Out Procedure", "category": "Procedures" }
  ]
}
```

## gRPC Interface

Defined in `chatbot_service.proto`. The chat-service connects to port **50051**.

```protobuf
service HuggingFaceService {
  rpc GenerateResponse(PromptRequest) returns (InferenceReply);
}
message PromptRequest { string prompt = 1; string session_id = 2; }
message InferenceReply { string result = 1; float confidence = 2; repeated Source sources = 3; string model = 4; }
```

## Module Structure

```
chatbot-service/
├── server.py               # gRPC server entry point (port 50051)
├── app.py                  # FastAPI HTTP server entry point (port 8000)
├── config.py               # Environment variable config (AppConfig)
├── rag/
│   ├── service.py          # RAGService — main pipeline orchestrator
│   ├── generator.py        # AnswerGenerator — LLM answer generation
│   ├── hybrid_retriever.py # HybridRetriever — BM25 + vector + RRF
│   ├── reranker.py         # Reranker — domain-aware score boosting
│   ├── prompts.py          # PromptTemplates — IMS-specific prompts
│   ├── question_refiner.py # QuestionRefiner — rewrites follow-up questions
│   └── session_context.py  # SessionContext — fetches chat history from PostgreSQL
├── ingest/
│   ├── pipeline.py         # IngestPipeline — document ingestion orchestrator
│   ├── extractor.py        # TextExtractor — PDF/DOCX/XLSX text extraction
│   ├── chunker.py          # DocumentChunker — overlapping text chunking
│   ├── embedder.py         # Embedder — BGE-M3 embedding wrapper
│   └── store.py            # ChromaStore — ChromaDB client wrapper
└── eval/
    ├── faithfulness_eval.py # Faithfulness evaluation (answer grounded in sources)
    └── retrieval_eval.py    # Retrieval accuracy evaluation
```

## Environment Variables

Copy `.env.example` to `.env`:

```env
# LLM provider: ollama | huggingface | azure-foundry
LLM_PROVIDER=ollama
LLM_MODEL=llama3.2:3b
OLLAMA_ENDPOINT=http://ollama-service:11434

# HuggingFace (if LLM_PROVIDER=huggingface)
HUGGING_FACE_HUB_TOKEN=hf_...
HF_MODEL=meta-llama/Llama-3.1-8B-Instruct

# Azure AI Foundry (if LLM_PROVIDER=azure-foundry)
AZURE_FOUNDRY_KEY=...
AZURE_FOUNDRY_ENDPOINT=...

# ChromaDB
CHROMA_MODE=remote              # remote | local
CHROMA_HOST=<azure-chroma-host>
CHROMA_PORT=443
CHROMA_SSL=true
CHROMA_COLLECTION=oconnors_ims

# Domain filter — restrict retrieval to one SharePoint folder
RAG_DOMAIN=IMS                  # IMS | Service | (unset = all)

# PostgreSQL — for session context
POSTGRES_HOST=localhost
POSTGRES_DB=oconnor
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<password>
```

## Setup

```bash
cd chatbot-service
python -m venv .venv
source .venv/bin/activate         # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env              # then edit .env
```

## Running

**FastAPI HTTP server:**
```bash
uvicorn app:app --host 0.0.0.0 --port 8000 --reload
```

**gRPC server:**
```bash
python server.py
```

Open `http://localhost:8000/docs` for the Swagger UI.

## Document Ingestion

To ingest IMS documents into ChromaDB:

```bash
python run_ingest.py
```

This runs `IngestPipeline` which scans the IMS folder, extracts text, chunks it (1200 chars, 200 overlap), embeds with BGE-M3, and stores in ChromaDB.

## Dependencies

- FastAPI + Uvicorn (HTTP server)
- gRPC (server for chat-service integration)
- ChromaDB (vector store client)
- sentence-transformers + BAAI/bge-m3 (embeddings)
- rank-bm25 (keyword search)
- pdfplumber + PaddleOCR (document extraction)
- python-docx, openpyxl (DOCX/XLSX extraction)
- openai (Ollama + Azure Foundry OpenAI-compatible client)
- huggingface_hub (HuggingFace inference)
- psycopg2 (PostgreSQL for session context)
