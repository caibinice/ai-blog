---
title: From RAG Demo to Enterprise Intelligent Cockpit: Knowledge, Vectors, and Streaming Answers
excerpt: A real enterprise AI experience is more than just a chat box—it’s a cockpit built from data persistence, retrieval evidence, streaming feedback, and business workflows.
---

Many RAG demos start with a chat box: upload files, enter a question, and the model gives an answer. This flow is fine for proving a concept, but when I tried to turn it into an enterprise intelligent cockpit, questions quickly went beyond the chat itself.

Are the knowledge base and documents persisted? How do vectors sync when a document is deleted? Which chunks does the answer reference? How do you give feedback when the upstream model’s stream is interrupted? How do business reports, data sources, and conversation logs share the same permission and audit boundaries?

What these questions have in common is that they all live *outside* the conversation. The chat box is only the entrance; what actually decides whether this can ship is the storage, retrieval, event stream, and fallback paths behind it. This project is answering these questions that are closer to real-world deployment. It doesn't try to be feature-complete; it tries to make every step from upload to answer—every step that could fail *silently*—explicit.

> **August 2026 update:** This article preserves the initial vector-first, lexical-fallback architecture. The live version now uses structure-aware chunks, parallel dense and lexical recall, RRF fusion, lifecycle filters, deduplication, and adjacent-chunk merging. See [Treating Enterprise RAG as Knowledge Engineering](/en/articles/enterprise-rag-knowledge-engineering) for the complete tuning approach.

## Two Types of Databases with Different Responsibilities

MySQL stores knowledge bases, document metadata, data sources, report templates, run records, conversations, and business configurations. PostgreSQL + pgvector stores fixed-dimension vectors and chunk metadata.

Why not stuff all of this into one database? Because the two kinds of data have completely different access patterns. Business data needs transactions, foreign keys, filtering, and pagination—home turf for a relational database. Vector retrieval needs "given a query vector, find the most similar top-k," which is essentially approximate nearest-neighbor search. Cramming high-dimensional vectors into an ordinary table and computing distances row by row is both slow and hard to maintain. Letting each kind of data use the right engine actually keeps the interface cleaner. Force them together and one class of operation always ends up contorting itself around the other's storage layout, dragging down both read and write paths.

Document import is a pipeline you can break apart:

- Apache Tika extracts plain text from PDF, Word, plain text, and other formats, masking format differences.
- The text is split into chunks of a controlled size—say 500 characters with a 50-character overlap (numbers here are illustrative; tune them to your corpus and embedding model). The overlap exists so a sentence cut in the middle doesn't lose its context.
- An embedding is generated for each chunk.
- The vector, together with chunk metadata (which document, which chunk index, position in the source), is written to the vector table.

As pseudocode, the boundaries are clearer:

```text
# import (index path)
text   = tika.extract(file)                   # mask PDF/Word/plain-text differences
chunks = split(text, size=500, overlap=50)    # numbers illustrative, tune per corpus
for c in chunks:
    v = embed(c.text)                         # produce a fixed-dimension vector
    pgvector.insert(v, meta={doc_id, idx, span})
mysql.save(doc_meta)                          # register the document on the business side
```

Metadata matters because retrieval hits a vector, but what the user needs to see is "which paragraph of which document this came from." Without metadata, there's no way to turn a similarity result back into a checkable citation. A vector is just a string of floats—it can tell you something is *similar*, but not where it *came from*, and enterprise contexts care most about provenance.

Chunk size is a knob to trade off, not a smaller-is-better or bigger-is-better dial. Cut too fine and a single chunk carries incomplete meaning, so retrieval hits half a sentence. Cut too coarse and one chunk mixes several topics, diluting similarity and blurring the citation. Overlap compensates at the cut points: adjacent chunks share a small boundary of text so a key sentence that happens to land on a split isn't lost on both sides. These numbers all have to be tried against your actual corpus; there's no default that settles it once and for all.

At query time, pgvector cosine search is preferred, taking the top-k most similar chunks as context:

```text
# query (query path)
q    = embed(question)
hits = pgvector.search(q, top_k=5)            # preferred: cosine top-k (top_k value illustrative)
if vector_unavailable or not hits:
    hits = mysql.keyword_cjk_search(question) # fallback: keyword / CJK
context = [h.chunk for h in hits]             # assemble context, carry citations
```

Here's a fallback path I didn't skip: if the vector service is unavailable—connection failure, timeout, or dimension mismatch—retrieval falls back to MySQL keyword and CJK search. CJK segmentation differs from English; splitting on whitespace would treat a whole Chinese sentence as one token, so the fallback has to handle CJK specifically to be useful. The fallback's quality is usually worse than vector retrieval, but it guarantees that "the vector store went down, so the whole Q&A is dead" never happens. The fallback isn't the default path; it's an explicit safety net—you don't reach it under normal conditions, and when you do, the user at least gets a keyword-based answer instead of a spinning blank page.

The k in top-k also needs restraint. Too few and you may miss the genuinely relevant chunk; too many and irrelevant content crowds the context and dilutes the model's attention. It's coupled to chunk size: smaller chunks usually need a larger k to gather enough context.

The two stores' responsibilities line up more clearly side by side:

| Dimension | MySQL | PostgreSQL + pgvector |
| --- | --- | --- |
| What it holds | KB, doc metadata, data sources, report templates, run records, chats, config | fixed-dimension vectors, chunk metadata |
| Access pattern | transactions, filtering, pagination, joins | top-k approximate nearest neighbor |
| Main role | carries business-workflow state | powers semantic retrieval |
| Role in Q&A | keyword / CJK fallback | preferred cosine search |

This separation is not about stacking databases, but about letting structured business data and similarity search each use the right tool, while keeping a fallback path. It also means deleting a document has to touch both sides: remove the business record in MySQL and clear the corresponding vectors and chunks in pgvector, or retrieval will hit a document that no longer exists and the citation becomes meaningless. A delete across two databases has no natural transaction guarantee, so order and compensation need thought: one safe approach is to mark the business record deleted first, then clean the vectors asynchronously—so even if it fails midway, a reconciliation job can scan out orphan chunks ("vector with no matching document") and reclaim them, rather than letting them quietly linger in results.

![RAG cockpit index and query paths, and the MySQL / pgvector dual-database split](/images/enterprise-ai-cockpit-rag.svg)

## Streaming Answers Must Come from the Real Upstream

The backend uses Spring WebFlux and Spring AI. After `ChatClient` receives SSE from the upstream OpenAI-compatible/DeepSeek, it continues to send tokens, citations, chart information, and completion status as an event stream to the Vue frontend.

This is fundamentally different from slicing a full answer into several strings locally and emitting them on a timer. Fake local streaming is only a visual effect; the time-to-first-token still equals generating the whole answer. A real upstream stream lets the user see feedback the moment the model emits its first few tokens. The cost is that the real stream is no longer one clean string, but a sequence of events with states to handle:

```text
event: open           // connection established
event: token   × N    // incremental text, appended piece by piece
event: citation       // matched source chunks
event: chart          // structured chart data
event: done           // normal completion
event: error/timeout  // exception branch, must close explicitly
```

Carrying this stream with WebFlux helps because it handles backpressure natively as a `Flux`: the upstream produces a piece and it's pushed downstream, without buffering the whole answer in memory first. But async also means an error is no longer a return value a simple try/catch can catch—it's an event on the stream, and it has to be modeled explicitly within the stream's semantics.

The last two lines are the point. The connection can drop mid-stream, the upstream can time out, or it can return an error event. None of these can be swallowed—the frontend must know whether the stream ended normally or aborted, otherwise the UI hangs forever on "typing." So the backend guarantees that every SSE stream ends either with `done` or with `error`/`timeout`; there is no third, silent "it just stopped." This invariant looks trivial, but it's the foundation of whether the streaming experience can be trusted: allow even one "stream with no terminal state" and the frontend has to bolt on timeout guesses everywhere to compensate, and the complexity bites straight back.

There's also an easily overlooked link: Nginx needs to turn off SSE buffering. By default a reverse proxy buffers the response, collecting a batch before forwarding. That's an optimization for ordinary endpoints but a disaster for SSE—the backend outputs piece by piece, yet the browser might still receive everything at once at the end, and the streaming experience is gone. Turn off buffering and events pass through the proxy the instant they're produced. The nasty part of debugging this is that a local direct connection works perfectly and it only reproduces once you're behind the proxy, which is easy to misread as the backend not streaming at all.

![SSE event stream over time: upstream through ChatClient to the frontend, with error and timeout branches](/images/enterprise-ai-cockpit-sse.svg)

The frontend places answer text, cited documents, and ECharts charts in the same context. token events keep appending body text, citation events render the matched chunks as expandable sources, and chart events carry structured data for ECharts to draw. The user sees not only "what the model said" but can also ask "what it based that on."

## The Full Trace of a Single Q&A

Stitch the pieces together and one Q&A actually runs the whole pipeline. The user asks in the cockpit; the question is first embedded into a query vector and run through pgvector cosine retrieval for the top-k chunks—or, if the vector service is unavailable at that moment, it falls back to keyword and CJK search. The matched chunks plus the question are assembled into context and handed to `ChatClient` for the upstream. The upstream starts emitting tokens; the backend forwards token events while inserting citation and chart events at the right moments, and closes with `done`—and any failure along the way closes explicitly with `error`/`timeout`.

I deliberately made every step of this trace observable, because what's really thorny in an enterprise setting is often not "is the answer right" but "when it's wrong, can you find where." What retrieval hit, which passages were cited, whether the stream ended cleanly or aborted—if all of that lives in logs and events, an unsatisfying answer can be reviewed rather than becoming an unquestionable "that's just what it said."

## An Enterprise Cockpit Is Not a Universal Robot

The current system also includes report templates, run records, data source tests, voice interfaces, and an MCP weather example. The point of these capabilities is to verify how AI enters an existing workflow, not to cram every function into a dialog box.

The way I read "cockpit" is this: AI is one instrument on the panel, not a black box that replaces all the instruments. Reports have templates and run records, data sources can be connectivity-tested on their own, conversations have a history you can trace back—these are structures that let the AI's output be traced and reviewed, rather than "just ask it." The value of a dashboard is precisely that each gauge has its job and its readings can be cross-checked; cramming everything into one chat box mashes a stack of readings into a single sentence—pretty, but uncheckable.

I deliberately kept a few boundaries:

- Local embedding is used only for repeatable pipeline verification; production quality still requires a real model.
- Data source extraction and report tasks still have an MVP nature.
- The public demo exposes read-only screens, while chat, uploads, deletes, and report runs require a short-lived backend action token; application-level RBAC, tenant isolation, and auditing remain future work.
- Model answers must include citations; fluent expression cannot be treated as a guarantee of fact.

I write these boundaries down because I don't want the demo to look more mature than it actually is. That local embedding runs the pipeline doesn't mean its recall quality is production-grade; that a read-only demo plus short-lived tokens blocks casual damage doesn't make it a full permission system. Honestly labeling "this part is still MVP" is cheaper than being found out later.

That last one is what I value most. Fluent and correct are two different things. An answer that can cite its source, even in plain wording, is more usable than an eloquent passage you can't check. Requiring citations is essentially giving the model's confidence an anchor that can be verified—the more assertively it speaks, the more it should be able to point to the passage that sentence came from.

## Trade-offs on a Small Server

This system shares 2GB of memory with two other projects. All frontend is built locally into static files; the server runs only one constrained JVM backend. The database connection pool, Quartz threads, heap, metaspace, and direct memory all have explicit limits.

Why pin down a ceiling on every one of them? Because on a shared-memory machine, the real danger isn't a component using a lot—it's a component with no cap. An unbounded connection pool or thread pool will quietly eat memory under load and then drag down the other services on the same box. Setting an explicit ceiling on each item is declaring in advance "this is the most I'll use," which makes capacity predictable. Predictable matters more than "runs faster"—on this machine, the cascading failure from one uncontrolled memory spike costs far more than the bit of latency you'd save.

Direct memory deserves its own watch. Netty-based frameworks like WebFlux use off-heap memory, which isn't bound by the ordinary heap limit and is the easiest thing to forget to configure; once traffic rises, the heap can look roomy while off-heap is quietly swelling. Only by pinning it down too do you actually close the books on this machine's memory.

If overall resources continuously exceed the threshold, the intelligent cockpit will become the first backend to be suspended. That's a deliberate priority: compared with the other two projects, it's more of a testbed, so pausing it costs the least. This is not a failure, but a part of capacity boundaries: the system should know when to hold back. Deciding "who yields first" ahead of time is far steadier than improvising the choice when memory is already tight.

You can open the current version at [/smartCockpit/](/smartCockpit/). It is still a laboratory, but it is no longer just a chat box.
