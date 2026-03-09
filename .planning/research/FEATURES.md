# Feature Research

**Domain:** Claude Code skill — external API wrapper (Exa web search + code context)
**Researched:** 2026-03-09
**Confidence:** HIGH (primary sources: exa-mcp-server reference implementation, existing SKILL.md examples)

## Feature Landscape

### Table Stakes (Users Expect These)

Features the skill must have or it is non-functional for subagents.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `web-search` subcommand | Core tool — no web search = skill is useless | LOW | `bash exa.sh web-search "<query>"` — dispatches to POST /search |
| `code-context` subcommand | Core tool — no code context = skill is half-broken | LOW | `bash exa.sh code-context "<query>"` — dispatches to POST /context |
| API key loading from `.env` | Without auth, every call returns 401 | LOW | Source `.env` at script top; fail fast with clear message if missing |
| Non-zero exit on API error | Subagents check exit codes; silent failure hides problems | LOW | `exit 1` on HTTP error, missing key, empty response |
| Human-readable error messages on stderr | Subagent must know WHY it failed, not just that it did | LOW | "Error: EXA_API_KEY not set in .env" vs silent exit |
| LLM-ready output on stdout | The skill exists to feed text to an LLM — must be clean text | LOW | webSearch returns `context` string; codeContext returns `response` string — print as-is, no decoration |
| SKILL.md that describes invocation contract | Without it, subagents don't know the tool exists or how to call it | MEDIUM | Must cover: when to use each tool, required/optional args, output shape, example calls |
| `.env.example` documenting required keys | Without this, humans cannot set up the skill | LOW | `EXA_API_KEY=your_key_here` |
| `.gitignore` entry for `.env` | API key leak risk — must be excluded from commits | LOW | Add `.env` to root `.gitignore` or skill-local gitignore |

### Differentiators (Competitive Advantage)

Features that make the skill better than a raw `curl` invocation.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Query writing guidance in SKILL.md | Subagents write better queries → better results; raw curl has no guidance | LOW | Specify: include language name, include framework+version, use exact identifiers. Evidence from exa-mcp-server code-search SKILL.md |
| Dynamic token tuning guidance for code-context | Subagents waste tokens or get thin results without guidance | LOW | Document: 1000–3000 for focused snippet, 5000 default, 10000–20000 for integration depth — aligns with `tokensNum` 1000–50000 range |
| "Use in forked agent" instruction | Prevents main context pollution from large search results | LOW | Instruction: spawn a Task agent to run this skill, extract minimum snippet, return only that. Pattern from exa code-search SKILL.md |
| Deduplication guidance | Exa often returns mirrored/forked repos and repeated SO answers | LOW | Instruct agent to deduplicate before presenting — documented pattern from reference SKILL.md |
| Distinct error class messaging | Subagents can react differently to "no results" vs "auth failure" vs "rate limit" | MEDIUM | Exit code 1 + message: "NO_RESULTS: ...", "AUTH_ERROR: ...", "RATE_LIMIT: ..." on stderr |
| numResults passthrough (web-search) | Default 8 results is wrong for many tasks; caller should control depth | LOW | `bash exa.sh web-search "<query>" --num-results 15` — maps to `numResults` param |
| tokensNum passthrough (code-context) | Default 5000 tokens is wrong for many tasks | LOW | `bash exa.sh code-context "<query>" --tokens 10000` — maps to `tokensNum` param |
| Output format guidance in SKILL.md | Without this, subagents dump raw API text back to user | LOW | Specify: return snippet + constraints/gotchas + source URLs; deduplicate near-identical results before presenting |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| All Exa API params exposed (category, livecrawl, type, domain filters) | Feels complete/powerful | Bash flag parsing becomes brittle; PROJECT.md explicitly scopes to web + code for v1; advanced params often cause 400 errors in wrong category combos | Build a working v1 first; add advanced params in v1.x if actual use cases emerge |
| JSON-structured output | Seems more machine-parseable | Exa already returns LLM-ready context strings — converting to JSON adds escaping complexity with no benefit for the LLM consumer | Return the raw `context`/`response` string; it is already optimized for LLM use |
| Result caching / deduplication logic in shell script | Avoid repeat API calls | Adds significant Bash complexity; stale cache causes wrong results; not needed for a skill that runs per-query | Let the LLM subagent deduplicate at the reasoning layer via SKILL.md instruction |
| Interactive / REPL mode | Developer convenience | Skills are called non-interactively by subagents; interactive mode adds code with zero real-world use | Non-interactive only — stdin args, stdout output, done |
| Integration with `ais` CLI | Reuse existing code | PROJECT.md explicitly makes this standalone; coupling creates dependency that breaks portability | Skill is self-contained; reference exa.sh patterns but do not import them |
| Retry logic with backoff | Robustness | Shell-based retry loops add 30–60 lines of Bash; rate limit recovery is better handled by the subagent deciding to retry | Exit with distinct error code; let the calling agent handle retry |
| Node.js or Python implementation | More powerful string handling | Violates core constraint (Bash 3.2+, no dependencies); breaks portability to any machine with curl | Bash + curl + sed/tr — sufficient for extracting `context` and `response` fields |

## Feature Dependencies

```
[SKILL.md invocation contract]
    └──requires──> [web-search subcommand works]
    └──requires──> [code-context subcommand works]
    └──requires──> [.env API key loading works]

[web-search subcommand]
    └──requires──> [API key loading]
    └──requires──> [LLM-ready stdout output]
    └──requires──> [Non-zero exit on error]

[code-context subcommand]
    └──requires──> [API key loading]
    └──requires──> [LLM-ready stdout output]
    └──requires──> [Non-zero exit on error]

[numResults passthrough] ──enhances──> [web-search subcommand]
[tokensNum passthrough] ──enhances──> [code-context subcommand]
[distinct error class messaging] ──enhances──> [Non-zero exit on error]
```

### Dependency Notes

- **SKILL.md requires both subcommands work:** The skill file is the contract; it is only useful if the underlying script matches what it documents.
- **Both subcommands require API key loading:** No auth = 401 on every call. Key loading must be the first thing the script does.
- **Passthrough params enhance but do not block:** v1 works without them; add them once the basic call/response cycle is confirmed working.

## MVP Definition

### Launch With (v1)

Minimum viable product — the skill becomes callable by a subagent and returns useful results.

- [ ] `exa.sh` script with `web-search` and `code-context` subcommands — core functionality
- [ ] `.env` loading at script start with fast failure if `EXA_API_KEY` is missing — auth is table stakes
- [ ] LLM-ready stdout: print the `context` field (web-search) and `response` field (code-context) verbatim — no decoration
- [ ] Non-zero exit on error with stderr message — subagents need to detect failures
- [ ] `SKILL.md` with: description, when to use each tool, invocation examples, forked-agent instruction, query writing guidance — the skill is invisible without this
- [ ] `.env.example` with `EXA_API_KEY=your_key_here` — humans cannot set up without it
- [ ] `.gitignore` entry for `.env` — key must not be committed

### Add After Validation (v1.x)

Features to add once the core call/response cycle is verified working.

- [ ] `--num-results N` flag for web-search — add when callers need depth control beyond default 8
- [ ] `--tokens N` flag for code-context — add when callers need more than default 5000 tokens
- [ ] Distinct error codes in stderr messages (AUTH_ERROR, NO_RESULTS, RATE_LIMIT) — add when subagent retry logic is being built

### Future Consideration (v2+)

Features to defer until the skill proves its value in real sessions.

- [ ] Advanced Exa params (category, livecrawl, domain filters) — defer until use cases justify the Bash complexity
- [ ] Additional Exa tools beyond web + code (company research, deep research, LinkedIn) — explicitly out of scope per PROJECT.md

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| web-search subcommand | HIGH | LOW | P1 |
| code-context subcommand | HIGH | LOW | P1 |
| API key loading + fast failure | HIGH | LOW | P1 |
| LLM-ready stdout output | HIGH | LOW | P1 |
| Non-zero exit on error | HIGH | LOW | P1 |
| SKILL.md invocation contract | HIGH | MEDIUM | P1 |
| .env.example | MEDIUM | LOW | P1 |
| .gitignore for .env | MEDIUM | LOW | P1 |
| Query writing guidance in SKILL.md | HIGH | LOW | P1 |
| Forked-agent instruction in SKILL.md | HIGH | LOW | P1 |
| Dynamic token tuning guidance | MEDIUM | LOW | P2 |
| --num-results passthrough | MEDIUM | LOW | P2 |
| --tokens passthrough | MEDIUM | LOW | P2 |
| Distinct error class messaging | LOW | MEDIUM | P2 |
| Advanced Exa API params | LOW | HIGH | P3 |
| Additional Exa tools | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

This is an internal tool wrapper (not competing on a market), but the reference implementation (exa-mcp-server) provides a clear baseline.

| Feature | exa-mcp-server (Node/MCP) | This skill (Bash/Claude Code) |
|---------|--------------------------|-------------------------------|
| web_search_exa | Full param support via Zod schema | web-search subcommand, query + optional numResults for v1 |
| get_code_context_exa | Full param support, tokensNum 1000–50000 | code-context subcommand, query + optional tokens for v1 |
| Auth | env var EXA_API_KEY | .env file loaded by script |
| Error handling | HTTP status + rate limit detection | exit 1 + stderr message; rate limit as distinct error class in v1.x |
| Output format | LLM-ready text (context string) | Same — print verbatim |
| Invocation contract | MCP tool schema (auto-discovered) | SKILL.md (manually read by subagent) |
| Context isolation | MCP protocol boundary | Forked Task agent per SKILL.md instruction |
| Dependencies | Node.js, npm packages | curl only (Bash 3.2+) |

## Sources

- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/webSearch.ts` — canonical web_search_exa implementation, param names, response shape (HIGH confidence)
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/exaCode.ts` — canonical get_code_context_exa implementation, tokensNum range, response shape (HIGH confidence)
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/skills/code-search/SKILL.md` — canonical SKILL.md pattern for this exact tool (HIGH confidence)
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/skills/company-search/SKILL.md` — SKILL.md pattern: token isolation, dynamic tuning, query variation (HIGH confidence)
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/config.ts` — API endpoints: POST /search, POST /context; defaults: 8 results, 2000 chars (HIGH confidence)
- `/Users/ntuvu/Desktop/workspace/projects/aio-ai-search/.planning/PROJECT.md` — scope constraints, Bash-only requirement, .env location, out-of-scope items (HIGH confidence)

---
*Feature research for: Claude Code skill wrapping Exa web-search and code-context APIs*
*Researched: 2026-03-09*
