---
title: Knowledge Engineering and Tunable Cockpit Architecture for Enterprise RAG
excerpt: A deep dive into enterprise RAG knowledge engineering: structure-aware chunking, hybrid Dense+Keyword retrieval with RRF reranking, lifecycle metadata governance, MCP boundaries, and the Retrieval Lab evaluation loop.
---

In enterprise knowledge Q&A systems, the primary bottleneck rarely lies in the text generation capabilities of the underlying LLM. Instead, failures typically stem from upstream engineering flaws in document ingestion and retrieval pipelines: lost heading hierarchies, flattened table structures, missed contract numbers or error codes, outdated document versions overriding newer policies, and unresolved conversational references.

To systematically address these challenges, the [Enterprise AI Cockpit](/smartCockpit/) underwent a comprehensive knowledge engineering overhaul. The engineering focus shifted from prompt hacking to structural document parsing, hybrid retrieval fusion, temporal metadata governance, and closed-loop empirical evaluation.

## Decoupling the Indexing and Querying Pipelines

RAG is fundamentally a composite system of two decoupled operational pipelines:

```text
Indexing Pipeline: Ingestion -> Structural Parsing/Heading Recovery -> Semantic Chunking -> Provenance Tracking -> Embedding -> Vector/Inverted Indexing
Querying Pipeline: Query -> Coreference Resolution -> Policy/Temporal Filtering -> Dense + Keyword Retrieval -> RRF Fusion Reranking -> Context Assembly -> Generation & Citation
```

Both pipelines can introduce informational decay: losing heading context during indexing leaves embeddings detached from business hierarchies; ignoring validity windows during querying leads to confident citations of obsolete policies.

To isolate errors effectively, the system enforces a bottom-up diagnostic workflow:

1. **Structural Parsing Audit**: Verify whether document structures, headings, table layouts, and business codes are faithfully preserved;
2. **Candidate Recall Verification**: Confirm whether ground-truth text chunks are captured within Dense or Keyword candidate sets;
3. **Filtering and Fusion Review**: Check whether relevant candidates were mistakenly pruned by metadata filters, deduplication, or RRF weighting;
4. **Context Version Conflict Inspection**: Ensure that conflicting historical versions do not coexist within the final prompt context;
5. **Model Attribution Assessment**: Verify that the LLM's generated response strictly adheres to the supplied context evidence.

```text
Diagnostic Flow: Structural Integrity -> Candidate Recall -> Fusion Weighting -> Version Consistency -> Model Attribution
```

## Structure-Aware Chunking and Provenance Tracking

Naively slicing text using fixed-character windows breaks semantic coherence and detaches section headings from body paragraphs. The upgraded implementation uses a structure-aware chunking algorithm: it prioritizes Markdown headings, hierarchical chapter titles, numbered lists, double-newline paragraphs, and sentence boundaries. Fixed-window slicing is used only as a fallback when a single structural block exceeds length thresholds.

Every chunk retains its hierarchical heading path as explicit metadata:

```text
Heading Path: Corporate Policies > After-Sales Support > Refund Approval Standards
Chunk Content: Refund requests must be submitted within seven days of receipt, accompanied by order numbers and payment receipts.
```

When a chunk is retrieved independently into top-k candidates, the attached path ensures the language model retains immediate context of the underlying rule. Chunks are deduplicated via content hashing prior to storage. When adjacent chunks from the same document receive high relevance scores during retrieval, the context builder dynamically merges them and strips overlapping text to maximize prompt efficiency.

For data governance, the system records comprehensive provenance metadata: `source` (file path), `sourceType` (MIME type), `parser` (extractor version), `ingestedAt` (timestamp), `contentHash` (SHA-256), and `chunkStrategy` (chunking algorithm version).

## Hybrid Dense + Keyword Retrieval with RRF Fusion

Dense embeddings excel at capturing conceptual similarity and semantic paraphrasing, but struggle with exact identifiers (e.g., contract codes `CN-2026-0818`, SKUs, and error codes). Conversely, lexical keyword search excels at token precision but cannot generalize across synonyms.

The cockpit executes a dual-track retrieval strategy:

```text
dense_candidates   = pgvector.cosine_search(query_vector, candidate_k)
keyword_candidates = mysql.lexical_search(query_tokens, candidate_k)
fused_ranked       = reciprocal_rank_fusion(dense_candidates, keyword_candidates, k=60)
final_ranked       = apply_freshness_and_exact_match_boost(fused_ranked)
context_chunks     = merge_adjacent_chunks(deduplicate(final_ranked), top_k)
```

Candidate sets are merged using **Reciprocal Rank Fusion (RRF)**. Because RRF evaluates relative ranks rather than disparate, unnormalized distance scores, it demonstrates high parameter robustness. On top of RRF scores, the system applies calibrated boosts for exact phrase matches, business entity identifiers, heading matches, and active document versions.

This hybrid architecture also acts as a built-in redundancy mechanism: if the vector database experiences latency or outages, keyword search maintains baseline Q&A capabilities, and vice versa.

## Knowledge Lifecycle and Temporal Metadata Governance

A common failure mode in corporate knowledge management is the coexistence of multiple conflicting document revisions. Semantic similarity alone cannot discern whether a document is in "Draft", "Archived", or "Effective" status.

The system embeds temporal and lifecycle governance into chunk-level metadata:

| Metadata Field | Type | Query Filter Rule |
| --- | --- | --- |
| `status` | String | Production Q&A strictly enforces `status IN ('active', 'published')` |
| `effectiveFrom` | Timestamp | Documents with future effective dates are excluded from default search |
| `effectiveTo` | Timestamp | Expired policies are filtered out of standard retrieval queries |
| `supersededBy` | String | Historical versions superseded by newer releases are pruned |
| `version` | String | When candidates score closely, newer versions receive ranking boosts |

Administrators can configure automated version supersession workflows and schedule background reconciliation tasks to clean orphan chunks and expired documents.

## Conversational Coreference Resolution and Query Rewriting

In multi-turn dialogues, follow-up queries frequently contain strong pronouns (e.g., Turn 1: "What is the refund window?"; Turn 2: "Does this rule apply to international orders?"). Embedding the second query directly leads to poor retrieval due to missing subject context.

The system uses a deterministic query stitching technique: upon detecting pronouns or incomplete predicates, it appends the core subject from the preceding user turn to form an expanded search query:

```text
Turn 1: What is the refund approval window?
Turn 2: Does this rule apply to international orders?
Synthesized Query: What is the refund approval window? Does this rule apply to international orders?
```

The synthesized text is utilized solely for vector and keyword search; the generation model continues to receive the pristine conversation history, avoiding prompt drift.

## Model Context Protocol (MCP) Tool Governance

The architecture strictly separates static knowledge base content from dynamic MCP tool execution:
- **Knowledge Base**: Serves static, citeable documentation, standards, and institutional records;
- **MCP Tools**: Handles dynamic state queries (e.g., live weather, AMap geolocation, time APIs, dynamic SQL queries, and transactional actions).

Tool governance enforces the principle of least privilege: models are only permitted to invoke tools explicitly enabled by the user in the UI. Backend hosts validate tool schemas, enforce execution step limits, and log full execution traces.

```text
User Authorization -> Tool Directory / Schemas -> Model Planning -> Host Validation & Sandbox Execution -> Observation -> Final Synthesis
```

## Retrieval Lab and Quantitative Evaluation Loop

To enable continuous retrieval tuning, the console features a built-in Retrieval Lab. Engineers and operators can select a target knowledge base, submit test queries, and inspect Hybrid + RRF rankings, similarity scores, chunk previews, and metadata payloads.

The system tracks key retrieval metrics against a benchmark Golden Dataset:

- **Recall@k**: Percentage of queries where ground-truth chunks appear in top-k candidates;
- **MRR (Mean Reciprocal Rank)**: Average reciprocal rank of the first relevant chunk;
- **Citation Precision**: Proportion of claims in generated answers directly backed by citations;
- **Version Conflict Rate**: Frequency of expired or conflicting chunks slipping into prompts;
- **p50/p95 Retrieval Latency**: Performance monitoring across parsing, search, and reranking.

When no high-confidence chunks are found, the system explicitly returns a "no relevant evidence" state, prompting operators to review document metadata or ingest missing information, preventing hallucinated responses.

You can experience the upgraded retrieval architecture in the [Enterprise AI Cockpit](/smartCockpit/).

## References

- [Anthropic: Contextual Retrieval Engineering Guide](https://www.anthropic.com/engineering/contextual-retrieval)
- [pgvector Documentation & Hybrid Search Guidelines](https://github.com/pgvector/pgvector#hybrid-search)
- [Apache Tika Content Extraction Documentation](https://tika.apache.org/2.7.0/parser.html)
- [Model Context Protocol (MCP) Specification](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
