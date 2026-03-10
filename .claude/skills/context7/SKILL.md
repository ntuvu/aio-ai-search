---
name: context7
description: Look up library documentation and code examples using Context7. Use `resolve` to find a library ID, then `query` to get documentation. Examples: "how to use React server components", "Next.js app router documentation".
context: fork
agent: use-tool
---

Look up library documentation using the local Context7 script. Run:

```
bash $SKILL_DIR/scripts/context7.sh <command> "$ARGUMENTS"
```

## Commands

### `resolve` — Find a library ID

```
bash $SKILL_DIR/scripts/context7.sh resolve <library_name> [options]
```

| Option | Description |
|--------|-------------|
| `<library_name>` | Name of the library (e.g., "react", "next.js", "express") |
| `--query <text>` | Original user question for relevance ranking (optional but recommended) |

Returns up to 5 matching libraries with ID, title, description, snippet count, trust score.

**Selection criteria**: Pick the library with the highest trust score and most relevant description.

### `query` — Query library documentation

```
bash $SKILL_DIR/scripts/context7.sh query --library-id <id> --query <query>
```

| Option | Description |
|--------|-------------|
| `--library-id <id>` | Context7 library ID from `resolve` (e.g., "/reactjs/react.dev") |
| `--query <query>` | Specific question — be detailed for better results |

## Examples

```bash
# Step 1: Find the library ID
bash $SKILL_DIR/scripts/context7.sh resolve "next.js" --query "How to use server components in Next.js"

# Step 2: Query documentation with the library ID
bash $SKILL_DIR/scripts/context7.sh query --library-id "/vercel/next.js" --query "How to set up server components"
```

## Notes

- Write specific, detailed queries for better results
- Good: "How to set up authentication with JWT in Express.js"
- Bad: "auth" (too vague)
