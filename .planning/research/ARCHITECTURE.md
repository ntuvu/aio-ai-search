# Architecture Research

**Domain:** Claude Code skill package — external API wrapper
**Researched:** 2026-03-09
**Confidence:** HIGH (verified against real SKILL.md examples in `/Users/ntuvu/.claude/plugins/` and the exa-mcp-server reference skills)

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                    Claude Code Session                            │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │                  SKILL.md                                │     │
│  │  (loaded automatically from .claude/skills/ at startup) │     │
│  │  - Frontmatter: name, description, allowed-tools        │     │
│  │  - Body: when to use, how to invoke, output format      │     │
│  └────────────────────────┬────────────────────────────────┘     │
│                            │  subagent reads SKILL.md            │
│                            ▼                                      │
│  ┌──────────────┐   ┌──────────────────────────────────────┐     │
│  │  Subagent    │──▶│  Bash tool invocation                │     │
│  │  (Task fork) │   │  bash .claude/skills/external-tool/  │     │
│  └──────────────┘   │      scripts/exa.sh web-search "q"  │     │
│                      └────────────────┬─────────────────────┘     │
└───────────────────────────────────────│─────────────────────────┘
                                        │
┌───────────────────────────────────────│─────────────────────────┐
│              Skill Package Boundary   │                          │
│   .claude/skills/external-tool/       │                          │
│                                       ▼                          │
│   ┌──────────────┐   ┌─────────────────────────────────────┐    │
│   │    .env      │──▶│          scripts/exa.sh              │    │
│   │  EXA_API_KEY │   │  - sources .env                      │    │
│   └──────────────┘   │  - dispatches on $1 (web-search /   │    │
│                      │    code-context)                      │    │
│   ┌──────────────┐   │  - builds curl payload               │    │
│   │  .env.example│   │  - parses JSON with sed/tr           │    │
│   │  (template)  │   │  - prints results to stdout          │    │
│   └──────────────┘   └─────────────────┬───────────────────┘    │
│                                        │                          │
└────────────────────────────────────────│─────────────────────────┘
                                         │ HTTP POST
                                         ▼
                         ┌───────────────────────────────┐
                         │       Exa API                  │
                         │  POST https://api.exa.ai/      │
                         │    /search  (web-search)       │
                         │    /context (code-context)     │
                         └───────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| `SKILL.md` | Tells the subagent WHEN to use the tool and HOW to invoke the script; loaded by Claude Code at session start | YAML frontmatter + Markdown body |
| `scripts/exa.sh` | Executes the actual API call; single entry point dispatching on subcommand | Pure Bash, Bash 3.2+ compatible |
| `.env` | Holds `EXA_API_KEY`; sourced by the script at runtime; never committed | `key=value` format, chmod 600 |
| `.env.example` | Documents required env vars for setup; safe to commit | Commented template |

## Recommended Project Structure

```
.claude/skills/external-tool/
├── SKILL.md                # Claude Code skill instruction file
├── scripts/
│   └── exa.sh              # Shell script: API caller and response formatter
├── .env                    # Runtime secrets (gitignored)
└── .env.example            # Setup template (committed)
```

### Structure Rationale

- **Single folder:** skill + script + config co-located — the whole unit can be copied to any project
- **`scripts/` subfolder:** consistent with real-world skill patterns (ui-ux-pro-max uses `scripts/`, qmd release skill uses `scripts/`)
- **No `lib/` split:** this is a two-command tool, not a framework; one file is the right abstraction level
- **`.env` at package root:** scoped to the skill, not the project root — avoids collisions with other `.env` files in the repo

## Architectural Patterns

### Pattern 1: SKILL.md as Subagent Instruction File

**What:** SKILL.md is a Markdown file with YAML frontmatter that Claude Code reads at session start. It instructs the subagent when to trigger and exactly how to invoke the underlying tool. It is not code — it is an instruction document.

**When to use:** Any tool a subagent should know how to call without human direction.

**Trade-offs:** Simple to author; no runtime overhead. Constraint: instructions must be precise — vague SKILL.md produces inconsistent invocation behavior.

**Frontmatter fields observed in real skills:**
```yaml
---
name: web-search-exa                    # Identifier; used in allowed-tools
description: "When to use this skill"  # Rich natural language; subagent uses this to decide when to activate
context: fork                           # "fork" = spawn Task subagent; prevents context pollution
allowed-tools: Bash(scripts/exa.sh:*)  # Restricts which tools are permitted in this skill context
---
```

**Body sections that matter:**
- "Tool Restriction" — tells the subagent to only call the specific script, not improvise
- "When to Use" — conditions for activation
- "Inputs" — exact argument signature with types and defaults
- "Output Format" — what the subagent should return to the parent

### Pattern 2: Script as Thin CLI Adapter

**What:** The shell script is the sole bridge between Claude's Bash tool and the external API. It reads credentials from `.env`, constructs the HTTP request, calls `curl`, and formats the response for stdout. The subagent captures stdout.

**When to use:** Always — the script is the only non-instruction code in the skill package.

**Trade-offs:** Pure Bash means zero dependencies; macOS-compatible with Bash 3.2+. Constraint: JSON parsing without `jq` requires `sed`/`tr` discipline.

**Canonical script interface (both commands must follow this contract):**
```bash
# Invocation (web search)
bash .claude/skills/external-tool/scripts/exa.sh web-search "<query>"

# Invocation (code context)
bash .claude/skills/external-tool/scripts/exa.sh code-context "<query>"

# Exit codes
# 0 = success, results printed to stdout
# 1 = error (missing key, API error), message printed to stderr

# Stdout contract
# web-search: formatted list of result titles + URLs + text snippets
# code-context: unescaped code/documentation text ready for LLM consumption
```

**Env loading pattern:**
```bash
# Load .env from same directory as this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
if [ -f "$ENV_FILE" ]; then
    . "$ENV_FILE"
fi
if [ -z "$EXA_API_KEY" ]; then
    echo "ERROR: EXA_API_KEY not set. Add it to .env" >&2
    exit 1
fi
```

### Pattern 3: Token Isolation via `context: fork`

**What:** The `context: fork` frontmatter key instructs Claude Code to execute the skill in a forked subagent context. All Exa results are processed there; only the distilled summary reaches the main context.

**When to use:** Any skill that fetches large external responses (search results, docs). Prevents context window contamination.

**Trade-offs:** Slight latency increase from spawning. Benefit: main context stays clean regardless of result volume. This is the pattern used by all exa-mcp-server skills.

## Data Flow

### Subagent Invocation Flow

```
1. Claude Code loads SKILL.md at session start
   └─ registers "web-search-exa" skill

2. User query triggers subagent decision
   └─ SKILL.md description matches user intent
   └─ subagent forks (context: fork)

3. Subagent reads SKILL.md body
   └─ learns: call scripts/exa.sh with subcommand + query arg

4. Subagent issues Bash tool call
   └─ bash .claude/skills/external-tool/scripts/exa.sh web-search "<query>"

5. exa.sh executes
   └─ sources .env → reads EXA_API_KEY
   └─ builds JSON payload
   └─ curl POST https://api.exa.ai/search
   └─ parses response with sed/tr
   └─ prints formatted results to stdout

6. Bash tool captures stdout
   └─ returns to subagent as tool result

7. Subagent processes results
   └─ deduplicates (per SKILL.md output instructions)
   └─ returns distilled summary to main context
```

### API Request/Response Flow

**web-search (POST /search):**
```
Request payload:
{
  "query": "<arg>",
  "type": "auto",
  "numResults": 8,
  "contents": {
    "context": { "maxCharacters": 10000 },
    "livecrawl": "fallback"
  }
}

Response: { "context": "<LLM-ready text string>" }
Parse: extract .context field directly — single string, no array iteration needed
```

**code-context (POST /context):**
```
Request payload:
{
  "query": "<arg>",
  "tokensNum": 5000
}

Response: { "response": "<code/docs string with escape sequences>" }
Parse: extract .response field, unescape \n \t \" sequences
```

### Key Data Flows

1. **Credential flow:** `.env` → sourced into `exa.sh` environment → passed as `x-api-key` header in curl
2. **Result flow:** Exa API JSON response → sed/tr parsing in `exa.sh` → stdout → Bash tool result → subagent → distilled text → main context

## Scaling Considerations

This is a single-user CLI skill, not a multi-user service. Scaling considerations are irrelevant — the only concern is API rate limits and response latency.

| Concern | Approach |
|---------|----------|
| API rate limits | Exa enforces server-side; script propagates 429 errors to stderr |
| Large responses | `contextMaxCharacters` and `tokensNum` parameters cap response size at request time |
| Slow API calls | curl timeout flag (`--max-time 30`) prevents indefinite hangs |

## Anti-Patterns

### Anti-Pattern 1: Hardcoding API Key in Script

**What people do:** Set `EXA_API_KEY="sk-..."` directly in `exa.sh` for convenience.

**Why it's wrong:** The script is committed to git. Key leaks. The `.env` + gitignore pattern exists for exactly this reason.

**Do this instead:** Source `.env` at runtime; validate key presence at script start; exit 1 with clear error if missing.

### Anti-Pattern 2: Running API Calls in Main Context

**What people do:** Invoke the script directly from the main Claude Code context instead of delegating to a subagent via `context: fork`.

**Why it's wrong:** Exa responses can be 10,000+ characters. Inline in main context this consumes context window budget and pollutes the conversation. The exa-mcp-server skills document this explicitly as "Token Isolation (Critical)."

**Do this instead:** Set `context: fork` in SKILL.md frontmatter; instruct the subagent to summarize before returning.

### Anti-Pattern 3: One Script Per Command

**What people do:** Create `web-search.sh` and `code-context.sh` as separate files.

**Why it's wrong:** Two files means two maintenance points, duplicated env loading logic, and a more complex directory to explain. The `exa.sh <subcommand>` dispatch pattern keeps the skill a single-file script.

**Do this instead:** Single `exa.sh` with `case "$1" in web-search|code-context)` dispatch. Each branch handles its own payload construction and response parsing.

### Anti-Pattern 4: Vague SKILL.md Description

**What people do:** Write `description: "Search the web"` — too generic.

**Why it's wrong:** The subagent uses the description to decide when to activate the skill. A vague description causes either false activations (skill fires for every question) or missed activations (skill never fires because it doesn't match).

**Do this instead:** Write a description that names the tool, the provider, concrete use cases, and trigger phrases. The ui-ux-pro-max SKILL.md is the benchmark — its description is 200+ words of specific triggers.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Exa `/search` | curl POST with JSON body; API key in `x-api-key` header | Returns `.context` string — no results array to iterate; simpler than the `results[]` pattern used in the existing `providers/exa.sh` |
| Exa `/context` | curl POST with JSON body; API key in `x-api-key` header | Returns `.response` string with JSON escape sequences; must unescape before returning to subagent |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| SKILL.md → exa.sh | Claude's Bash tool executes the script path named in SKILL.md | Path must be relative to project root OR absolute; use `$SKILL_DIR` pattern for portability |
| exa.sh → .env | Shell `source` / `. "$ENV_FILE"` | Load relative to script location using `$(dirname "$0")`; fail fast if key absent |
| subagent → main context | Subagent stdout captured by Claude as tool result | Subagent must summarize/distill before returning; SKILL.md "Output Format" section governs this |

## Build Order

For the skill to work end-to-end, build in this sequence:

1. **`scripts/exa.sh`** — the executable core; can be tested standalone with `curl` before SKILL.md exists
2. **`.env.example`** — document the key format so setup is clear
3. **`.env`** — populate with real key; verify `exa.sh web-search "test"` returns results
4. **`SKILL.md`** — write instruction file last, once the script interface is locked; frontmatter `name` must match what subagent will be told to use

## Sources

- Real SKILL.md patterns: `/Users/ntuvu/.claude/plugins/cache/qmd/qmd/0.1.0/skills/` (qmd, release skills)
- Real SKILL.md patterns: `/Users/ntuvu/.claude/plugins/cache/ui-ux-pro-max-skill/` (ui-ux-pro-max skill with script invocation)
- Real SKILL.md patterns: `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/skills/` (code-search, research-paper-search, x-search)
- Exa API endpoint reference: `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/config.ts` — `BASE_URL: 'https://api.exa.ai'`, `SEARCH: '/search'`, `CONTEXT: '/context'`
- Exa web-search request shape: `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/webSearch.ts`
- Exa code-context request shape: `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/exaCode.ts`
- Token isolation pattern: exa-mcp-server skills — "Token Isolation (Critical)" section present in all category skills
- Bash JSON parsing patterns: project MEMORY.md — `sed 's/},{/|@@|/g'` delimiter split, unescape sequences

---
*Architecture research for: Claude Code skill package wrapping Exa search API*
*Researched: 2026-03-09*
