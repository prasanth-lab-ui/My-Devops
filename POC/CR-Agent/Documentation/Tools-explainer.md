# CR Agent — Tools Explained

Not a spec sheet. This walks through *why* each tool entered the project — the exact problem that showed up, and the tool that solved it — in the order you'd actually hit them while building.

## Table of Contents

- [CR Agent — Tools Explained](#cr-agent--tools-explained)
  - [Table of Contents](#table-of-contents)
  - [The Starting Problem](#the-starting-problem)
  - [Python — the language everything is written in](#python--the-language-everything-is-written-in)
  - [FastAPI — the front door](#fastapi--the-front-door)
  - [Pydantic — the customs officer](#pydantic--the-customs-officer)
  - [openpyxl — the hands that fill the spreadsheet](#openpyxl--the-hands-that-fill-the-spreadsheet)
  - [LiteLLM — the universal power adapter](#litellm--the-universal-power-adapter)
  - [NVIDIA NIM \& Google AI Studio (Gemini) — the actual brains](#nvidia-nim--google-ai-studio-gemini--the-actual-brains)
  - [LangGraph — turning a chatbot into an agent](#langgraph--turning-a-chatbot-into-an-agent)
  - [VectorDB (Chroma) — the librarian who's read every past CR](#vectordb-chroma--the-librarian-whos-read-every-past-cr)
  - [Llama Guard — the second opinion](#llama-guard--the-second-opinion)
  - [Mem0 — the agent's long-term memory](#mem0--the-agents-long-term-memory)
  - [MCP — the standard wall socket](#mcp--the-standard-wall-socket)
  - [Langfuse — the flight recorder](#langfuse--the-flight-recorder)
  - [Quick Reference Table](#quick-reference-table)

---

## The Starting Problem

You want to type "we're upgrading EKS from 1.34 to 1.36 in staging" into a chat box and get back a fully formatted CR.xlsx, filled in the way your org actually writes CRs, checked by something before it lands in your inbox. That one sentence hides about ten separate problems. Each tool below exists because of one specific problem in that chain — not because it's trendy.

---

## Python — the language everything is written in

**The problem:** you need one language that has good libraries for web servers, spreadsheets, AI orchestration, and vector search, without gluing together four different ecosystems.

**Why Python:** it's the only language where LangGraph, LiteLLM, openpyxl, and every LLM SDK are all first-class citizens. You're not choosing Python for this project specifically — you're choosing it because the entire agentic-AI tooling world lives here first.

**Where it shows up:** everywhere. Every tool below is a Python library.

---

## FastAPI — the front door

**The problem:** something has to receive the user's chat message, hand it to the agent, and send a response back — and later, serve the finished Excel file for download.

**The story:** the user's phone sends `POST /chat` with `{"session_id": "abc123", "message": "upgrade EKS to 1.36"}`. FastAPI receives that, validates the shape of the request (via Pydantic, next section), passes the message into the LangGraph agent, and returns whatever the agent says back — a clarifying question, a draft summary, or eventually a download link. Later, `GET /download/abc123` hands back the actual `.xlsx` file.

**Why FastAPI specifically:** it's async by default (matters when you're waiting on slow LLM calls), and it auto-validates request/response shapes using the same Pydantic models you're already using for the CR schema — one less thing to keep in sync.

---

## Pydantic — the customs officer

**The problem:** an LLM's raw output is just text. "Risk level: pretty high I'd say" is not a value you can put in a spreadsheet cell that expects `High` / `Medium` / `Low`. Something has to reject bad shapes before they cause damage downstream.

**The story:** you define a `CRSchema` class — `risk_level: Literal["Low", "Medium", "High"]`, `rollback_plan: str`, `maintenance_window: datetime`, and so on. When the LLM's output comes back as JSON, you run it through `CRSchema.model_validate(llm_output)`. If the LLM wrote `"risk": "pretty high"`, validation fails immediately with a clear error — *before* that garbage ever reaches your Excel writer. That error message gets fed back to the LLM as a retry prompt: "risk_level must be exactly one of Low/Medium/High."

**Why this matters here specifically:** without this, a malformed field either crashes the Excel writer or silently produces a broken CR that looks fine until someone opens it. Pydantic is the checkpoint that catches it at the border, not after it's already in the building.

---

## openpyxl — the hands that fill the spreadsheet

**The problem:** you have validated data (thanks, Pydantic) and a sample CR template with merged cells, specific fonts, and a particular layout. Something has to put the data into the *right cells* without wrecking the formatting.

**The story:** first, you open `cr_template.xlsx` once and walk every cell to build a map — "Risk Level" label sits at `C7`, its answer goes in the merged range `D7:F7`. You save that map as JSON. Then, every time you generate a CR, you open a **fresh copy** of the template (never the original, never a blank sheet) and use that map to write `sheet["D7"] = "High"`. The borders, fonts, and merged cells were never touched — only the data changed.

**The gotcha that teaches you something:** the first time you try this, you'll write into a merged cell's second half and openpyxl will throw an error, because only the top-left cell of a merge is writable. That one error is the whole lesson about why "parse the template first" is a separate step from "write the data."

---

## LiteLLM — the universal power adapter

**The problem:** you're using free-tier APIs from two or three different providers (they all rate-limit, so you want fallback), and every provider has a slightly different request format. Writing separate code for NVIDIA's API shape and Google's API shape means every prompt change has to be made twice.

**The story:** instead of calling `nvidia_client.chat(...)` in one place and `genai.GenerativeModel(...).generate(...)` in another, you call one function: `litellm.completion(model="nvidia_nim/llama-3.1-70b", messages=[...])`. Tomorrow, when NVIDIA's free tier is rate-limited, you change one string to `model="gemini/gemini-2.5-flash"` and nothing else in your codebase moves. LiteLLM speaks every provider's dialect on the back end and gives you one consistent front end.

**Why this matters for a *free-tier* project specifically:** free tiers get rate-limited or nerfed without warning (it's happened before — see Google's Gemini free-tier cuts in late 2025). LiteLLM is what makes "swap providers" a config change instead of a rewrite.

---

## NVIDIA NIM & Google AI Studio (Gemini) — the actual brains

**The problem:** somewhere, an actual model has to read "upgrade EKS to 1.36" and turn it into structured fields and readable prose. That's the one thing none of the other tools do — they route, validate, store, and log, but the *understanding* happens here.

**The story:** NVIDIA NIM gives you free access to fast open-weight models (Llama 3.x, Qwen) — good for the frequent, cheap calls like the extraction and clarify-question steps. Google AI Studio's Gemini free tier gives you a much larger context window — useful when the conversation history or the RAG-retrieved past CRs get long, and you need one model call to see all of it at once. In practice you route cheap/frequent calls to NVIDIA and long-context calls to Gemini, both through LiteLLM so the routing logic lives in one config, not scattered through the code.

**Why two providers instead of one:** free tiers rate-limit per provider, not per project. Two providers means two independent quotas — if one taps out mid-conversation, LiteLLM can fall back to the other instead of the agent just failing.

---

## LangGraph — turning a chatbot into an agent

**The problem:** a single prompt-response call can't handle "the user gave a one-line scenario and I need to ask three follow-up questions before I have enough to write a CR, and I need to remember their answers across separate HTTP requests."

**The story:** without LangGraph, every `/chat` call is stateless — the agent has amnesia between messages. With LangGraph, you define a graph: an `extract` node, a `completeness_check` node, a `clarify` node that *pauses* the whole process (an "interrupt") and waits for the user's next message, then resumes exactly where it left off. A checkpointer (SQLite) saves the graph's state to disk after every step, keyed by `session_id`. So when the user replies to "what's the rollback plan?" ten minutes later from a different request, LangGraph reloads exactly where the conversation was and merges the new answer in.

**The concrete moment this becomes necessary:** the instant you need the agent to ask *more than one* question across *more than one* message, plain prompt-chaining breaks down and you need real state management. That's the line between "chatbot" and "agent."

---

## VectorDB (Chroma) — the librarian who's read every past CR

**The problem:** the LLM can fill in *what* the risk level is, but it has no idea *how your org writes* a Rollback Plan section. Left alone, it'll write generic, forgettable prose.

**The story:** you feed 5–10 real past CRs into Chroma, each one embedded as a vector and tagged with a `change_type` (EKS upgrade, SG change, SFTP config). When a new scenario comes in — "upgrading EKS" — you embed that scenario too and ask Chroma for the most similar past CRs, filtered to the same `change_type` tag. Those retrieved examples get pasted into the drafting prompt as "here's how we've written this kind of Rollback Plan before." The new CR's prose ends up sounding like your team wrote it, because it's grounded in examples of your team's actual writing.

**Why not just paste all past CRs into every prompt:** free-tier context windows and token quotas aren't infinite, and irrelevant examples (an SFTP CR when you're writing an EKS upgrade) actively confuse the model more than they help. Retrieval is what keeps the prompt small and relevant instead of a dump of everything you've ever written.

---

## Llama Guard — the second opinion

**The problem:** Pydantic checks that a CR is *structurally* complete. It has no idea whether the content is safe or policy-appropriate — a CR could be fully valid and still describe something risky in a way that shouldn't go out unreviewed.

**The story:** after the draft is written, it goes through two separate checks in parallel: Validator A (your own Pydantic + business-rule code — "if risk is High, rollback plan can't be blank") and Validator B, which is Llama Guard reading the drafted content specifically for safety/policy violations. They're deliberately two *separate* agents with separate jobs, not one node doing both — because when something fails, you want to know immediately whether it's a completeness problem or a policy problem, not have to untangle one giant "is this okay?" verdict.

**Why a guard model instead of just prompting the same LLM to "double check itself":** an LLM checking its own output tends to agree with itself. A separate model, purpose-built for safety classification, is a genuinely independent second opinion — the same reason code review isn't done by the person who wrote the code.

---

## Mem0 — the agent's long-term memory

**The problem:** LangGraph's checkpointer remembers *this conversation*. It forgets everything the moment the session ends. But if this user opens a brand new chat next month about another EKS change, it'd be useful if the agent already knew they tend to work on EKS/staging changes.

**The story:** Mem0 sits above the per-session state — it's memory that survives across sessions entirely. After a conversation wraps, relevant facts ("this user's changes are usually staging EKS work, they favor conservative maintenance windows") get written to Mem0. Next month, a new session pulls that context in before the first message is even answered, so the clarify step might already skip a question it would otherwise have asked.

**Where the line is:** LangGraph's checkpointer = memory *within* one CR's conversation. Mem0 = memory *across* every CR this user has ever created. Different problems, different tools.

---

## MCP — the standard wall socket

**The problem:** the Excel writer and the RAG retriever are just Python functions right now — the agent calls them directly, which means only *this* agent, written in *this* codebase, can use them.

**The story:** MCP (Model Context Protocol) wraps a tool behind a standard interface — a defined schema for what inputs it takes and what it returns — so any MCP-compatible agent can call `write_cr_excel` or `retrieve_similar_crs` without knowing anything about how they're implemented internally. It's the difference between wiring an appliance directly into your wall (works, but only in that one house) and giving it a standard plug (works anywhere with a matching socket). In this project it becomes worth doing once you're splitting into multiple cooperating agents (the stretch phase) and want them sharing tools without sharing code.

**Why it's a stretch-phase tool, not a Phase 1 tool:** with a single agent calling its own functions directly, MCP is overhead you don't need yet. It earns its place once "one agent, several tools" becomes "several agents, shared tools."

---

## Langfuse — the flight recorder

**The problem:** the agent is now non-deterministic (LLM calls), multi-step (LangGraph nodes), and asynchronous (waiting on user replies). When something goes wrong three nodes deep, "add a print statement" stops being a viable debugging strategy.

**The story:** every LangGraph node and every LiteLLM call gets wrapped with a Langfuse trace — input, output, latency, token count, tagged with the `session_id`. When a user reports "it asked me the same question twice," you don't guess — you open that session's trace in Langfuse and see, node by node, exactly what the `completeness_check` decided was still missing at each step, and why.

**Why this is worth setting up before things actually break:** retrofitting observability after you've already got a confusing bug is much harder than having the trace already there when the bug happens. It's a flight recorder — useless installed *after* the flight.

---

## Quick Reference Table

| Tool                | One-line role     | Solves                                                     |
| ------------------- | ----------------- | ---------------------------------------------------------- |
| Python              | The language      | Ecosystem — everything else lives here first               |
| FastAPI             | Front door        | Receives chat messages, serves downloads                   |
| Pydantic            | Customs officer   | Rejects malformed LLM output before it spreads             |
| openpyxl            | The hands         | Writes data into the template without breaking formatting  |
| LiteLLM             | Universal adapter | One interface across multiple free LLM providers           |
| NVIDIA NIM / Gemini | The brains        | Actual language understanding and generation               |
| LangGraph           | State machine     | Multi-turn conversation, clarify loops, human review gates |
| Chroma (VectorDB)   | The librarian     | Retrieves similar past CRs to ground writing style         |
| Llama Guard         | Second opinion    | Independent safety/policy check on drafted content         |
| Mem0                | Long-term memory  | Facts that persist across sessions, not just within one    |
| MCP                 | Standard socket   | Tools usable by multiple agents without shared code        |
| Langfuse            | Flight recorder   | Full trace of every node/call for debugging                |

Each tool earns its place at a specific phase in [`ROADMAP.md`](./ROADMAP.md) — nothing here is worth adding before the problem it solves actually shows up.