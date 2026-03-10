---
name: github
description: Search GitHub source code using the gh CLI. Use `code-search` to find real code examples, implementations, and patterns on GitHub.
context: fork
agent: use-tool
---

Search GitHub source code using the local `gh` CLI. This skill runs with the use-tool agent.

## Commands

### 1. `code-search` — Search GitHub

```
bash $SKILL_DIR/scripts/github.sh code-search <query> [options]
```

**Query strategy (IMPORTANT):**
- Use **one key identifier** as the main query (class name, function, constant)
- Put `language:python` (or other lang) **inside the query string**, do NOT use a `--language` flag
- Special characters `@`, `{`, `}`, `#`, `!` are **auto-stripped** before sending to GitHub
- If 0 results → retry with a shorter query

**Example:**
```bash
bash $SKILL_DIR/scripts/github.sh code-search "MonthlyPartitionsDefinition language:python"
bash $SKILL_DIR/scripts/github.sh code-search "partitions_def MonthlyPartitionsDefinition language:python"
```

**Output per result:**
```
--- Result N ---
Repo: owner/repo
File: path/to/file.py
URL:  https://github.com/...
Raw:  https://raw.githubusercontent.com/...   ← use to fetch full file
Code:
<snippet>
```

**Options:**
| Option | Description |
|--------|-------------|
| `--limit <n>` | Number of results (default: 10) |
| `--owner <org>` | Filter by org |
| `--repo <owner/repo>` | Filter by specific repo |
| `--filename <name>` | Filter by file name |

---

### 2. `fetch-file` — Get full file content

```
bash $SKILL_DIR/scripts/github.sh fetch-file <owner/repo> <path/to/file>
```

**Example:**
```bash
bash $SKILL_DIR/scripts/github.sh fetch-file dagster-io/dagster examples/assets/assets.py
```

**When using a subagent to fetch a file, request this output format:**
```
=== FILE: <owner/repo> / <path> ===
<file content>

=== SUMMARY ===
- <highlight 1: main pattern, API usage>
- <highlight 2: anything notable or unusual>
- <highlight 3: ...>
```

---

## Typical workflow

Run `code-search` to find files, then `fetch-file` for full content.

## Auth

Uses system `gh` auth (no API key needed). Run `gh auth status` to verify.
