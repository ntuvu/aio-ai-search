---
name: exa
description: >-
  Search the web, find code examples, or extract content from a URL using Exa AI.
  Use `web-search` to find current information, news, facts, or answers about any topic — returns clean text from top results.
  Use `code-context` for any programming question (API usage, library examples, code snippets, debugging) — searches GitHub, Stack Overflow, and official docs.
  Use `crawl` when you have an exact URL and need its full text content and metadata.
context: fork
agent: use-tool
---

Search the web or find code context using the local Exa script. Run:

```
bash $SKILL_DIR/scripts/exa.sh <command> "$ARGUMENTS"
```

## Commands

### `web-search` — Search the web

```
bash $SKILL_DIR/scripts/exa.sh web-search <query> [options]
```

| Option | Description |
|--------|-------------|
| `<query>` | Websearch query |
| `--num-results <n>` | Number of search results to return (must be a number, default: 8) |
| `--livecrawl <mode>` | `fallback`: use live crawling as backup if cached content unavailable, `preferred`: prioritize live crawling (default: `fallback`) |
| `--type <type>` | `auto`: balanced search (default), `fast`: quick results |
| `--category <cat>` | Filter results to a specific category — `company`: company websites and profiles, `research paper`: academic papers and research, `people`: LinkedIn profiles and personal bios |
| `--max-chars <n>` | Maximum characters for context string optimized for LLMs (must be a number, default: 10000) |

### `code-context` — Find code examples and documentation

```
bash $SKILL_DIR/scripts/exa.sh code-context <query> [options]
```

| Option | Description |
|--------|-------------|
| `<query>` | Search query to find relevant context for APIs, Libraries, and SDKs. For example, 'React useState hook examples', 'Python pandas dataframe filtering', 'Express.js middleware', 'Next js partial prerendering configuration' |
| `--tokens <n>` | Number of tokens to return (must be a number, 1000–50000). Default is 5000 tokens. Adjust based on how much context you need — use lower values for focused queries and higher values for comprehensive documentation. |

### `crawl` — Fetch full content from a URL

```
bash $SKILL_DIR/scripts/exa.sh crawl <url> [options]
```

| Option | Description |
|--------|-------------|
| `<url>` | URL to crawl and extract content from |
| `--max-chars <n>` | Maximum characters to extract (must be a number, default: 3000) |

## Examples

```bash
# Web search
bash $SKILL_DIR/scripts/exa.sh web-search "Next.js 15 release notes" --livecrawl preferred
bash $SKILL_DIR/scripts/exa.sh web-search "transformer attention mechanism" --category "research paper"

# Code context
bash $SKILL_DIR/scripts/exa.sh code-context "React useState hook examples"
bash $SKILL_DIR/scripts/exa.sh code-context "Python pandas dataframe filtering" --tokens 10000

# Crawl a specific URL
bash $SKILL_DIR/scripts/exa.sh crawl "https://docs.anthropic.com/en/api/getting-started" --max-chars 5000
```
