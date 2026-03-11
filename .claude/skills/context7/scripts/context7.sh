#!/usr/bin/env bash
# context7 — Look up library documentation using Context7
# Usage: context7 <command> [options]
#
# Commands:
#   resolve <library_name>   Search for a library ID on Context7
#   query                    Query documentation for a library
#
# resolve options:
#   --query <text>   Original question for relevance ranking (optional)
#
# query options:
#   --library-id <id>   Context7 library ID (e.g., "/reactjs/react.dev")
#   --query <query>     Specific question about the library

set -euo pipefail

# Load .env from parent directory
_script_dir="$(cd "$(dirname "$0")" && pwd)"
_env_file="$_script_dir/../../.env"
[ -f "$_env_file" ] && . "$_env_file"

CONTEXT_API_KEY="${CONTEXT_API_KEY:-}"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# //'
  exit 1
}

die() { echo "error: $*" >&2; exit 1; }

[ -z "$CONTEXT_API_KEY" ] && die "CONTEXT_API_KEY is not set"
[ $# -eq 0 ] && usage

# URL-encode a string (portable, no jq/python)
urlencode() {
  local string="$1" i c
  for (( i = 0; i < ${#string}; i++ )); do
    c="${string:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-/]) printf '%s' "$c" ;;
      ' ') printf '%%20' ;;
      *) printf '%%%02X' "'$c" ;;
    esac
  done
}

# Unescape JSON string to plain text
json_unescape() {
  sed -e 's/\\n/\n/g' -e 's/\\t/\t/g' -e 's/\\"/"/g' -e 's/\\\\/\\/g' \
      -e 's/\\u[0-9a-fA-F]\{4\}//g'
}

case "${1:-}" in --help|-h) usage ;; esac

command="$1"; shift

case "$command" in
  resolve)
    API_URL="https://context7.com/api/v2/libs/search"

    library_name=""
    query=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --query)    query="$2"; shift 2 ;;
        --help|-h)  usage ;;
        -*)         die "unknown option: $1" ;;
        *)
          if [ -z "$library_name" ]; then library_name="$1"; else library_name="$library_name $1"; fi
          shift ;;
      esac
    done

    [ -z "$library_name" ] && die "library name is required"

    encoded_name=$(urlencode "$library_name")
    url="${API_URL}?libraryName=${encoded_name}"

    if [ -n "$query" ]; then
      encoded_query=$(urlencode "$query")
      url="${url}&query=${encoded_query}"
    fi

    response=$(curl -s -w '\n%{http_code}' \
      -X GET "$url" \
      -H "accept: application/json" \
      -H "Authorization: Bearer $CONTEXT_API_KEY" \
      --max-time 15) || die "request to Context7 API failed (network error)"

    http_code="${response##*$'\n'}"
    response="${response%$'\n'*}"
    [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -lt 300 ] || die "Context7 API returned HTTP $http_code"

    if printf '%s' "$response" | grep -q '"error"'; then
      err_msg=$(printf '%s' "$response" | sed -e 's/.*"error":"//' -e 's/".*//')
      die "API error: $err_msg"
    fi

    inner=$(printf '%s' "$response" | sed -e 's/.*"results":\[{/{/' -e 's/}\].*$/}/')
    results=$(printf '%s' "$inner" | awk '{gsub(/\},\{/,"}\n{")}1')

    if [ -z "$results" ] || [ "$results" = "" ]; then
      echo "No libraries found for \"$library_name\". Try a different name." >&2
      exit 1
    fi

    count=0
    while IFS= read -r obj; do
      [ -z "$obj" ] && continue
      id=$(printf '%s' "$obj" | awk -F'"id":"' '{split($2,a,"\""); print a[1]; exit}')
      title=$(printf '%s' "$obj" | awk -F'"title":"' '{split($2,a,"\""); print a[1]; exit}')
      desc=$(printf '%s' "$obj" | awk -F'"description":"' '{split($2,a,"\""); print a[1]; exit}')
      snippets=$(printf '%s' "$obj" | sed -e 's/.*"totalSnippets"://' -e 's/[,}].*//')
      trust=$(printf '%s' "$obj" | sed -e 's/.*"trustScore"://' -e 's/[,}].*//')

      printf -- '- Title: %s\n' "$title"
      printf '  Context7-compatible library ID: %s\n' "$id"
      printf '  Description: %s\n' "$desc"
      printf '  Code Snippets: %s\n' "$snippets"
      printf '  Trust Score: %s\n\n' "$trust"

      count=$((count + 1))
      [ "$count" -ge 5 ] && break
    done <<< "$results"
    ;;

  query)
    API_URL="https://context7.com/api/v2/context"

    library_id=""
    query=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --library-id) library_id="$2"; shift 2 ;;
        --query)      query="$2";      shift 2 ;;
        --help|-h)    usage ;;
        -*)           die "unknown option: $1" ;;
        *)
          if [ -z "$query" ]; then query="$1"; else query="$query $1"; fi
          shift ;;
      esac
    done

    [ -z "$library_id" ] && die "--library-id is required"
    [ -z "$query" ] && die "--query is required"

    encoded_id=$(urlencode "$library_id")
    encoded_query=$(urlencode "$query")
    url="${API_URL}?libraryId=${encoded_id}&query=${encoded_query}&type=txt"

    response=$(curl -s -w '\n%{http_code}' \
      -X GET "$url" \
      -H "accept: application/json" \
      -H "Authorization: Bearer $CONTEXT_API_KEY" \
      --max-time 30) || die "request to Context7 API failed (network error)"

    http_code="${response##*$'\n'}"
    response="${response%$'\n'*}"
    [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -lt 300 ] || die "Context7 API returned HTTP $http_code"

    if printf '%s' "$response" | grep -q '"error"'; then
      err_msg=$(printf '%s' "$response" | sed -e 's/.*"error":"//' -e 's/".*//')
      die "API error: $err_msg"
    fi

    if printf '%s' "$response" | grep -q '"data"'; then
      content=$(printf '%s' "$response" \
        | sed -e 's/.*"data":"//' -e 's/"[[:space:]]*}[[:space:]]*$//' \
        | json_unescape)
    else
      content="$response"
    fi

    if [ -z "$content" ]; then
      echo "No documentation found. Try a different query or library ID." >&2
      exit 1
    fi

    printf '%s\n' "$content"
    ;;

  *)
    die "unknown command: $command (use 'resolve' or 'query')"
    ;;
esac
