#!/usr/bin/env bash
# web_search_exa — Search the web using Exa AI
# Usage: web_search_exa <query> [options]
# Options:
#   --num-results <n>           Number of results (default: 8)
#   --livecrawl <fallback|preferred>  Live crawl mode (default: fallback)
#   --type <auto|fast>          Search type (default: auto)
#   --category <company|research paper|people>  Filter by category
#   --max-chars <n>             Max characters for context (default: 10000)

set -euo pipefail

# Load .env from repo root (resolve script location to find repo root)
_script_dir="$(cd "$(dirname "$0")" && pwd)"
_env_file="$_script_dir/../.env"
[ -f "$_env_file" ] && . "$_env_file"

EXA_API_KEY="${EXA_API_KEY:-}"
API_URL="https://api.exa.ai/search"

usage() {
  sed -n '2,9p' "$0" | sed 's/^# //'
  exit 1
}

die() { echo "error: $*" >&2; exit 1; }

[ -z "$EXA_API_KEY" ] && die "EXA_API_KEY is not set"
[ $# -eq 0 ] && usage

# Parse arguments
query=""
num_results=8
livecrawl="fallback"
type="auto"
category=""
max_chars=10000

while [ $# -gt 0 ]; do
  case "$1" in
    --num-results)   num_results="$2"; shift 2 ;;
    --livecrawl)     livecrawl="$2";   shift 2 ;;
    --type)          type="$2";        shift 2 ;;
    --category)      category="$2";    shift 2 ;;
    --max-chars)     max_chars="$2";   shift 2 ;;
    --help|-h)       usage ;;
    -*)              die "unknown option: $1" ;;
    *)
      if [ -z "$query" ]; then
        query="$1"
      else
        query="$query $1"
      fi
      shift
      ;;
  esac
done

[ -z "$query" ] && die "query is required"

# Escape query for JSON (basic: backslash, double-quote, newline, tab)
json_query=$(printf '%s' "$query" \
  | sed 's/\\/\\\\/g' \
  | sed 's/"/\\"/g' \
  | tr '\n' ' ' \
  | tr '\t' ' ')

# Build category field
category_field=""
if [ -n "$category" ]; then
  category_field='"category": "'"$category"'",'
fi

# Build request body
body='{
  "query": "'"$json_query"'",
  "type": "'"$type"'",
  "numResults": '"$num_results"',
  '"$category_field"'
  "contents": {
    "text": true,
    "context": {
      "maxCharacters": '"$max_chars"'
    },
    "livecrawl": "'"$livecrawl"'"
  }
}'

# Make request
response=$(curl -sf \
  -X POST "$API_URL" \
  -H "accept: application/json" \
  -H "content-type: application/json" \
  -H "x-api-key: $EXA_API_KEY" \
  -H "x-exa-integration: web-search-bash" \
  --max-time 25 \
  -d "$body") || die "request to Exa API failed"

# Extract context field (between first "context":" and the closing quote before "requestId")
context=$(printf '%s' "$response" \
  | sed 's/.*"context":"//' \
  | sed 's/","requestId".*//' \
  | sed 's/","autopromptString".*//' \
  | sed 's/\\n/\n/g' \
  | sed 's/\\t/\t/g' \
  | sed 's/\\"/"/g' \
  | sed 's/\\\\/\\/g')

if [ -z "$context" ]; then
  echo "No search results found. Please try a different query." >&2
  exit 1
fi

printf '%s\n' "$context"
