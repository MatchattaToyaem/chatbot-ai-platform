# Ollama Service

Docker container that runs a **self-hosted Ollama LLM server** for the O'Connors AI Platform, providing the LLM inference backend for the chatbot-service.

## Responsibility

- Runs the [Ollama](https://ollama.com/) server, which exposes an OpenAI-compatible HTTP API on port **11434**.
- Pulls and serves the configured LLM model (default: `llama3.2:3b`) on startup.
- Used by the chatbot-service when `LLM_PROVIDER=ollama` (the default provider for self-hosted deployments).

## How It Works

The `entrypoint.sh` script:
1. Starts the Ollama server process in the background.
2. Waits 10 seconds for the server to initialise.
3. Pulls the configured model (`LLM_MODEL` env var, default `llama3.2:3b`).
4. Keeps the container running via `wait`.

## Configuration

| Environment Variable | Default        | Description                        |
|----------------------|----------------|------------------------------------|
| `LLM_MODEL`          | `llama3.2:3b`  | Ollama model to pull and serve     |

## File Structure

```
ollama-service/
├── Dockerfile              # Extends official ollama/ollama image
├── entrypoint.sh           # Startup script: serve + pull model
├── ollama.yaml             # Kubernetes/Container Apps deployment manifest
└── ollama-deploy.yaml      # Alternative deployment manifest
```

## Running Locally

```bash
docker build -t ollama-service .
docker run -p 11434:11434 \
  -e LLM_MODEL=llama3.2:3b \
  ollama-service
```

Once running, the chatbot-service should set:
```env
LLM_PROVIDER=ollama
OLLAMA_ENDPOINT=http://ollama-service:11434
LLM_MODEL=llama3.2:3b
```

## Supported Models

Any model available on [ollama.com/library](https://ollama.com/library) can be configured via `LLM_MODEL`. The model is pulled at container startup, so first boot may take several minutes depending on model size.

| Model          | Size   | Notes                            |
|----------------|--------|----------------------------------|
| `llama3.2:3b`  | ~2 GB  | Default — fast, good quality     |
| `llama3.1:8b`  | ~5 GB  | Larger, better for complex tasks |
| `mistral:7b`   | ~4 GB  | Alternative                      |

## GPU Acceleration

If deployed on a GPU-enabled node, Ollama automatically uses the GPU. For CPU-only deployments, set the container's resource limits accordingly (3B model requires ~4 GB RAM minimum).

## Production Deployment

Deployed to Azure Container Apps via `ollama.yaml`. The deployment uses a persistent volume for model storage so models are not re-downloaded on every container restart.
