# Evaluation Service

Spring Boot service for **AI response quality evaluation** in the O'Connors AI Platform.

## Responsibility

This service is the backend component for evaluating the quality of AI-generated answers. It is designed to:

- Expose REST endpoints for submitting evaluation jobs (planned).
- Aggregate and store evaluation metrics collected by the chatbot-service's Python eval module.
- Provide reporting on RAG pipeline quality (faithfulness, retrieval accuracy, answer relevance).

> **Current status:** Service scaffolding is in place. Evaluation logic is currently implemented in the chatbot-service's `eval/` module (Python). This Java service is the planned backend for storing and surfacing evaluation results through the platform's REST API.

## Planned Endpoints

| Method | Path                      | Description                                     |
|--------|---------------------------|-------------------------------------------------|
| POST   | `/api/evaluations`        | Submit a batch of evaluation results            |
| GET    | `/api/evaluations`        | List evaluation runs with metrics               |
| GET    | `/api/evaluations/{id}`   | Get details for a specific evaluation run       |

## Evaluation Metrics (from chatbot-service eval/)

The Python eval module in `chatbot-service/eval/` computes:

- **Faithfulness**: Are answers grounded in the retrieved source documents?
- **Retrieval accuracy**: Are the most relevant documents retrieved for a given question?
- **Answer relevance**: Does the answer actually address the question?

## Configuration

```properties
server.port=8084

spring.datasource.url=jdbc:postgresql://localhost:5432/oconnor
spring.datasource.username=postgres
spring.datasource.password=<password>

app.jwt.secret=<base64-encoded-secret>
```

## Build & Run

```bash
cd evaluation-service
./gradlew bootRun
```

## Running Python Evaluations (chatbot-service)

The evaluation scripts in `chatbot-service/eval/` can be run directly:

```bash
cd chatbot-service
python run_eval.py
```

This runs faithfulness and retrieval evaluations against the live RAG pipeline and outputs a results report.
