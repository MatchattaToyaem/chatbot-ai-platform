#!/bin/bash
set -e

MODEL=${LLM_MODEL:-llama3.2:3b}

ollama serve &

echo "Waiting for Ollama to start..."
sleep 10

echo "Pulling model: $MODEL"
ollama pull $MODEL

echo "Model ready. Ollama is running."
wait
