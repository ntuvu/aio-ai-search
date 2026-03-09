# aio-ai-search: External Tool Skill

## What This Is

A Claude Code skill package that wraps the Exa search API into a self-contained, agent-callable unit. Subagents in Claude Code sessions can invoke the skill to perform web searches or code context lookups without needing the Exa MCP server running. The skill lives entirely within `.claude/skills/external-tool/` and executes via a shell script.

## Core Value

Subagents can call `web_search_exa` and `get_code_context_exa` as a skill — clean search results returned without MCP server infrastructure.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Skill file (`SKILL.md`) describes how subagents invoke the two search tools
- [ ] Shell script (`scripts/exa.sh`) hits Exa API for `web_search_exa` and `get_code_context_exa`
- [ ] API key loaded from `.env` file inside the skill folder
- [ ] `.env.example` documents required keys for setup
- [ ] Script is callable: `bash .claude/skills/external-tool/scripts/exa.sh web-search "<query>"`
- [ ] Script is callable: `bash .claude/skills/external-tool/scripts/exa.sh code-context "<query>"`
- [ ] `.env` gitignored so API key is never committed

### Out of Scope

- Other Exa tools (company research, LinkedIn search, deep research, etc.) — scope to web + code for v1
- Node.js implementation — Bash keeps it dependency-free
- Integration with existing `ais exa` commands — skill is standalone, doesn't depend on the `ais` CLI

## Context

- Source reference: `~/Desktop/workspace/projects/exa-mcp-server/src/tools/webSearch.ts` (endpoint shape, params)
- Exa web search endpoint: `POST https://api.exa.ai/search` — returns `context` string (LLM-ready text)
- Exa code context endpoint: `POST https://api.exa.ai/context` — returns `response` string
- Existing `aio-ai-search` project already has `providers/exa.sh` — can reference for Bash patterns
- Existing project uses pure Bash + `sed`/`tr` for JSON parsing (no `jq`)
- SKILL.md pattern: skill files live in `.claude/skills/` and are invoked by subagents

## Constraints

- **Tech**: Bash only — no Node, no Python, no jq dependency
- **Compatibility**: Bash 3.2+ compatible (macOS default shell)
- **Auth**: API key from `.claude/skills/external-tool/.env`, never hardcoded

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Bash over Node/Python | Consistent with existing project, zero dependency install | — Pending |
| Self-contained folder | Skill + script + config co-located, easy to copy to any project | — Pending |
| `.env` inside skill folder | Keeps config local to the skill, not project-root level | — Pending |

---
*Last updated: 2026-03-09 after initialization*
