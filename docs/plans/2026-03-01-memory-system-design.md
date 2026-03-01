# All-Day Memory System Design

## Overview

The memory system is All-Day's foundation — a persistent, searchable store of every AI agent's conversation history and accumulated expertise. It ingests conversation transcripts (starting with Claude Code JSONL files), breaks them into topic-based summary chunks, and makes them searchable via semantic search. This enables agents to discover and learn from each other's past work.

## Architecture

Monolithic Rails 8 API application with Sidekiq for async summarization and PostgreSQL + pgvector for storage and semantic search.

## Data Model

### Users

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| name | string | |
| email | string | unique |
| api_key | string | unique, indexed, for API auth |
| created_at | timestamp | |

### Agents (Agent Identities)

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| user_id | bigint | FK → users, the user who owns this agent |
| name | string | e.g. "auth-specialist", "frontend-dev" |
| model | string | e.g. "claude-opus-4-6" |
| model_config | jsonb | temperature, max_tokens, etc. |
| parent_id | bigint | FK → agents, nullable, for branched agents |
| origin | enum | blank_slate, continued, branched |
| metadata | jsonb | |
| created_at | timestamp | |

### Transcripts (Session Containers)

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| agent_id | bigint | FK → agents |
| source | string | e.g. "claude-code", "allday" |
| source_session_id | string | original session ID from source |
| status | enum | active, completed |
| started_at | timestamp | |
| completed_at | timestamp | nullable |
| metadata | jsonb | project path, git repo, etc. |

### Messages

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| transcript_id | bigint | FK → transcripts |
| agent_id | bigint | FK → agents |
| role | enum | user, assistant, system, tool_call, tool_result |
| content | text | |
| thinking | text | nullable, for extended thinking blocks |
| sequence | integer | ordering within transcript |
| timestamp | timestamp | |
| metadata | jsonb | tool names, model info, etc. |

### Memory Chunks (Shallow Memory)

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| transcript_id | bigint | FK → transcripts |
| agent_id | bigint | FK → agents |
| topic | string | short label, e.g. "debugged auth flow" |
| summary | text | 2-3 paragraph description |
| embedding | vector | pgvector column for semantic search |
| skills_demonstrated | text[] | tags like "postgresql", "debugging", "rails" |
| message_range_start | integer | first message sequence in this chunk |
| message_range_end | integer | last message sequence in this chunk |
| created_at | timestamp | |

## API Endpoints

### Agent Identity Management

- `POST /api/v1/agents` — Create agent (blank_slate or branched from parent_id)
- `GET /api/v1/agents/:id` — Agent details including lineage
- `GET /api/v1/agents/:id/memories` — Agent's shallow memory chunks
- `GET /api/v1/agents/:id/transcripts` — Agent's transcript list

### Transcript Streaming Ingestion

- `POST /api/v1/transcripts` — Start a new transcript session. Returns transcript_id.
- `POST /api/v1/transcripts/:id/messages` — Append a message to an active transcript.
- `PATCH /api/v1/transcripts/:id` — Mark transcript completed, triggers summarization.

### Transcript Bulk Import

- `POST /api/v1/transcripts/import` — Upload a full JSONL file. Creates transcript + all messages in one shot, triggers summarization. Params: agent_id, source, source_session_id, metadata, file (JSONL).

### Transcript Retrieval

- `GET /api/v1/transcripts/:id` — Transcript metadata.
- `GET /api/v1/transcripts/:id/messages` — Paginated message list (for loading into consultation agents or dashboard viewing).

### Memory Search

- `GET /api/v1/memories/search` — Semantic search across all shallow memory. Params: query (text), agent_id (optional filter), skills (optional filter), limit. Returns matching memory chunks with agent identity info.

## Summarization Pipeline

1. **Trigger**: Transcript marked `completed` or bulk imported → enqueues `SummarizeTranscriptJob`.
2. **Chunking**: Groups messages into logical conversation segments using topic-change detection via LLM.
3. **Summary generation**: For each topic chunk, LLM produces topic label, summary, and skills_demonstrated tags.
4. **Embedding**: Each summary is embedded via an embedding API and stored in the pgvector column.
5. **Storage**: Memory chunks written to database, linked to transcript and message range.

**Summarization model**: Configurable system-level setting. Defaults to Haiku for cost efficiency, can use Sonnet/Opus for higher quality.

**Idempotency**: Re-summarizing a transcript soft-deletes existing chunks and creates new ones.

## Search and Agent Consultation

### Semantic Search

1. Agent calls search endpoint with a natural language query.
2. Server embeds the query, performs pgvector nearest-neighbor search.
3. Returns top-N memory chunks with topic, summary, skills, agent identity, and transcript reference.

### Agent Consultation (Future — Orchestration Layer)

When an agent finds relevant experience from another agent:

1. Retrieve the relevant agent's transcripts and messages via the API.
2. Launch a new agent instance with those transcripts loaded as context.
3. The calling agent converses with the consultation agent to learn from past experience.
4. The consultation conversation is stored as a new transcript.

The memory API provides all the data; the orchestration layer (future work) handles agent launching.

## Tech Stack

- Ruby 3.3+, Rails 8 (API-only)
- PostgreSQL 16+ with pgvector extension
- Sidekiq + Redis for background jobs
- Anthropic SDK for LLM summarization
- Embedding API (Voyage, OpenAI, or Anthropic) for vector generation
- RSpec for testing, VCR/WebMock for API mocking

## Authentication (MVP)

API key-based. Each user has an API key. Agents authenticate with their owner's key plus an `X-Agent-Id` header.

## Project Structure

```
allday/
  app/
    models/          # User, Agent, Transcript, Message, MemoryChunk
    controllers/
      api/v1/        # AgentsController, TranscriptsController,
                     # MessagesController, MemoriesController
    jobs/            # SummarizeTranscriptJob
    services/        # TranscriptImporter, Summarizer,
                     # EmbeddingService, MemorySearchService
  config/
  db/
    migrate/
```
