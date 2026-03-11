---
name: grepapp
description: >-
  Find real-world code examples from over a million public GitHub repositories to help answer programming questions.
  IMPORTANT: searches for literal code patterns (like grep), not keywords — use actual code that would appear in files.
  Use `search` with --use-regexp for flexible regex patterns (prefix with (?s) for multiline).
  Filter by --lang, --repo, or --path to narrow results. No API key required.
context: fork
agent: use-tool
---

Find real-world code patterns across 1M+ public GitHub repositories using the local grepapp script. Run:

```
bash $SKILL_DIR/scripts/grepapp.sh search <query> [options]
```

> **Important**: grep.app searches for *literal code* (like grep), not keywords. Use actual code snippets, function names, or patterns you'd find in source files — not natural language descriptions.

## Command

### `search` — Search GitHub repositories for code patterns

```
bash $SKILL_DIR/scripts/grepapp.sh search <query> [options]
```

| Option | Description |
|--------|-------------|
| `<query>` | Code pattern to search (literal string by default, or regex with `--use-regexp`) |
| `--match-case` | Case-sensitive matching (default: case-insensitive) |
| `--match-whole-words` | Match whole words only |
| `--use-regexp` | Treat query as a regular expression; prefix with `(?s)` for multiline patterns |
| `--repo <owner/name>` | Filter by repository; supports partial match (e.g. `facebook/react` or `vercel/`) |
| `--path <pattern>` | Filter by file path; supports partial match (e.g. `src/components` or `/route.ts`) |
| `--lang <language>` | Filter by language; **repeatable** for multiple languages |
| `--num-results <n>` | Number of results to return (default: 10) |
| `--page <n>` | Page number for pagination (default: 1) |

## Examples

```bash
# Find how getStaticProps is used in Next.js itself
bash $SKILL_DIR/scripts/grepapp.sh search "getStaticProps" --repo vercel/next.js

# Search for useState in TypeScript and TSX files
bash $SKILL_DIR/scripts/grepapp.sh search "useState" --lang TypeScript --lang TSX --num-results 5

# Regex: find Python test functions
bash $SKILL_DIR/scripts/grepapp.sh search "def test_\w+" --use-regexp --lang Python --num-results 5

# Find files using a specific import pattern
bash $SKILL_DIR/scripts/grepapp.sh search "from 'react-query'" --lang TypeScript

# Multiline regex: find async functions with specific body pattern
bash $SKILL_DIR/scripts/grepapp.sh search "(?s)async function.*await fetch" --use-regexp --lang JavaScript

# Filter by file path
bash $SKILL_DIR/scripts/grepapp.sh search "createSlice" --path "store/" --lang TypeScript
```

## Output Format

```
=== grep.app: <query> (<total> total matches) ===

[1] owner/repo  (branch)
    path/to/file.ext  [N matches]
    |  matching line of code
    |  another matching line
    URL: https://github.com/owner/repo/blob/branch/path/to/file.ext
```

## Notes

- No API key required — grep.app is a public service
- For best results, use actual code syntax rather than prose descriptions
  - Good: `"export default function"` or `"useEffect(() => {"`
  - Bad: `"react component that uses effects"` (too vague, non-code)
- Combine `--lang` with `--repo` or `--path` for highly targeted searches
- Use `--page` to paginate through large result sets
