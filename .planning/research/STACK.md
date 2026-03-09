# Technology Stack

**Project:** aio-ai-search — Claude Code external-tool skill (Exa API wrapper)
**Researched:** 2026-03-09
**Confidence:** HIGH (verified against reference implementation at `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/` and real installed SKILL.md files in `/Users/ntuvu/.claude/plugins/cache/`)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Bash | 3.2+ | Script runtime — dispatches subcommands, loads config, builds HTTP payloads | macOS ships Bash 3.2 as `/bin/bash`; zero installation required; consistent with existing `ais` project patterns |
| curl | system | HTTP client — sends POST requests to Exa API | Pre-installed on macOS and all major Linux distros; handles TLS, headers, request body, timeout, and error codes without any dependencies |
| sed | POSIX | JSON field extraction — pulls single string values from API responses | Universally available; sufficient for the two response shapes this skill handles (`.context` string, `.response` string); no external packages |
| tr | POSIX | Unescape JSON sequences — converts `\n`, `\t` to real characters in `code-context` responses | Single-purpose, always available; the code-context `.response` field contains JSON-escaped text that must be unescaped before displaying |

### Supporting Files

| File | Purpose | When to Use |
|------|---------|-------------|
| `SKILL.md` | Instruction document for Claude Code subagents — YAML frontmatter declares skill identity; Markdown body specifies when and how to invoke the script | Required for subagent discoverability; without it the script is invisible to Claude Code |
| `.env` | Runtime secrets storage — holds `EXA_API_KEY=sk-...`; sourced by `exa.sh` at startup | Always present at runtime; never committed to git |
| `.env.example` | Setup template — documents required keys with placeholder values | Committed to git; tells new users what to populate |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| shellcheck | Static analysis for Bash scripts | Run against `scripts/exa.sh` to catch quoting errors, unbound variables, and Bash 3.2 incompatibilities before runtime |
| curl (manual) | Smoke-test API calls before the script exists | `curl -X POST https://api.exa.ai/search -H "x-api-key: $EXA_API_KEY" -H "content-type: application/json" -d '{...}'` verifies the API contract independently |

---

## Technique Specifications

### 1. curl Flags for POST JSON Requests

The exact flag set required for Exa API calls:

```bash
curl \
  --silent \
  --show-error \
  --max-time 30 \
  -X POST \
  -H "accept: application/json" \
  -H "content-type: application/json" \
  -H "x-api-key: $EXA_API_KEY" \
  -d "$payload" \
  "https://api.exa.ai/search"
```

**Flag rationale:**
- `--silent` — suppresses the progress meter that would corrupt stdout output read by the subagent
- `--show-error` — re-enables error messages on stderr even when `--silent` is set; without this, network failures are invisible
- `--max-time 30` — prevents indefinite hangs on slow responses; 30s matches the 25–30s timeout used in the Node reference implementation (`webSearch.ts` uses 25000ms, `exaCode.ts` uses 30000ms)
- `-X POST` — explicit method declaration; required because the default is GET
- `-H "accept: application/json"` — tells the server the client expects JSON back
- `-H "content-type: application/json"` — tells the server the request body is JSON
- `-H "x-api-key: $EXA_API_KEY"` — Exa authentication header (verified from `webSearch.ts` line 43: `'x-api-key': config?.exaApiKey || process.env.EXA_API_KEY`)
- `-d "$payload"` — request body as a variable; build the payload string in Bash before the curl call

### 2. Bash JSON Extraction — Single String Field

Both Exa endpoints return a top-level string field. No array iteration is needed. The extraction pattern is:

**For `web-search` — extract `.context`:**
```bash
context=$(echo "$response" | sed 's/.*"context":"\(.*\)".*/\1/')
```

**For `code-context` — extract `.response` and unescape:**
```bash
result=$(echo "$response" | sed 's/.*"response":"\(.*\)".*/\1/')
# Unescape JSON sequences
result=$(printf '%s' "$result" | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g')
```

**Why this approach:**
- No `jq` dependency — the single-field extraction pattern is sufficient for both response shapes
- `sed` regex captures everything between the first `"context":"` and the final `"` — works for large string values
- The unescape step is required for `code-context`: the `.response` field contains raw code with `\n` newlines and `\t` indentation encoded as JSON escape sequences
- For the `web-search` `.context` field, unescaping is optional (the context string is already prose); apply same pattern for consistency

**Limitation to document:** This sed pattern breaks if the JSON field value contains literal `"` characters that were not escaped. The Exa API JSON-encodes all quotes in the response body, so the unescaping step (`s/\\"/"/g`) handles this correctly. If Exa ever returns malformed JSON, the extraction will produce incorrect output — acceptable for this use case.

### 3. .env Loading Pattern

Load `.env` relative to the script's own location, not `$PWD`. This makes the script callable from any working directory:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
fi

if [ -z "${EXA_API_KEY:-}" ]; then
    echo "ERROR: EXA_API_KEY not set. Create .claude/skills/external-tool/.env with EXA_API_KEY=your_key" >&2
    exit 1
fi
```

**Why `. "$ENV_FILE"` (dot-source) over `set -a; source; set +a`:**
- `set -a; . "$ENV_FILE"; set +a` auto-exports all variables set during source — useful when forking subprocesses, unnecessary here since curl reads the variable from the same shell process
- The simple `. "$ENV_FILE"` pattern is Bash 3.2 compatible (no `source` keyword, which is a Bash 4+ alias of `.`)
- `set -euo pipefail` at the top achieves the same fail-fast behavior more cleanly
- The `${EXA_API_KEY:-}` form (empty default) prevents `set -u` from triggering an unbound variable error before the missing-key check

**SCRIPT_DIR resolution:**
- `$(cd "$(dirname "$0")" && pwd)` — the canonical Bash 3.2-compatible path resolution; resolves symlinks in the directory component
- Required because `exa.sh` is called via `bash .claude/skills/external-tool/scripts/exa.sh` — `$0` will be the path passed by the subagent, and `dirname` strips the filename to get the directory

### 4. SKILL.md Frontmatter Schema

Verified against three real installed skill files (`ui-ux-pro-max`, `qmd`, `exa code-search`). The fields Claude Code recognizes:

```yaml
---
name: web-search-exa
description: "Natural language description of when to activate this skill. Used by subagent to decide whether to invoke. Should name the tool, list concrete trigger scenarios, and include key phrases a user would say."
context: fork
allowed-tools: Bash(scripts/exa.sh:*)
---
```

**Field specifications:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `name` | string | Yes | Identifier for the skill; used in logs and tool references; kebab-case convention |
| `description` | string | Yes | The activation trigger — write as a rich natural language description, not a one-liner; the subagent pattern-matches this against user intent |
| `context` | enum | Recommended | `fork` spawns a Task subagent; prevents Exa's large text responses from consuming main context window; verified pattern in all exa-mcp-server skills |
| `allowed-tools` | string | Recommended | Glob restricting which tools are permitted inside the skill context; `Bash(scripts/exa.sh:*)` limits execution to only the skill script |

**Fields observed in some skills but not required:**
- `license` — metadata only (seen in `qmd` SKILL.md)
- `compatibility` — informational note for humans (seen in `qmd` SKILL.md)
- `metadata.author`, `metadata.version` — plugin registry fields, not needed for a local skill

**`context: fork` is critical for this skill.** Exa responses range from 2,000 to 20,000+ characters. Without `context: fork`, the full API response is injected into the main conversation context. The exa-mcp-server skills label this "Token Isolation (Critical)" and enforce it in every skill definition.

---

## Installation

No package installation required. The entire stack ships with macOS and Linux:

```bash
# Verify prerequisites are available
bash --version          # Must be 3.2+ (macOS default satisfies this)
curl --version          # Must support HTTPS
sed --version           # Any POSIX sed
shellcheck --version    # Optional: install via brew install shellcheck

# Verify API key works
EXA_API_KEY="your_key" curl --silent --show-error -X POST \
  -H "content-type: application/json" \
  -H "x-api-key: $EXA_API_KEY" \
  -d '{"query":"test","tokensNum":500}' \
  https://api.exa.ai/context
```

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| sed single-field extraction | jq `.context` | `jq` is not installed by default on macOS; adding it as a dependency contradicts the zero-dependency goal and would break the skill on any machine without Homebrew |
| sed single-field extraction | Python `json.loads` | Python 3 not guaranteed at `/usr/bin/python3` on all macOS versions; adds interpreter dependency; overkill for extracting one string field |
| sed single-field extraction | Node.js `JSON.parse` | Node not installed system-wide; PROJECT.md explicitly excludes Node; defeats portability purpose |
| `. "$ENV_FILE"` (dot-source) | Manually export each variable | Dot-source is one line; manual export requires knowing all variable names in advance; breaks when new keys are added to `.env` |
| `set -euo pipefail` + explicit key check | No error handling | Silent failures make debugging impossible for subagents; subagents check exit codes |
| Single `exa.sh` with subcommand dispatch | Separate `web-search.sh` and `code-context.sh` | Two files = duplicated env loading, duplicated error handling, harder to document in SKILL.md; one file is the right abstraction for a two-command tool |
| curl `--max-time 30` | No timeout flag | Without timeout, a hung API call blocks the subagent indefinitely; 30s matches the Node reference implementation's timeout |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `jq` | Not installed by default on macOS; breaks portability to any machine without Homebrew; the two Exa response shapes are simple enough that `sed` extracts them in one line | `sed 's/.*"context":"\(.*\)".*/\1/'` |
| `python3` / `python` | Python 3 path varies by macOS version; Python 2 (`/usr/bin/python`) is removed on macOS 12.3+; adds a runtime dependency that cannot be guaranteed | `sed` + `tr` |
| `node` | Not system-installed; PROJECT.md explicitly out of scope; violates the "zero dependency" design goal | `curl` + `sed` |
| Associative arrays (`declare -A`) | Bash 4+ only; macOS `/bin/bash` is Bash 3.2; using `declare -A` silently produces wrong behavior on macOS | Simple variable assignment; `case` dispatch for multi-branch logic |
| `source` keyword | Bash 4+ alias; use `.` (dot) for Bash 3.2 compatibility | `. "$ENV_FILE"` |
| `echo -e` for unescaping | Behavior differs between Bash built-in echo and `/bin/echo` on macOS; `-e` is not POSIX | `printf '%s'` + `sed` substitution for escape sequences |
| Hardcoded API key in script | Script is in version control; key leaks on first commit | Load from `.env` via dot-source; `.env` is gitignored |
| `set -e` alone (without `set -u` and `set -o pipefail`) | `set -e` does not catch unbound variables or errors in pipelines; partial error handling creates silent failure modes | `set -euo pipefail` as the first executable line |

---

## Stack Patterns by Variant

**If the subcommand takes optional flags (v1.x):**
- Add flag parsing after the subcommand check using a `while` loop + `case "$1"` + `shift`
- Do NOT use `getopts` — it does not handle long options (`--num-results`) and the syntax is unfamiliar to readers
- Keep flag parsing inside the relevant subcommand branch, not at global scope

**If the response field contains a JSON array instead of a string:**
- Use the `sed 's/},{/|@@|/g'` delimiter split pattern documented in project MEMORY.md
- Then loop with `IFS='|@@|'` to iterate result objects
- This pattern is NOT needed for v1 (both endpoints return a single top-level string)

**If running on Linux (not macOS):**
- The stack is identical; `/bin/bash` on Ubuntu/Debian is Bash 5.x, which is a superset of 3.2
- All `sed`, `tr`, `curl` patterns are POSIX-compatible and run unchanged

---

## Version Compatibility

| Component | Minimum Version | Notes |
|-----------|----------------|-------|
| Bash | 3.2 | macOS default since OS X 10.3 (2003); do not use features added in 4.0+ (associative arrays, `mapfile`, `source` keyword) |
| curl | 7.x | Any modern curl supports `--silent`, `--show-error`, `--max-time`, `-X`, `-H`, `-d`; TLS 1.2+ required for `api.exa.ai` |
| sed | POSIX | Avoid GNU-only extensions (e.g., `\w`, `\+` in character classes); use `[a-zA-Z0-9_]` and `\{1,\}` for compatibility |
| SKILL.md | Claude Code ≥ 1.x | Frontmatter `context: fork` and `allowed-tools` verified against installed skills; schema has been stable across observed versions |

---

## Sources

- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/config.ts` — confirmed API base URL (`https://api.exa.ai`), endpoints (`/search`, `/context`), defaults (8 results, 2000 chars) — HIGH confidence
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/webSearch.ts` — confirmed auth header name (`x-api-key`), request shape, `.context` response field, 25s timeout — HIGH confidence
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/src/tools/exaCode.ts` — confirmed `.response` field, `tokensNum` param (1000–50000), 30s timeout — HIGH confidence
- `/Users/ntuvu/Desktop/workspace/projects/exa-mcp-server/skills/code-search/SKILL.md` — confirmed SKILL.md frontmatter schema (`name`, `description`, `context: fork`), body sections — HIGH confidence
- `/Users/ntuvu/.claude/plugins/cache/qmd/qmd/0.1.0/skills/qmd/SKILL.md` — confirmed `allowed-tools` field syntax (`Bash(qmd:*)`) — HIGH confidence
- `/Users/ntuvu/.claude/plugins/cache/ui-ux-pro-max-skill/ui-ux-pro-max/2.0.1/.claude/skills/ui-ux-pro-max/SKILL.md` — confirmed minimal frontmatter (name + description only, no `context`/`allowed-tools`) is valid — HIGH confidence
- Project `MEMORY.md` — confirmed `sed 's/},{/|@@|/g'` array parsing pattern, escape sequence handling approach — HIGH confidence

---

*Stack research for: Claude Code external-tool skill (Exa web-search + code-context)*
*Researched: 2026-03-09*
