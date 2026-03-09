# Pitfalls Research

**Domain:** Bash CLI external-tool skill (Exa REST API + Claude Code SKILL.md)
**Researched:** 2026-03-09
**Confidence:** HIGH — pitfalls derived from known Bash 3.2 constraints, curl behavior, and Claude Code skill spec requirements

## Critical Pitfalls

### Pitfall 1: Bash 3.2 Array Syntax Breaks on macOS Default Shell

**What goes wrong:**
Scripts use associative arrays (`declare -A`) or array features introduced in Bash 4+. On macOS, `/bin/bash` is Bash 3.2. The script silently fails or exits with a syntax error when installed via the default shell.

**Why it happens:**
Developers test on Linux (Bash 5.x) or with a Homebrew Bash that is Bash 5.x. The script works in development but breaks for any user whose `#!/bin/bash` resolves to `/bin/bash` on macOS.

**How to avoid:**
- Never use `declare -A` (associative arrays)
- Never use `${array[@]::N}` slice syntax (Bash 4+)
- Never use `mapfile` or `readarray`
- Use only indexed arrays with `arr[0]=val` syntax for simple cases
- Prefer positional variables or delimited strings over arrays when possible
- Run `shellcheck --shell=bash` and check that shellcheck targets `bash` not `bash5`

**Warning signs:**
- `declare -A` anywhere in the file
- `mapfile` or `readarray` calls
- `${!array[@]}` usage (associative array key iteration)
- Testing only on Linux CI without a macOS Bash 3.2 check

**Phase to address:**
Phase 1 (scaffold) — establish shebang line and test harness against Bash 3.2 from the start

---

### Pitfall 2: `read -r` Missing Causes Backslash Mangling in API Responses

**What goes wrong:**
`read` without `-r` interprets backslash sequences in the input. JSON responses from the Exa API contain `\"`, `\\`, `\n` as literal characters. Without `-r`, the shell processes these escapes and corrupts the captured string before your `sed` pipeline ever runs.

**Why it happens:**
`read` without `-r` is the POSIX default. Developers write `read line` or `while read line` in loops and do not notice the corruption because small responses look fine, but longer responses with escape sequences silently mangle data.

**How to avoid:**
Always use `read -r` in every `while read` loop:
```bash
while IFS= read -r line; do
  ...
done <<< "$response"
```
`IFS=` prevents leading/trailing whitespace stripping in addition to `-r` preventing backslash interpretation.

**Warning signs:**
- Any `while read line` without `-r`
- Any `read line` without `-r` when consuming curl output
- API response text appears truncated at a backslash

**Phase to address:**
Phase 1 (scaffold) and Phase 2 (JSON parsing) — enforce in code review checklist

---

### Pitfall 3: `sed` Regex Extracts Wrong Field When `.context` or `.response` Contains Nested JSON

**What goes wrong:**
A greedy `sed` regex like `s/.*"context":"\(.*\)".*/\1/` will match from the first `"context":"` to the LAST `"` in the entire response, not the closing quote of the `context` field. If the `.context` value itself contains quoted substrings, the extracted value is truncated or extended incorrectly.

**Why it happens:**
BRE (basic regular expression) `.*` is greedy and spans the entire line. JSON values from Exa are often multi-sentence text with embedded punctuation. The response is typically one long line from curl, making greedy matching especially dangerous.

**How to avoid:**
Use a non-greedy approach by matching everything except a double-quote for the value boundary:
```bash
# Extract .context value (stops at first unescaped quote)
context=$(printf '%s' "$response" | sed 's/.*"context":"\([^"]*\)".*/\1/')
```
For values that may contain escaped quotes (`\"`), split on the field delimiter first using `tr` or multi-step `sed` before extracting:
```bash
# Step 1: isolate after the key
after=$(printf '%s' "$response" | sed 's/.*"context":"//')
# Step 2: cut at first unescaped closing quote
value=$(printf '%s' "$after" | sed 's/\\"/ESCAPED_QUOTE/g' | sed 's/"\(.*\)$//' | sed 's/ESCAPED_QUOTE/\\"/g')
```
Document which endpoint returns which field: `POST /search` returns `.results[].text`, `POST /context` returns `.response`.

**Warning signs:**
- Extracted value is unexpectedly empty
- Extracted value ends with trailing JSON fragments like `,"id":`
- Value cuts off mid-sentence when the text contains a quote character

**Phase to address:**
Phase 2 (JSON parsing module) — write unit tests with fixture responses that include quoted substrings

---

### Pitfall 4: `.env` Loading Strips Quotes or Fails on Export

**What goes wrong:**
Sourcing `.env` with `source .env` or `. .env` interprets the file as shell code. If the `.env` file contains `EXA_API_KEY="abc123"`, the value stored in the variable includes the literal quote characters on some shells or is correct on others — behavior depends on whether the assignment is bare or quoted. If the file contains `export EXA_API_KEY=abc123` without quotes and the key contains special characters, the export silently assigns a truncated value.

A second failure mode: the path resolution for `.env` uses a relative path. When the script is invoked from a different working directory (e.g., `ais exa web-search "query"` run from `/tmp`), the relative `.env` path resolves to the wrong location and the key is never loaded.

**Why it happens:**
`.env` loading is usually written as `source ./.env` which resolves relative to `$PWD`, not relative to the script file. External-tool invocation by Claude Code may set a different working directory.

**How to avoid:**
- Resolve the `.env` path relative to the script's own directory using `$SCRIPT_DIR`:
```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
```
- Write `.env` values without surrounding quotes in the file itself: `EXA_API_KEY=abc123`
- If quotes are needed (value contains spaces), document the expected format explicitly
- Validate the key is non-empty immediately after loading:
```bash
[ -z "$EXA_API_KEY" ] && { echo "ERROR: EXA_API_KEY not set" >&2; exit 1; }
```

**Warning signs:**
- Script works when run from its own directory but fails when run from another directory
- `echo "$EXA_API_KEY"` shows value wrapped in extra quotes like `"abc123"`
- API returns 401 despite key appearing correct

**Phase to address:**
Phase 1 (scaffold) — establish `.env` loading pattern before any API calls are written

---

### Pitfall 5: SKILL.md Missing `context: fork` in Frontmatter Causes Wrong Subagent Behavior

**What goes wrong:**
A SKILL.md without `context: fork` in its YAML frontmatter will cause Claude Code to invoke the skill in the current agent context rather than spawning a new subagent. This means the skill's tool calls share the parent agent's context window and tool permissions, which can pollute state and bypass the isolation the skill is designed to provide.

**Why it happens:**
`context: fork` is not a default — it must be explicit. Developers copy a minimal SKILL.md template that omits frontmatter entirely, or copy one that uses `context: shared`, which is a different behavior.

**How to avoid:**
Every SKILL.md must begin with:
```yaml
---
context: fork
allowed-tools:
  - Bash
---
```
The `allowed-tools` list must match exactly the tools the skill script needs. If the script only uses `Bash`, list only `Bash`. Listing extra tools does not cause failures but signals imprecise skill authoring.

**Warning signs:**
- Skill invocation does not appear as a separate subagent in Claude Code logs
- Skill tool calls appear in the parent agent's tool use stream
- Parent agent context window grows during skill execution

**Phase to address:**
Phase 3 (SKILL.md authoring) — validate frontmatter with a SKILL.md linter or manual review checklist before integration testing

---

### Pitfall 6: `allowed-tools` Path in SKILL.md Uses Wrong Bash Invocation Format

**What goes wrong:**
SKILL.md `allowed-tools` entries that reference `Bash` tool calls must match how Claude Code names them. If the frontmatter uses `bash` (lowercase) or `shell` instead of `Bash`, the skill may fail to execute or may silently fall back to no tool restriction. Additionally, if the skill requires file reads (e.g., checking `.env` exists), omitting `Read` from `allowed-tools` causes the subagent to error.

**Why it happens:**
The `allowed-tools` values are case-sensitive and must match Claude Code's internal tool names exactly. There is no validation error at load time — the failure surfaces only at invocation.

**How to avoid:**
- Use exact tool names: `Bash`, `Read`, `Write`, `Glob`, `Grep` (capitalized)
- For an `exa.sh` external tool that only shells out via curl, `allowed-tools: [Bash]` is sufficient
- Test by invoking the skill and confirming the subagent can execute its commands

**Warning signs:**
- Subagent spawns but immediately errors on its first tool call
- "tool not allowed" or "unknown tool" error in subagent output
- Skill works in parent context but fails when `context: fork` is active

**Phase to address:**
Phase 3 (SKILL.md authoring) — include an invocation smoke test as part of phase acceptance criteria

---

### Pitfall 7: curl Non-2xx Response Treated as Success

**What goes wrong:**
By default, curl exits with code 0 even when the HTTP response is 401, 429, or 500. The script continues as if the request succeeded, passes the error JSON body to the `sed` parser, and produces garbled or empty output. The user sees no actionable error message.

**Why it happens:**
curl's exit code reflects transport success (connection established, data transferred), not HTTP success. Most scripts check `$?` after curl and assume 0 means the API call worked.

**How to avoid:**
Use `--fail` or `--fail-with-body` to make curl exit non-zero on HTTP errors:
```bash
response=$(curl --fail-with-body --silent --show-error \
  -X POST "$url" \
  -H "Authorization: Bearer $EXA_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$payload" 2>&1)
exit_code=$?
if [ $exit_code -ne 0 ]; then
  printf 'ERROR: API request failed (exit %d)\n%s\n' "$exit_code" "$response" >&2
  exit 1
fi
```
Note: `--fail-with-body` was added in curl 7.76.0 (2021). For older curl, use `--fail` (body is suppressed on error) or capture HTTP status code separately with `-w "%{http_code}"`.

**Warning signs:**
- Script outputs empty string or `null` for failed API requests
- No error shown when API key is invalid
- Script exits 0 after a network timeout

**Phase to address:**
Phase 2 (API integration) — define error handling wrapper before implementing individual endpoint calls

---

### Pitfall 8: API Key Committed to Git via Hardcoded Value or Unignored `.env`

**What goes wrong:**
The `EXA_API_KEY` value appears directly in `exa.sh`, or the `.env` file at `.claude/skills/external-tool/.env` is committed because `.gitignore` only covers the repo root `.env` and not nested `.env` files.

**Why it happens:**
`.gitignore` entries like `*.env` or `.env` at the root do not automatically ignore `.env` files in subdirectories unless the pattern is `**/.env` or the `.gitignore` entry is placed in the subdirectory itself. Developers assume root gitignore covers all subdirectory matches.

**How to avoid:**
Add to the root `.gitignore`:
```
**/.env
.env
```
Or add a `.gitignore` file inside `.claude/skills/external-tool/` containing just `.env`.
Never hardcode the key in `exa.sh` — always load from the `.env` file.
Add a pre-commit check or CI lint step that scans for `EXA_API_KEY=` followed by a non-empty value in tracked files.

**Warning signs:**
- `git status` shows `.env` as a tracked or staged file
- `git log --all --full-history -- "**/.env"` returns results
- The key appears in `git diff` output

**Phase to address:**
Phase 1 (scaffold) — add `.gitignore` entries before any `.env` file is created

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Inline all JSON parsing in the endpoint function | Faster to write first version | Duplicated logic, impossible to unit test parsing separately | MVP only — extract to `json.sh` module before adding a second endpoint |
| Single `sed` one-liner to extract any field | Concise code | Breaks on nested values, hard to debug | Never — use multi-step extraction with intermediate variables |
| Skip curl `--fail` flag | Simpler error path | Silent failures on 4xx/5xx; users see garbled output | Never |
| Hardcode `.env` path as relative `./. env` | Faster to write | Breaks when script is called from different `$PWD` | Never — always derive path from `$SCRIPT_DIR` |
| Omit `context: fork` in SKILL.md | Works in simple tests | Skill contaminates parent agent context | Never for production skills |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Exa `/search` endpoint | Assume response field is `.context` (like `/context` endpoint) | `/search` returns `.results[]` array with `.text` per result; `/context` returns top-level `.response` string |
| Exa `/context` endpoint | Attempt to iterate results array | Response is a single `.response` string, not an array |
| curl + API key | Pass key as query parameter | Always pass as `Authorization: Bearer $EXA_API_KEY` header |
| curl JSON body | Interpolate variables directly into `-d '{...}'` | Shell quoting inside single-quoted strings does not expand variables; use a variable: `payload="{\"query\":\"$q\"}"` then `-d "$payload"` |
| `.env` sourcing | `source .env` from relative path | Resolve via `$SCRIPT_DIR` before sourcing |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| No curl timeout | Script hangs indefinitely on slow network | Add `--max-time 30 --connect-timeout 10` to every curl call | Immediately on any network hiccup |
| Large response piped through multiple `sed` calls in a loop | Slow for large result sets | Keep `sed` chains outside loops; process full response at once | At responses > ~50KB |
| Spawning a subshell per result item in a while loop | Works fine for 5 results | Each `$(...)` fork is expensive; restructure to process all results in one pass | At 20+ results |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| API key in script source | Key exposed in version history, readable by any process that can read the file | Load exclusively from `.env`; add `.env` to `.gitignore` |
| `.env` world-readable permissions | Any local user can read the key | `chmod 600 .claude/skills/external-tool/.env` after creation |
| User query interpolated unsanitized into JSON payload | If query contains `"`, it breaks JSON structure and could inject unexpected fields | Escape double quotes in user input before interpolation: `query=$(printf '%s' "$1" | sed 's/"/\\"/g')` |
| Error messages echoing full API response to stdout | Response may contain sensitive data or expose system details | Send error details to `stderr` only; stdout reserved for clean output |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No output on success (silent curl) | User cannot tell if command worked | Always print at least one result line or a "no results" message |
| Raw JSON dumped to terminal on error | Confusing wall of text | Parse error response for `.error` or `.message` field; print human-readable line |
| Missing usage help when called with no arguments | User must read source to understand how to invoke | Add a `usage()` function called when `$#` is 0 or on `-h`/`--help` |
| Progress indication absent for slow queries | Appears hung for >2s queries | Print `Searching...` to stderr before curl call; clear after |

---

## "Looks Done But Isn't" Checklist

- [ ] **`.env` loading:** Verify script works when invoked from a different directory than where it lives — test with `cd /tmp && ais exa web-search "test"`
- [ ] **Error handling:** Verify a bad API key produces a non-zero exit code and a readable error message — test with `EXA_API_KEY=bad ais exa web-search "test"`
- [ ] **SKILL.md frontmatter:** Verify `context: fork` is present and `allowed-tools` lists only `Bash` — do not assume defaults
- [ ] **JSON parsing:** Verify extraction works when the `.response` value contains a double-quote character — test with a fixture containing `\"` in the value
- [ ] **Bash 3.2 compat:** Verify script passes `shellcheck --shell=bash` with no warnings — check macOS `/bin/bash --version` if available
- [ ] **`.gitignore`:** Verify `git status` does not show `.env` as untracked or staged — run before first commit
- [ ] **curl timeout:** Verify `--max-time` and `--connect-timeout` flags are present on every curl invocation
- [ ] **`/search` vs `/context` field names:** Verify the correct field is extracted for each endpoint — `.results[].text` for search, `.response` for context

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| API key committed to git | HIGH | Rotate key immediately with Exa; use `git filter-branch` or BFG Repo Cleaner to purge from history; audit all forks/clones |
| Wrong field name in parser (`.context` vs `.response`) | LOW | Fix the `sed` extraction line; add fixture test to prevent regression |
| Bash 4+ syntax introduced | LOW | Rewrite the specific construct; validate with `bash --version` on macOS |
| SKILL.md missing `context: fork` | LOW | Add frontmatter; re-test invocation |
| Relative `.env` path breaks invocation | LOW | Replace with `$SCRIPT_DIR`-relative path; retest from multiple directories |
| No curl error handling causes silent failures | MEDIUM | Wrap all curl calls in error-checking function; add `--fail-with-body`; retest all code paths |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Bash 3.2 incompatible syntax | Phase 1 (scaffold) | `shellcheck --shell=bash` passes; test on macOS `/bin/bash` |
| `read` without `-r` | Phase 1 (scaffold) | `shellcheck` flags missing `-r`; code review |
| Greedy `sed` extraction | Phase 2 (JSON parsing) | Fixture test with embedded quotes in value |
| `.env` relative path | Phase 1 (scaffold) | Invocation test from `/tmp` |
| API key in git | Phase 1 (scaffold) | `git status` check before first commit; `.gitignore` audit |
| Missing `context: fork` | Phase 3 (SKILL.md) | Inspect frontmatter; subagent isolation smoke test |
| Wrong `allowed-tools` capitalization | Phase 3 (SKILL.md) | Invoke skill and confirm no "tool not allowed" error |
| curl non-2xx not caught | Phase 2 (API integration) | Test with invalid key; verify non-zero exit and error message |
| curl no timeout | Phase 2 (API integration) | Verify `--max-time` present in curl call; code review |
| Wrong field name per endpoint | Phase 2 (API integration) | Fixture tests for both `/search` and `/context` responses |

---

## Sources

- Bash 3.2 release notes and changelog (macOS default shell constraint): https://www.gnu.org/software/bash/manual/
- shellcheck documentation on `read -r` requirement: https://www.shellcheck.net/wiki/SC2162
- curl `--fail-with-body` availability (curl 7.76.0, April 2021): https://curl.se/docs/manpage.html
- Claude Code skills and SKILL.md frontmatter specification: Claude Code official documentation
- Exa API reference for `/search` and `/context` endpoints: https://docs.exa.ai/reference/

---
*Pitfalls research for: Bash external-tool skill (exa.sh + SKILL.md for Claude Code)*
*Researched: 2026-03-09*
