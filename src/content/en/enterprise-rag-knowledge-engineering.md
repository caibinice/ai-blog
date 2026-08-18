---
title: Treating Enterprise RAG as Knowledge Engineering: From Answers to an Optimizable System
excerpt: The model runs the final leg. Reliable enterprise answers depend on structured parsing, hybrid retrieval, lifecycle governance, observable evaluation, and explicit MCP boundaries.
---

An enterprise knowledge base creates an easy illusion: once documents have embeddings and a chat box returns fluent prose, RAG is finished. In practice, many failures happen before the model ever sees context. A heading disappears during parsing, a table is flattened, an exact contract number never enters the candidate set, an obsolete policy outranks the current one, or a follow-up such as “does that rule apply to contractors?” is retrieved as a brand-new question with no subject.

I recently upgraded the knowledge pipeline behind the [Enterprise AI Cockpit](/smartCockpit/). The goal was not to replace the model with a larger one. It was to make the question “why did these pieces of evidence reach the model?” observable, testable, and improvable.

## RAG is two production pipelines

RAG is the composition of an indexing path and a query path:

```text
index: file -> parsing/structure recovery -> chunking -> provenance -> embedding -> index
query: question -> query understanding -> permission/time filters -> dense + keyword -> rerank -> context -> answer + citations
```

Either path can destroy information. If the indexer loses heading hierarchy, a good embedding only represents a sentence without its business context. If the query path ignores version and effective dates, accurate similarity can confidently retrieve an expired policy. That changes the debugging order: inspect extraction, candidate recall, filtering and fusion, conflicting versions, and only then the model’s use of evidence.

## Chunking should preserve the smallest useful business context

The earlier implementation used fixed character windows. It was predictable, but it could separate a heading from its body or cut a sentence in half. The new chunker first recognizes Markdown headings, Chinese chapter headings, numbered sections, paragraphs, and sentence boundaries. Character windows are now a final fallback for oversized structural units.

Each child chunk carries its section context:

```text
Section: Refund Approval Rules
A refund request must be filed within seven days of receipt and include the order number.
```

Adjacent chunks retain a bounded overlap. Exact duplicates are removed before indexing, and highly ranked neighboring chunks from the same document are merged in source order after retrieval while repeated overlap is trimmed. This combination avoids two recurring problems: fragments that are too small to mean anything and repeated overlap consuming the context budget.

Every import also records provenance: `source`, `sourceType`, `parser`, `ingestedAt`, `contentHash`, and `chunkStrategy`. These fields do not directly improve prose, but they answer operational questions that matter: where the evidence came from, which parser handled it, whether the content changed, and which indexing strategy created the current vectors.

## Dense and lexical retrieval are complementary

Embeddings are good at matching different expressions of the same idea. Lexical search is good at contract IDs, SKUs, error codes, versions, and domain names. Enterprise questions often contain both kinds of signal. Pure vector search can place a generic contract policy above `CN-2026-0818`; pure keyword search can miss that “expenses after termination” answers a question phrased as “can I still claim after leaving?”

The cockpit now retrieves both candidate sets:

```text
dense   = pgvector.cosine(query, candidate_k)
lexical = mysql.keyword_cjk(query, identifiers, candidate_k)
fused   = reciprocal_rank_fusion(dense, lexical)
ranked  = exact_phrase_identifier_version_freshness_boost(fused)
context = merge_adjacent(dedupe(ranked), top_k)
```

Reciprocal Rank Fusion works on rank positions rather than pretending that cosine and lexical scores are directly comparable. Small reranking boosts then favor exact phrases, identifiers, title matches, newer versions, and fresher imports. These are bounded corrections, not rules that replace relevance.

The dual path also improves resilience. If vector retrieval fails temporarily, lexical candidates still produce evidence; if the lexical store is unavailable, dense retrieval can still answer. Hybrid retrieval improves both average quality and graceful degradation.

## Fresh knowledge requires explicit lifecycle data

The most dangerous knowledge base is not an empty one. It is one containing three authoritative-looking but contradictory versions. Similarity alone does not understand draft, superseded, expired, or effective next month.

The retrieval layer now uses lifecycle metadata:

| Field | Default query behavior |
| --- | --- |
| `status` | include active, published, or current documents |
| `effectiveFrom` | exclude rules that are not yet effective |
| `effectiveTo` | exclude expired knowledge |
| `supersededBy` | exclude a version replaced by another document |
| `version` | gently prefer newer versions among similarly relevant candidates |

Administrators can include inactive material for diagnostics, but ordinary users should not have to resolve version conflicts. The next operational step is to automate superseding old documents and schedule reconciliation for expired records and orphan vectors. Updating knowledge is as important as searching it.

## Follow-up questions need retrieval context

A chat model can understand “that rule,” but the retriever only sees the current string. After “what is the refund deadline?”, the follow-up “who does that rule apply to?” is a weak standalone embedding.

For clearly referential follow-ups, the cockpit now prepends the latest user question to the retrieval query while leaving the original question unchanged for generation:

```text
What is the refund deadline?
Follow-up: Who does that rule apply to?
```

This conservative rewrite avoids asking a model to paraphrase every query. Once a representative evaluation set exists, a structured small-model rewriter can be compared against the original query with recall@k instead of being trusted by intuition.

## MCP tools and the knowledge base have different jobs

The knowledge base serves stable, citable facts. MCP tools serve live weather, maps, calculation, and business queries that require execution or current state. Stale weather should not masquerade as a document, and a policy should not require a live tool call on every question.

The model may now plan only tools explicitly selected in the interface. “Tools enabled, none selected” means no capability is exposed; it no longer grants an implicit weather tool. The host validates calls against MCP schemas, bounds execution steps, records observations, and returns a trace. The model plans inside the authorized catalog rather than inventing capabilities.

```text
user selection -> tool catalog/schema -> model plan -> host validation/execution -> observations -> answer
```

This is the distinction between function calling as a demo and an auditable tool pipeline.

## A retrieval lab closes the tuning loop

Previously, retrieval was hidden behind the final chat response. When an answer was poor, logs had to reveal whether recall was wrong or the model misused correct evidence. The Knowledge page now includes a Retrieval Lab: select a knowledge base, enter a question, and inspect the real Hybrid + RRF order, scores, excerpts, and full evidence. Its protected endpoint reuses the production retrieval path instead of maintaining a separate test implementation.

Visibility is only the beginning. A compact golden set should record the allowed knowledge bases, expected document or passage, key fact, and whether the task should invoke a tool. Each change to chunking, embeddings, fusion weights, or lifecycle rules should compare:

- `Recall@k` for candidate coverage;
- `MRR` for how early the first correct passage appears;
- citation correctness for whether claims are directly supported;
- stale/conflicting-hit rate;
- p50/p95 latency and candidate volume.

“No evidence” must be measured too. An honest empty result is more useful than fluent text assembled from irrelevant chunks. The Retrieval Lab therefore points an empty query toward document status, effective dates, metadata, and chunk content instead of immediately increasing top-k.

## The practical conclusion

The central asset in enterprise RAG is not the vector database. It is a maintainable system for producing knowledge and learning from retrieval failures. Better models improve reasoning and expression, but they do not repair broken parsing, missing access boundaries, expired policies, or a bad candidate set.

My preferred implementation order is now:

1. make structure, provenance, and lifecycle traceable;
2. combine semantic and lexical retrieval and expose candidate behavior;
3. build regression metrics from real questions;
4. only then compare embeddings, rerankers, and generation models.

This order lets every improvement name the layer it changed and every regression identify a likely cause. The current implementation and its Retrieval Lab are available in the [Enterprise AI Cockpit](/smartCockpit/).

## References

- [Anthropic: Contextual Retrieval](https://www.anthropic.com/engineering/contextual-retrieval)
- [pgvector: official Hybrid Search guidance](https://github.com/pgvector/pgvector#hybrid-search)
- [Apache Tika Parser documentation](https://tika.apache.org/2.7.0/parser.html)
- [Model Context Protocol: Tools specification](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
