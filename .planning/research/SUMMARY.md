# Project Research Summary

**Project:** aio-ai-search — Claude Code external-tool skill (Exa API wrapper)
**Domain:** Claude Code skill package — Bash script wrapping a REST API
**Researched:** 2026-03-09
**Confidence:** HIGH

## Executive Summary

This project is a Claude Code skill package that wraps the Exa web-search and code-context APIs in a Bash script, making them callable by Claude Code subagents. Experts build this type of tool as a minimal, self-contained script package: one shell script dispatching two subcommands, one SKILL.md instruction file that tells Claude Code when and how to invoke the script, and a `.env` file for the API key. The entire stack — Bash 3.2, curl, sed, tr — ships pre-installed on macOS and Linux, so no package installation is required for any user.

The recommended approach is to build in strict dependency order: scaffold `.env` loading and error handling first (before any API calls), then implement the two curl endpoints with JSON field extraction, then write SKILL.md last once the script interface is locked. This order matters because the most dangerous pitfalls (API key leaks via git, broken `.env` path resolution) occur before a single API call is written. The core implementation is genuinely simple — both Exa endpoints return a single top-level string field, not an array — which means JSON parsing requires only a one-step `sed` extraction per endpoint, not a full parser.

The dominant risks are environment and configuration problems, not algorithmic ones. The three highest-severity risks are: (1) API key committed to git if `.gitignore` is not in place before `.env` is created, (2) `context: fork` omitted from SKILL.md frontmatter causing Exa's large responses to contaminate the main context window, and (3) `.env` loaded via relative path (`./. env`) which breaks when the script is invoked from a different working directory. All three are prevention problems — they are trivial to avoid in Phase 1 and expensive to recover from later.

## Key Findings

### Recommended Stack

The full stack is Bash 3.2 + curl + sed + tr. There are no installable dependencies. Bash 3.2 is the macOS default since OS X 10.3; targeting it explicitly ensures the script runs on every macOS machine without Homebrew. curl handles TLS, authentication headers, request body, and timeout in a single call. sed extracts string fields from JSON responses. tr handles newline and tab unescaping in the code-context response field.

**Core technologies:**
- **Bash 3.2+**: Script runtime and subcommand dispatch — macOS default, zero installation required; do not use Bash 4+ features (`declare -A`, `mapfile`, `source` keyword)
- **curl**: HTTP client for POST requests to Exa API — pre-installed everywhere; use `--silent --show-error --fail-with-body --max-time 30` on every call
- **sed (POSIX)**: JSON field extraction — use `[^"]*` (non-greedy) rather than `.*` (greedy) to avoid extracting past the field boundary
- **tr (POSIX)**: Unescape JSON sequences in code-context `.response` field — `\n`, `\t`, `\"` must be converted before returning to subagent
- **SKILL.md**: Claude Code skill instruction file — YAML frontmatter (`name`, `description`, `context: fork`, `allowed-tools: Bash`) plus Markdown body with invocation contract

### Expected Features

Both Exa endpoints return a single top-level string field (`.context` for `/search`, `.response` for `/context`) making them far simpler to parse than typical REST APIs returning result arrays. The full MVP is deliverable in a single phase.

**Must have (table stakes):**
- `web-search` subcommand (`bash exa.sh web-search "<query>"`) — dispatches to `POST https://api.exa.ai/search`, prints `.context` field
- `code-context` subcommand (`bash exa.sh code-context "<query>"`) — dispatches to `POST https://api.exa.ai/context`, prints `.response` field (unescaped)
- `.env` loading with `SCRIPT_DIR`-relative path resolution and fast failure if `EXA_API_KEY` is missing
- Non-zero exit with `stderr` error message on API failure, missing key, or empty response
- LLM-ready stdout — print the API string field verbatim with no decoration
- `SKILL.md` with `context: fork`, `allowed-tools: Bash`, trigger description, invocation examples, query-writing guidance, and forked-agent instruction
- `.env.example` with `EXA_API_KEY=your_key_here`
- `.gitignore` entry for `.env` (pattern `**/.env` to cover nested paths)

**Should have (differentiators):**
- `--num-results N` flag for web-search (maps to `numResults` param, default 8)
- `--tokens N` flag for code-context (maps to `tokensNum` param, default 5000, range 1000–50000)
- Distinct error class prefixes in stderr (`AUTH_ERROR:`, `NO_RESULTS:`, `RATE_LIMIT:`) — enables subagent retry logic
- Query-writing guidance in SKILL.md (specify language, framework, version in queries)
- Token tuning guidance in SKILL.md (1000–3000 for focused snippet, 5000 default, 10000+ for integration depth)

**Defer (v2+):**
- Advanced Exa params (category, livecrawl, domain filters) — adds Bash flag parsing complexity with low use frequency
- Additional Exa tools (company research, deep research, LinkedIn) — explicitly out of scope per PROJECT.md

### Architecture Approach

The skill package is a 4-file unit: `SKILL.md` (subagent instruction), `scripts/exa.sh` (API executor), `.env` (runtime secret), `.env.example` (setup template). Claude Code loads SKILL.md at session start; when user intent matches the skill description, a forked subagent invokes `exa.sh` via the Bash tool, captures stdout, distills it, and returns only the summary to the main context. The entire response processing chain — credential loading, HTTP request, JSON extraction, output formatting — lives in `exa.sh`, keeping the skill self-contained and portable across any project.

**Major components:**
1. **SKILL.md** — Subagent trigger and invocation contract; `context: fork` is mandatory to prevent Exa's large responses from consuming main context; `allowed-tools: Bash` restricts the forked agent to only the script
2. **scripts/exa.sh** — Single entry point with `case "$1" in web-search|code-context)` dispatch; handles `.env` loading, payload construction, curl POST, `sed` field extraction, and stdout/stderr separation
3. **.env** — `EXA_API_KEY=value` at skill package root; sourced via `$SCRIPT_DIR`-relative path; `chmod 600`; gitignored
4. **.env.example** — Committed template documenting required keys for setup

### Critical Pitfalls

1. **API key committed to git** — Add `**/.env` to root `.gitignore` before creating `.env`; never hardcode key in script; run `git status` check before first commit; recovery requires key rotation and git history purge
2. **`context: fork` missing from SKILL.md** — Exa responses are 2,000–20,000+ characters; without fork isolation they contaminate the main context window; set `context: fork` and `allowed-tools: Bash` in every SKILL.md, no exceptions
3. **`.env` resolved via relative path** — `source ./.env` breaks when script is invoked from a different `$PWD`; always derive path with `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` at script top
4. **Greedy `sed` regex extracts wrong field** — `s/.*"context":"\(.*\)".*/\1/` extends to the last `"` in the response; use `[^"]*` instead of `.*` for the value capture group to stop at the first closing quote
5. **curl non-2xx responses treated as success** — curl exits 0 on HTTP 401/429/500 by default; add `--fail-with-body` to every curl call and explicitly check `$?`; without this, error JSON is passed to the `sed` parser and produces empty or garbled output

## Implications for Roadmap

Based on research, this project maps cleanly to 3 phases. The simplicity of the two-endpoint API (single string field per response) means the full implementation is fast; the phases are separated by concern, not by volume of work.

### Phase 1: Scaffold and Security Foundation
**Rationale:** All three highest-severity pitfalls (API key leak, broken `.env` path, missing Bash 3.2 guard) occur before a single line of API code is written. Establishing the file structure, `.gitignore`, and `.env` loading pattern first eliminates the irreversible risk (committed key) and the hard-to-debug risk (path resolution). This is the one phase where order matters absolutely.
**Delivers:** Skeleton `exa.sh` with `set -euo pipefail`, `SCRIPT_DIR`-relative `.env` loading, fast failure on missing key, empty `web-search`/`code-context` stubs; `.env.example`; `.gitignore` with `**/.env`; project directory structure
**Addresses:** API key loading (table stakes), `.gitignore` entry (table stakes)
**Avoids:** API key committed to git (Pitfall 8), broken `.env` path (Pitfall 4), Bash 3.2 syntax errors (Pitfall 1)

### Phase 2: API Integration and JSON Parsing
**Rationale:** With the scaffold in place, implement the actual curl calls and response parsing. Both endpoints share the same authentication pattern and similar payload structure, so implementing them together avoids duplicated setup. Error handling (curl `--fail-with-body`, exit codes, stderr messages) must be built into this phase, not added later — silent failures are the hardest bugs to diagnose in a subagent context.
**Delivers:** Working `web-search` subcommand returning `.context` string; working `code-context` subcommand returning unescaped `.response` string; non-zero exit with readable `stderr` on API errors; `--max-time 30` timeout on both curl calls
**Uses:** curl POST pattern from STACK.md; `sed` non-greedy extraction pattern; `tr`/`printf` unescape sequence for code-context
**Implements:** `scripts/exa.sh` script (CLI adapter component); credential flow and result flow from architecture
**Avoids:** Greedy `sed` extraction (Pitfall 3), curl non-2xx treated as success (Pitfall 7), missing `read -r` (Pitfall 2), wrong field name per endpoint (integration gotcha)

### Phase 3: SKILL.md and Subagent Integration
**Rationale:** SKILL.md is written last, once the script interface is locked, so the invocation contract it documents exactly matches what the script accepts. A SKILL.md written before the script is finalized will document wrong argument forms. This phase also includes the end-to-end smoke test (subagent invokes the skill, context isolation confirmed).
**Delivers:** `SKILL.md` with `context: fork`, `allowed-tools: Bash`, rich trigger description, invocation examples for both subcommands, query-writing guidance, token-tuning guidance, forked-agent instruction, output format spec; smoke test confirming subagent isolation
**Avoids:** Missing `context: fork` (Pitfall 5), wrong `allowed-tools` capitalization (Pitfall 6), vague SKILL.md description (Architecture anti-pattern 4)

### Phase 4: Passthrough Flags and Error Classes (v1.x)
**Rationale:** Deliver after the core call/response cycle is validated working. These features enhance usability but do not affect correctness — wrong defaults are recoverable, wrong output format is not.
**Delivers:** `--num-results N` flag for web-search; `--tokens N` flag for code-context; distinct `AUTH_ERROR:`, `NO_RESULTS:`, `RATE_LIMIT:` prefixes in stderr messages
**Implements:** Flag parsing via `while`/`case`/`shift` loop (not `getopts`); distinct error class messaging

### Phase Ordering Rationale

- Phase 1 must precede Phase 2 because `.env` loading, `set -euo pipefail`, and `.gitignore` are structural foundations that cannot be safely retrofitted after API code exists
- Phase 2 must precede Phase 3 because SKILL.md documents the script's argument interface — writing it before the interface is locked produces documentation drift
- Phase 4 is independent of Phase 3 and can be deferred indefinitely without breaking the skill
- Both API endpoints are implemented together in Phase 2 because they share auth, error handling, and `$SCRIPT_DIR`-path patterns; splitting them into separate phases would require revisiting the same boilerplate twice

### Research Flags

Phases with standard, well-documented patterns (skip `/gsd:research-phase`):
- **Phase 1 (Scaffold):** Bash script scaffolding is a solved problem; `.env` loading pattern and `.gitignore` setup are fully specified in STACK.md and PITFALLS.md
- **Phase 2 (API Integration):** Both Exa endpoint shapes are verified from the exa-mcp-server reference implementation; curl flag set and `sed` extraction patterns are fully specified in STACK.md
- **Phase 3 (SKILL.md):** SKILL.md frontmatter schema verified against 3 real installed skill files; all required fields documented in STACK.md and ARCHITECTURE.md
- **Phase 4 (Passthrough Flags):** Standard Bash flag parsing with `while`/`case`/`shift` is well-documented; no research needed

No phase requires `/gsd:research-phase` — the research is complete and authoritative.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified against exa-mcp-server TypeScript reference and 3 real installed SKILL.md files in `/Users/ntuvu/.claude/plugins/cache/`; all patterns are directly observable |
| Features | HIGH | Feature set derived from production reference implementation; scope constraints confirmed from PROJECT.md; no inference required |
| Architecture | HIGH | File structure and component boundaries verified from real deployed skills; `context: fork` behavior and `allowed-tools` syntax confirmed empirically |
| Pitfalls | HIGH | Pitfalls derived from concrete Bash 3.2 constraints, curl behavior, and observed SKILL.md failure modes; not speculative |

**Overall confidence:** HIGH

### Gaps to Address

- **Exa API `/search` vs `/context` response shapes need fixture validation:** STACK.md notes the `/search` endpoint returns `.context` at the top level (not `.results[].text`), but PITFALLS.md (integration gotchas) contradicts this, stating `/search` returns `.results[]` array with `.text` per result. This discrepancy must be resolved by making a real API call in Phase 2 before writing the parser. If `/search` returns an array, the `sed 's/},{/|@@|/g'` delimiter split pattern from MEMORY.md is required.
- **`.env` quote format:** PITFALLS.md recommends writing `.env` values without surrounding quotes (`EXA_API_KEY=abc123`), but real-world Exa API keys may contain characters requiring quoting. Document the expected format in `.env.example` and validate with a real key in Phase 1.

## Sources

### Primary (HIGH confidence)
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/webSearch.ts` — auth header name, request shape, `.context` response field, 25s timeout
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/exaCode.ts` — `.response` field, `tokensNum` range (1000–50000), 30s timeout
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/config.ts` — API base URL, endpoint paths, defaults (8 results, 2000 chars)
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/skills/code-search/SKILL.md` — canonical SKILL.md pattern for this exact tool
- `/Users/ntuvu/.claude/plugins/cache/qmd/qmd/0.1.0/skills/` — `allowed-tools` field syntax, minimal frontmatter validation
- `/Users/ntuvu/.claude/plugins/cache/ui-ux-pro-max-skill/` — rich `description` field benchmark (200+ words of specific triggers)
- Project `MEMORY.md` — `sed 's/},{/|@@|/g'` array parsing pattern, escape sequence handling

### Secondary (MEDIUM confidence)
- Bash 3.2 release notes and changelog — Bash 4+ feature exclusions (associative arrays, `mapfile`, `source` keyword)
- curl documentation — `--fail-with-body` availability (curl 7.76.0, April 2021)
- shellcheck documentation — `read -r` requirement (SC2162)

### Tertiary (LOW confidence)
- Exa API public documentation (https://docs.exa.ai/reference/) — endpoint reference; not directly verified; superseded by the reference TypeScript implementation

---
*Research completed: 2026-03-09*
*Ready for roadmap: yes*
