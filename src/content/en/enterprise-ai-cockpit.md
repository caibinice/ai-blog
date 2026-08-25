---
title: Enterprise AI Cockpit: RAG, Vector Search, and Real-Time Streaming
excerpt: Engineering an enterprise AI cockpit featuring decoupled persistent storage, pgvector retrieval with lexical fallbacks, true end-to-end SSE streaming, and strict resource isolation.
---

Transitioning Retrieval-Augmented Generation (RAG) from prototype demonstrations to production enterprise cockpits extends far beyond simple conversational interfaces. Production readiness demands systematic solutions for document metadata and vector synchronization, cross-database cascading deletions, citation provenance tracking, true end-to-end event streaming, and unified resource isolation.

This project delivers an enterprise AI cockpit architecture characterized by high-availability fallbacks and strict resource boundaries, making the entire pipeline—from ingestion to retrieval and streaming generation—fully transparent.

> **August 2026 Update:** This document retains the initial "vector-first, keyword-fallback" architecture notes. The online version has evolved to incorporate structure-aware chunking, dense + keyword hybrid retrieval, Reciprocal Rank Fusion (RRF), validity period filtering, and dynamic adjacent-chunk merging. For comprehensive tuning methodologies, see [Knowledge Engineering and Tunable Cockpits for Enterprise RAG](/articles/enterprise-rag-knowledge-engineering).

## Heterogeneous Storage Architecture and Separation of Concerns

The persistence layer separates relational state from vector embeddings across two specialized databases:

- **MySQL**: Manages structured business entities, including knowledge base configurations, document metadata, external data source connections, report templates, asynchronous execution logs, multi-turn conversation contexts, and access control policies.
- **PostgreSQL + pgvector**: Stores high-dimensional embedding vectors and associated chunk-level metadata.

Relational business workflows rely on ACID transactions, foreign keys, multi-dimensional filtering, and pagination; semantic vector retrieval centers on high-dimensional Approximate Nearest Neighbor (ANN) search via Cosine similarity. Decoupling these workloads preserves clean query pathways and optimal indexing performance across both storage engines.

The document ingestion pipeline operates through discrete stages:

1. **Format Extraction**: Apache Tika extracts clean, unformatted text from PDF, Word, Markdown, and plain text formats;
2. **Text Chunking**: Content is split into bounded segments (e.g., 500 characters with a 50-character overlap) to preserve cross-boundary semantic context;
3. **Embedding Generation**: Dedicated embedding models compute fixed-dimensional vector representations;
4. **Dual Persistence**: Vectors and chunk metadata (document ID, chunk index, character span) are inserted into pgvector, while document-level metadata and processing status are committed to MySQL.

```text
# Document Ingestion Pipeline
raw_text = tika.extract(file)
chunks   = split(raw_text, size=500, overlap=50)
for chunk in chunks:
    vector = embed(chunk.text)
    pgvector.insert(vector, metadata={doc_id, chunk_index, span})
mysql.save(doc_metadata)
```

Chunk metadata enables verifiable citation tracing: when top-k chunks are retrieved via vector distance, the system queries the associated metadata to link each retrieved snippet back to its source document and paragraph in the frontend UI.

During query execution, the system defaults to pgvector for Cosine similarity retrieval, gathering the top-k most relevant text chunks to populate the generation context:

```text
# Query Execution Pipeline
query_vector = embed(user_question)
hits = pgvector.search(query_vector, top_k=5)
if vector_unavailable or len(hits) == 0:
    hits = mysql.keyword_cjk_search(user_question)  # Fallback to lexical CJK search
context = [hit.chunk for hit in hits]
```

To guarantee high availability, the query pipeline includes an automatic fallback mechanism: if pgvector encounters network latency, timeouts, or dimensionality mismatches, search requests fall back to MySQL full-text and CJK lexical search. Although lexical matching lacks deep semantic generalization, it prevents single-point vector outages from disabling conversational workflows.

| Dimension | MySQL | PostgreSQL + pgvector |
| --- | --- | --- |
| Stored Entities | Knowledge bases, document metadata, data sources, templates, logs, conversations | Fixed-dimensional vectors, chunk metadata |
| Access Pattern | ACID transactions, conditional filtering, foreign keys, pagination | Top-k Approximate Nearest Neighbor (ANN) search |
| Core Responsibility | Business workflows and state machine persistence | Semantic recall and similarity computation |
| Query Role | Lexical / CJK fallback retrieval | Primary Cosine vector similarity search |

When a document is deleted, the system first marks the document record as deleted in MySQL, then triggers an asynchronous purge of associated chunks in pgvector, supplemented by scheduled reconciliation routines to clean orphan vector entries.

![RAG Cockpit indexing and querying pipelines, with MySQL and pgvector division of labor](/images/enterprise-ai-cockpit-rag.svg)

## End-to-End True SSE Streaming Architecture

The backend leverages Spring WebFlux and Spring AI. The `ChatClient` consumes Server-Sent Events (SSE) from upstream OpenAI-compatible / DeepSeek endpoints, streaming structured events directly to the Vue frontend in real time.

Unlike local buffered implementations that simulate typewriter animations after generation completes, end-to-end streaming renders the initial tokens as soon as the upstream model emits them, minimizing Time-to-First-Token (TTFT).

The streaming protocol is structured around explicit lifecycle events:

```text
event: open           // Connection established
event: token   × N    // Incremental text chunks for frontend appending
event: citation       // Source attribution metadata from knowledge base hits
event: chart          // Structured charting payloads for ECharts rendering
event: done           // Normal generation completion
event: error/timeout  // Explicit error or timeout termination
```

Spring WebFlux `Flux` streams natively support reactive backpressure, preventing excessive memory accumulation during high-concurrency generation. Every SSE stream guarantees termination with either a `done` or `error/timeout` event, preventing client interfaces from hanging indefinitely during network drops.

At the reverse proxy tier, production Nginx configurations set `proxy_buffering off` and `proxy_cache off` for streaming endpoints, ensuring chunks bypass intermediate buffers and reach the browser with sub-millisecond latency.

![SSE event stream timeline: upstream through ChatClient to frontend, including error and timeout branches](/images/enterprise-ai-cockpit-sse.svg)

The frontend renders response text, source badges, and interactive ECharts visualizations within a unified conversational stream, combining assertions, citations, and data graphs in a single view.

## Functional Scope and Security Boundaries

The platform integrates report templates, asynchronous batch execution, external data source connectivity tests, and Model Context Protocol (MCP) tooling.

Key security and architectural boundaries include:

- **Restricted Operation Governance**: The public demo provides read-only views, while uploads, deletions, and heavy report generation are protected by short-lived backend Action Tokens;
- **Strict Citation Grounding**: Model responses must be grounded in retrieved context chunks, preventing unverified assertions.

## Resource Governance in Constrained Environments

Operating on a 2GB RAM cloud node alongside quantitative trading and trend analysis services requires strict resource constraints. Frontend assets are fully pre-compiled into static bundles, while the backend runs inside a precisely tuned JVM container.

Resource caps are enforced across all layers:
- **JVM Heap & Metaspace**: Constrained via `-Xmx` and `-XX:MaxMetaspaceSize` to prevent unbounded memory growth;
- **Direct Memory**: Because Spring WebFlux utilizes Netty for off-heap I/O buffers, `-XX:MaxDirectMemorySize` is explicitly defined;
- **Connection and Thread Pools**: HikariCP connection pools and Quartz scheduler threads operate with minimal concurrent allocations.

Under system-level memory pressure, the cockpit service maintains the lowest priority tier and can be gracefully downgraded or paused to safeguard core infrastructure.

You can access the live deployment at [/smartCockpit/](/smartCockpit/). It is still a laboratory, but it is no longer just a chat box.
