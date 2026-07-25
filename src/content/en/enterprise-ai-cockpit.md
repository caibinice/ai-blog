---
title: From RAG Demo to Enterprise Intelligent Cockpit: Knowledge, Vectors, and Streaming Answers
excerpt: A real enterprise AI experience is more than just a chat box—it’s a cockpit built from data persistence, retrieval evidence, streaming feedback, and business workflows.
---

Many RAG demos start with a chat box: upload files, enter a question, and the model gives an answer. This flow is fine for proving a concept, but when I tried to turn it into an enterprise intelligent cockpit, questions quickly went beyond the chat itself.

Is the knowledge base and documents persistent? How do vectors sync when a document is deleted? Which chunks does the answer reference? How to give feedback when the upstream model’s stream is interrupted? How do business reports, data sources, and conversation logs share the same permission and audit boundaries?

This project is answering these questions that are closer to real-world deployment.

## Two Types of Databases with Different Responsibilities

MySQL stores knowledge bases, document metadata, data sources, report templates, run records, conversations, and business configurations. PostgreSQL + pgvector stores fixed-dimension vectors and chunk metadata.

After document import, the backend uses Apache Tika to extract text, splits it into controlled sizes, generates embeddings, and writes them to the vector table. When asking a question, pgvector cosine search is preferred; if the vector service is unavailable, it can fall back to MySQL keyword and CJK search.

This separation is not about stacking databases, but about letting structured business data and similarity search each use the right tool, while keeping a fallback path.

## Streaming Answers Must Come from the Real Upstream

The backend uses Spring WebFlux and Spring AI. After `ChatClient` receives SSE from the upstream OpenAI-compatible/DeepSeek, it continues to send tokens, citations, chart information, and completion status as an event stream to the Vue frontend.

This is different from slicing a full answer into several strings locally. A real upstream stream can give feedback earlier, and must handle connection drops, timeouts, error events, and final status. Nginx needs to turn off SSE buffering, otherwise although the backend outputs piece by piece, the browser might still receive everything at once in the end.

The frontend places answer text, cited documents, and ECharts charts in the same context. The user sees not only “what the model said” but can also ask “what it based that on.”

## An Enterprise Cockpit Is Not a Universal Robot

The current system also includes report templates, run records, data source tests, voice interfaces, and an MCP weather example. The point of these capabilities is to verify how AI enters an existing workflow, not to cram every function into a dialog box.

I deliberately kept a few boundaries:

- Local embedding is used only for repeatable link verification; production quality still requires a real model.
- Data source extraction and report tasks still have an MVP nature.
- The public demo uses Nginx Basic Auth; application-level RBAC, tenant isolation, and auditing are still future work.
- Model answers must include citations; fluent expression cannot be treated as a guarantee of fact.

## Trade-offs on a Small Server

This system shares 2GB of memory with two other projects. All frontend is built locally into static files; the server runs only one constrained JVM backend. The database connection pool, Quartz threads, heap, metaspace, and direct memory all have explicit limits.

If overall resources continuously exceed the threshold, the intelligent cockpit will become the first backend to be suspended. This is not a failure, but a part of capacity boundaries: the system should know when to hold back.

You can open the current version at [/smartCockpit/](/smartCockpit/). It is still a laboratory, but it is no longer just a chat box.
