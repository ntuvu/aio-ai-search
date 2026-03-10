#!/usr/bin/env bash
# get_code_context_exa — Find code examples, documentation, and programming solutions
# Usage: get_code_context_exa <query> [options]
# Options:
#   --tokens <n>   Number of tokens to return (1000-50000, default: 5000)

set -euo pipefail

# Load .env from repo root (resolve script location to find repo root)
_script_dir="$(cd "$(dirname "$0")" && pwd)"
_env_file="$_script_dir/../.env"
[ -f "$_env_file" ] && . "$_env_file"

EXA_API_KEY="${EXA_API_KEY:-}"
API_URL="https://api.exa.ai/context"

usage() {
  sed -n '2,6p' "$0" | sed 's/^# //'
  exit 1
}

die() { echo "error: $*" >&2; exit 1; }

[ -z "$EXA_API_KEY" ] && die "EXA_API_KEY is not set"
[ $# -eq 0 ] && usage

# Parse arguments
query=""
tokens=5000

while [ $# -gt 0 ]; do
  case "$1" in
    --tokens)   tokens="$2"; shift 2 ;;
    --help|-h)  usage ;;
    -*)         die "unknown option: $1" ;;
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

# Validate tokens range
if [ "$tokens" -lt 1000 ] || [ "$tokens" -gt 50000 ]; then
  die "tokens must be between 1000 and 50000"
fi

# Escape query for JSON
json_query=$(printf '%s' "$query" \
  | sed 's/\\/\\\\/g' \
  | sed 's/"/\\"/g' \
  | tr '\n' ' ' \
  | tr '\t' ' ')

# Build request body
body='{
  "query": "'"$json_query"'",
  "tokensNum": '"$tokens"'
}'

# Make request
response=$(curl -sf \
  -X POST "$API_URL" \
  -H "accept: application/json" \
  -H "content-type: application/json" \
  -H "x-api-key: $EXA_API_KEY" \
  -H "x-exa-integration: exa-code-bash" \
  --max-time 30 \
  -d "$body") || die "request to Exa API failed"

# Extract response field
code_content=$(printf '%s' "$response" \
  | sed 's/.*"response":"//' \
  | sed 's/"}//' \
  | sed 's/\\n/\n/g' \
  | sed 's/\\t/\t/g' \
  | sed 's/\\"/"/g' \
  | sed 's/\\\\/\\/g')

if [ -z "$code_content" ]; then
  echo "No code snippets or documentation found. Please try a different query." >&2
  exit 1
fi

printf '%s\n' "$code_content"
