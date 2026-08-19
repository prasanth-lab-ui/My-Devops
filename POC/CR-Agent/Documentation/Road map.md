# CR Agent — Roadmap

Detailed, step-by-step build plan. Each phase is independently shippable — the agent gets smarter and more capable one phase at a time, and each phase ends with a concrete "done when" so you know when to move on.

## Table of Contents

- [CR Agent — Roadmap](#cr-agent--roadmap)
  - [Table of Contents](#table-of-contents)
  - [Phase 0 — Setup \& Scaffold](#phase-0--setup--scaffold)
  - [Phase 1 — Static Single-Shot Pipeline](#phase-1--static-single-shot-pipeline)
  - [Phase 2 — Structured Output \& Validation Retry](#phase-2--structured-output--validation-retry)
  - [Phase 3 — RAG Grounding on Past CRs](#phase-3--rag-grounding-on-past-crs)
  - [Phase 4 — Conversational Agent Loop](#phase-4--conversational-agent-loop)
  - [Phase 5 — Human-in-the-Loop Review Gate](#phase-5--human-in-the-loop-review-gate)
  - [Phase 6 — Dual-Agent Validation](#phase-6--dual-agent-validation)
  - [Phase 7 — Security Hardening](#phase-7--security-hardening)
  - [Phase 8 — Observability](#phase-8--observability)
  - [Phase 9 — Evaluation Set](#phase-9--evaluation-set)
  - [Phase 10 — Deploy](#phase-10--deploy)
  - [Phase 11 (Stretch) — Multi-Agent Handoff via MCP](#phase-11-stretch--multi-agent-handoff-via-mcp)

---

## Phase 0 — Setup & Scaffold

**Goal:** A working, empty skeleton — no agent logic yet, just the plumbing to build on.

**Steps:**
1. Initialize the repo, git, and a Python virtual environment.
2. Create the folder structure: `app/`, `agent/nodes/`, `agent/prompts/`, `rag/`, `excel/`, `schema/`, `memory/`, `llm/`, `templates/`, `storage/output/`, `tests/`.
3. Write `requirements.txt`: `fastapi`, `uvicorn`, `pydantic`, `langgraph`, `langfuse`, `litellm`, `mem0ai`, `openpyxl`, `chromadb`, `sentence-transformers`, `python-dotenv`, `pytest`.
4. Sign up for free API keys (NVIDIA NIM, Google AI Studio / Gemini). Add them to `.env`, and add `.env` to `.gitignore`.
5. Drop the org's sample CR Excel into `templates/cr_template.xlsx`.
6. Stub `app/main.py` with a `GET /ping` health check; confirm it runs via `uvicorn app.main:app --reload`.
7. Write `.env.example` with placeholder key names (no real values) so the repo is safe to share.

**Files touched:** `app/main.py`, `requirements.txt`, `.env.example`, `templates/`

**You'll learn:** why separating schema, prompts, and orchestration into distinct layers from day one prevents the tangled-agent problem most tutorials run into.

**Done when:** the server runs, `/ping` returns 200, and the folder structure matches the plan.

---

## Phase 1 — Static Single-Shot Pipeline

**Goal:** Prove the core plumbing — template parse → one LLM call → filled Excel — with zero agent framework involved.

**Steps:**
1. Write `excel/template_parser.py`: open `cr_template.xlsx` with openpyxl, walk the cells, record header labels, merged-cell ranges, and column positions. Dump this as a JSON "shape" describing where each field belongs.
2. Define `schema/cr_schema.py`: a Pydantic model matching the template's actual fields (title, environment, change type, risk, impact, rollback plan, maintenance window, etc.), each marked required or optional.
3. Write `llm/litellm_client.py`: one function that calls a single free provider (start with Gemini) through LiteLLM's unified interface.
4. Hardcode one test scenario string in a throwaway script.
5. Build one prompt: "extract these fields from this scenario, return JSON matching this schema." No retries or validation yet — just see what comes back.
6. Write `excel/writer.py`: takes a schema instance + the template shape, opens a **copy** of the template, writes values into the correct cells, saves to `storage/output/`.
7. Wire it together end to end: scenario → LLM → dict → Excel file.
8. Open the generated file and confirm formatting (merged cells, styles) survived.

**Files touched:** `excel/template_parser.py`, `excel/writer.py`, `schema/cr_schema.py`, `llm/litellm_client.py`

**You'll learn:** openpyxl mechanics — merged cells break naive cell-by-cell writes, which is the first real surprise in this project — and the basic shape of a prompt-driven extraction task.

**Done when:** running one script produces a correctly formatted CR.xlsx from a hardcoded scenario.

---

## Phase 2 — Structured Output & Validation Retry

**Goal:** The LLM's output reliably matches your schema, and bad output self-corrects instead of crashing.

**Steps:**
1. Switch from "hope the JSON parses" to real JSON-mode / function-calling (check which of your free providers support it via LiteLLM — Gemini and NVIDIA NIM both do).
2. Pass the Pydantic schema as the function/tool definition so generation is constrained to it.
3. Wrap the LLM call in a parse-and-validate step: attempt `CRSchema.model_validate()`, catch `ValidationError`.
4. On failure, build a corrective retry prompt that includes the actual validation error, call the LLM again (cap at ~3 retries).
5. Track field-level confidence: which fields the LLM filled vs. left null — you'll need this list in Phase 4.
6. Write unit tests: feed 3–4 varied scenarios, assert schema always validates or fails cleanly after retries are exhausted.

**Files touched:** `llm/litellm_client.py`, `schema/cr_schema.py`, `tests/test_extraction.py`

**You'll learn:** why raw text parsing is fragile for agents, and why schema-constrained generation plus retry-on-validation-error is the standard fix.

**Done when:** all test scenarios produce valid schema instances, and a deliberately malformed case triggers a retry that succeeds.

---

## Phase 3 — RAG Grounding on Past CRs

**Goal:** Field content (Risk, Impact, Rollback Plan) reads like your org actually writes it, not like an LLM improvising.

**Steps:**
1. Collect a small seed corpus: 5–10 real or synthetic past CRs, tagged by change type (EKS upgrade, SG change, SFTP config, etc.) in a metadata file.
2. Write `rag/embed.py`: chunk each past CR's narrative fields, embed locally with `sentence-transformers` (all-MiniLM-L6-v2), store in Chroma with the change-type tag as metadata.
3. Write `rag/retriever.py`: given a new scenario, embed it and retrieve top-k similar CRs — filter/boost by change-type tag rather than relying on pure cosine similarity alone.
4. Modify the drafting prompt to inject retrieved CRs as few-shot examples ("here's how similar past CRs described Risk/Rollback — write this one in the same style").
5. Manually A/B check: generate the same scenario with and without RAG context, compare quality.
6. Add a "no relevant examples found" fallback so a retrieval miss doesn't break generation.

**Files touched:** `rag/embed.py`, `rag/retriever.py`, `agent/nodes/draft.py` (stub — full node in Phase 4)

**You'll learn:** retrieval tuning — top-k choice, metadata filtering vs. pure similarity — and why few-shot style grounding matters more than raw fact lookup here.

**Done when:** retrieval returns relevant same-change-type examples for at least 3 test scenarios, and generated content visibly reflects their style.

---

## Phase 4 — Conversational Agent Loop

**Goal:** Multi-turn chat that asks targeted follow-up questions until the CR schema is complete. This is the core of the whole project.

**Steps:**
1. Install and configure LangGraph; define the graph state (conversation history, partial CR schema instance, list of missing fields, session id).
2. Set up a checkpointer (SQLite is free and sufficient) so state persists across chat turns and separate API calls.
3. Build `agent/nodes/extract.py`: takes the latest user message plus existing state, merges newly extracted fields into the schema instance without overwriting already-filled fields unless the user is explicitly correcting one.
4. Build `agent/nodes/completeness.py`: compares the filled schema against the required-field list, outputs `missing_fields`.
5. Build `agent/nodes/clarify.py`: if fields are missing, generate **one** targeted question (not a dump of everything missing) and pause the graph on a LangGraph interrupt, waiting for the user's reply.
6. Wire the graph edges: `extract → completeness → (clarify → wait → extract)` looping until complete, then → `draft`.
7. Build `agent/nodes/draft.py`: once complete, call the Phase 3 retriever and generate full field content.
8. Expose via FastAPI: `POST /chat` accepting `{session_id, message}`, resuming the graph from its checkpoint each call.
9. Manually test a full conversation: a vague one-line scenario → 2–3 clarifying questions → a completed schema.

**Files touched:** `agent/graph.py`, `agent/nodes/extract.py`, `agent/nodes/completeness.py`, `agent/nodes/clarify.py`, `agent/nodes/draft.py`, `api/routes.py`

**You'll learn:** stateful graph design, interrupts, and multi-turn state merging — the actual "agent" skill this whole project exists to teach.

**Done when:** a chat session starting from a vague scenario reaches a complete schema through follow-up questions, correctly resuming state across separate requests.

---

## Phase 5 — Human-in-the-Loop Review Gate

**Goal:** Nothing gets written to disk without the user's explicit confirmation.

**Steps:**
1. Add a review node after `draft.py`: format the drafted CR as a readable summary and present it in chat.
2. Add another LangGraph interrupt here: pause and wait for `confirm`, `edit: <field> = <value>`, or `regenerate`.
3. Handle the edit path: patch just the specified field, re-show the summary, wait again.
4. Handle regenerate: re-run `draft.py` on the same schema, asking the LLM for an alternative version.
5. Only on explicit confirmation does the graph proceed to validation (Phase 6) and writing.

**Files touched:** `agent/graph.py`, new review node under `agent/nodes/`

**You'll learn:** approval gates as a first-class graph interrupt rather than a bolted-on "are you sure?" check — a pattern that generalizes to any agent taking consequential actions.

**Done when:** the agent never writes a file without explicit confirmation, and an edit request updates only that field without re-asking everything else.

---

## Phase 6 — Dual-Agent Validation

**Goal:** Two independent checks — structural and safety — before a CR is considered final.

**Steps:**
1. Build **Validator Agent A** (schema/completeness): re-run Pydantic validation on the final instance, plus explicit business-rule checks in code (e.g. "if risk = High, rollback plan can't be empty") — code, not LLM judgment.
2. Build **Validator Agent B** (safety/policy): run the drafted content through Llama Guard to catch anything policy-violating or unsafe, independent of Agent A.
3. Keep them as genuinely separate graph nodes with separate prompts/models, not one node doing both jobs — this keeps failures attributable and each check independently improvable.
4. Define merge logic: both must pass to proceed. Either failing routes back to `draft.py` with the specific issue attached, or to `clarify.py` if the root cause is missing user information.
5. Cap retry loops (e.g. 2 validation-fail cycles) before surfacing the issue to the user directly instead of looping silently.

**Files touched:** `agent/nodes/validate_schema.py`, `agent/nodes/validate_safety.py`, `agent/graph.py`

**You'll learn:** why splitting validation into independent agents — rather than one "check everything" step — makes failures diagnosable and mirrors how real review processes separate peer review from policy review.

**Done when:** a deliberately incomplete CR is caught by Agent A, and a deliberately unsafe scenario is caught by Agent B.

---

## Phase 7 — Security Hardening

**Goal:** The agent can't be tricked into leaking sensitive data or writing outside its sandbox.

**Steps:**
1. Build a sanitization pre-processor: strip or placeholder-replace hostnames, IPs, account IDs, and credentials from user input before any cloud LLM call.
2. Add a routing rule: if sanitization flags high-sensitivity content, route that turn's LLM call to a locally hosted model (Ollama) instead of the cloud free-tier provider.
3. Lock down `writer.py`: hardcode the output directory, reject any path input from the LLM or user, validate the filename.
4. Confirm the agent has no shell/code-exec tool; if one is added later, wrap it in a no-network Docker container.
5. Move all API keys to environment variables, and confirm none appear in Langfuse traces or logs (mask them in the logging config).
6. Add basic rate limiting (e.g. `slowapi`) and request size caps on `/chat`.

**Files touched:** `agent/nodes/extract.py` (pre-processor hook), `excel/writer.py`, `app/main.py` (rate-limiting middleware)

**You'll learn:** agent tool-security thinking — the same least-privilege principle you already apply to IAM roles, applied to LLM-controlled tools.

**Done when:** a scenario containing a fake real hostname never appears verbatim in cloud LLM request logs, and a crafted path-traversal write attempt is rejected.

---

## Phase 8 — Observability

**Goal:** Every agent decision is traceable, not just guessed at.

**Steps:**
1. Wire Langfuse into every LangGraph node and every LiteLLM call (input, output, latency, token count).
2. Tag traces with `session_id` so a full conversation replays as one trace tree.
3. Add trace tags for which validator failed, which retry count was hit, and whether RAG context was used.
4. Build the habit of checking a trace before guessing whenever something looks wrong during testing.

**Files touched:** `llm/litellm_client.py`, `agent/graph.py` (tracing hooks)

**You'll learn:** debugging non-deterministic agent behavior through inspection rather than print-statement guessing.

**Done when:** you can open Langfuse and see a full session's node-by-node execution, including which validator failed and why.

---

## Phase 9 — Evaluation Set

**Goal:** Measurable proof the agent works — not just "seems fine."

**Steps:**
1. Write 10–20 scenario strings covering different change types, with varying levels of upfront detail (some vague, some thorough).
2. For each, manually write the expected CR field values.
3. Write an eval script: run each scenario through the full graph (scripted answers for clarify questions), compare output to expected.
4. Score field-level accuracy — exact match for structured fields, semantic similarity for free-text fields like Rollback Plan.
5. Track this score over time as prompts and retrieval are tuned — this becomes your regression test.

**Files touched:** `tests/eval_set.json`, `tests/run_eval.py`

**You'll learn:** agent evaluation methodology — the step most tutorials skip, and the only reliable way to know if a prompt change actually helped.

**Done when:** the eval script runs end to end and produces a numeric accuracy score comparable across runs.

---

## Phase 10 — Deploy

**Goal:** The agent is reachable outside your machine, on $0/month.

**Steps:**
1. Write a Dockerfile for the FastAPI app.
2. Choose a target: Hugging Face Spaces (Docker SDK) for free public hosting, or self-host plus Tailscale Funnel / Cloudflare Tunnel to keep it fully private.
3. Move the vector store and SQLite checkpoint to a persistent volume/path appropriate for the chosen host.
4. Set environment variables/secrets in the hosting platform's dashboard, never in the repo.
5. Smoke-test a full conversation against the deployed instance.

**Files touched:** `Dockerfile`, platform-specific deployment config

**You'll learn:** shipping an agent as a real, reachable service — including the persistence gotchas free tiers introduce (ephemeral filesystems, sleep/wake cycles).

**Done when:** you can chat with the deployed agent from a different device and download a generated CR.xlsx from it.

---

## Phase 11 (Stretch) — Multi-Agent Handoff via MCP

**Goal:** Tools are exposed via MCP instead of called directly, and agents hand off work explicitly rather than sharing in-process state.

**Steps:**
1. Wrap the Excel writer and RAG retriever as MCP tools with defined schemas.
2. Split the single agent process into cooperating agents (extractor, validator, writer) that communicate via explicit handoff messages.
3. Add Mem0 at this layer so recurring change types or user preferences persist across sessions, not just within one conversation.
4. Reassess honestly: does the multi-agent split actually improve anything here, or does it just add coordination overhead? Document the trade-off — making that judgment call is itself the lesson.

**Files touched:** new MCP server wrapping tools, `agent/graph.py` refactor

**You'll learn:** agent-to-agent coordination patterns, and when multi-agent is genuinely warranted versus over-engineering.

**Done when:** tools are called via the MCP protocol rather than direct function calls, and you can articulate whether the split was worth it.