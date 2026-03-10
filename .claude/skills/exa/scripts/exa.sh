#!/usr/bin/env bash
# exa — Search the web or find code context using Exa AI
# Usage: exa <command> <query> [options]
#
# Commands:
#   web-search    Search the web for current information, news, facts
#   code-context  Find code examples, API usage, library documentation
#   crawl         Fetch and extract full content from a specific URL
#
# web-search options:
#   --num-results <n>           Number of results (default: 8)
#   --livecrawl <fallback|preferred>  Live crawl mode (default: fallback)
#   --type <auto|fast>          Search type (default: auto)
#   --category <company|research paper|people>  Filter by category
#   --max-chars <n>             Max characters for context (default: 10000)
#
# code-context options:
#   --tokens <n>   Number of tokens to return (1000-50000, default: 5000)
#
# crawl options:
#   --max-chars <n>   Max characters to extract (default: 3000)

set -euo pipefail

# Load .env from parent directory
_script_dir="$(cd "$(dirname "$0")" && pwd)"
_env_file="$_script_dir/../../.env"
[ -f "$_env_file" ] && . "$_env_file"

EXA_API_KEY="${EXA_API_KEY:-}"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# //'
  exit 1
}

die() { echo "error: $*" >&2; exit 1; }

[ -z "$EXA_API_KEY" ] && die "EXA_API_KEY is not set"
[ $# -eq 0 ] && usage

# Escape string for JSON
json_escape() {
  printf '%s' "$1" \
    | sed 's/\\/\\\\/g' \
    | sed 's/"/\\"/g' \
    | tr '\n' ' ' \
    | tr '\t' ' '
}

# Unescape JSON string to plain text
json_unescape() {
  sed -e 's/\\n/\n/g' -e 's/\\t/\t/g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}

command="$1"; shift

case "$command" in
  web-search)
    API_URL="https://api.exa.ai/search"

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
          if [ -z "$query" ]; then query="$1"; else query="$query $1"; fi
          shift ;;
      esac
    done

    [ -z "$query" ] && die "query is required"

    json_query=$(json_escape "$query")

    category_field=""
    if [ -n "$category" ]; then
      category_field='"category": "'"$category"'",'
    fi

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

    response=$(curl -sf \
      -X POST "$API_URL" \
      -H "accept: application/json" \
      -H "content-type: application/json" \
      -H "x-api-key: $EXA_API_KEY" \
      -H "x-exa-integration: web-search-bash" \
      --max-time 25 \
      -d "$body") || die "request to Exa API failed"

    context=$(printf '%s' "$response" \
      | sed -e 's/.*"context":"//' -e 's/","requestId".*//' -e 's/","autopromptString".*//' \
      | json_unescape)

    if [ -z "$context" ]; then
      echo "No search results found. Please try a different query." >&2
      exit 1
    fi

    printf '%s\n' "$context"
    ;;

  code-context)
    API_URL="https://api.exa.ai/context"

    query=""
    tokens=5000

    while [ $# -gt 0 ]; do
      case "$1" in
        --tokens)   tokens="$2"; shift 2 ;;
        --help|-h)  usage ;;
        -*)         die "unknown option: $1" ;;
        *)
          if [ -z "$query" ]; then query="$1"; else query="$query $1"; fi
          shift ;;
      esac
    done

    [ -z "$query" ] && die "query is required"

    if [ "$tokens" -lt 1000 ] || [ "$tokens" -gt 50000 ]; then
      die "tokens must be between 1000 and 50000"
    fi

    json_query=$(json_escape "$query")

    body='{
      "query": "'"$json_query"'",
      "tokensNum": '"$tokens"'
    }'

    response=$(curl -sf \
      -X POST "$API_URL" \
      -H "accept: application/json" \
      -H "content-type: application/json" \
      -H "x-api-key: $EXA_API_KEY" \
      -H "x-exa-integration: exa-code-bash" \
      --max-time 30 \
      -d "$body") || die "request to Exa API failed"

    code_content=$(printf '%s' "$response" \
      | sed -e 's/.*"response":"//' -e 's/"}//' \
      | json_unescape)

    if [ -z "$code_content" ]; then
      echo "No code snippets or documentation found. Please try a different query." >&2
      exit 1
    fi

    printf '%s\n' "$code_content"
    ;;

  crawl)
    API_URL="https://api.exa.ai/contents"

    url=""
    max_chars=3000

    while [ $# -gt 0 ]; do
      case "$1" in
        --max-chars)  max_chars="$2"; shift 2 ;;
        --help|-h)    usage ;;
        -*)           die "unknown option: $1" ;;
        *)
          if [ -z "$url" ]; then url="$1"; else die "unexpected argument: $1"; fi
          shift ;;
      esac
    done

    [ -z "$url" ] && die "url is required"

    json_url=$(json_escape "$url")

    body='{
      "ids": ["'"$json_url"'"],
      "contents": {
        "text": {
          "maxCharacters": '"$max_chars"'
        },
        "livecrawl": "preferred"
      }
    }'

    response=$(curl -sf \
      -X POST "$API_URL" \
      -H "accept: application/json" \
      -H "content-type: application/json" \
      -H "x-api-key: $EXA_API_KEY" \
      -H "x-exa-integration: crawling-mcp" \
      --max-time 25 \
      -d "$body") || die "request to Exa API failed"

    # Extract first result fields
    title=$(printf '%s' "$response" | sed -e 's/.*"title":"//' -e 's/".*//')
    url_out=$(printf '%s' "$response" | sed -e 's/.*"url":"//' -e 's/".*//')
    text=$(printf '%s' "$response" \
      | sed -e 's/.*"text":"//' -e 's/"}].*$//' \
      | json_unescape)

    if [ -z "$text" ]; then
      echo "No content found for the provided URL." >&2
      exit 1
    fi

    printf 'Title: %s\nURL: %s\n\n%s\n' "$title" "$url_out" "$text"
    ;;

  *)
    die "unknown command: $command (use 'web-search', 'code-context', or 'crawl')"
    ;;
esac
