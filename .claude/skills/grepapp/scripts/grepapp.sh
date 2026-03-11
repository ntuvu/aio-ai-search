#!/usr/bin/env bash
# grepapp — Search 1M+ public GitHub repos using grep.app
# Usage: grepapp <command> [options]
#
# Commands:
#   search    Search repositories for a code pattern
#
# search options:
#   <query>               Code pattern to search for (literal string or regex)
#   --match-case          Case-sensitive matching
#   --match-whole-words   Whole-word matching
#   --use-regexp          Treat query as a regular expression (prefix with (?s) for multiline)
#   --repo <owner/name>   Filter by repository, supports partial match (e.g. facebook/react)
#   --path <pattern>      Filter by file path, supports partial match (e.g. src/components)
#   --lang <language>     Filter by language; repeatable (e.g. --lang TypeScript --lang TSX)
#   --num-results <n>     Number of results (default: 10)
#   --page <n>            Page number (default: 1)

set -euo pipefail

# Load .env from parent directory (no-op for grepapp — no API key required)
_script_dir="$(cd "$(dirname "$0")" && pwd)"
_env_file="$_script_dir/../../.env"
[ -f "$_env_file" ] && . "$_env_file"

usage() {
  sed -n '2,18p' "$0" | sed 's/^# //'
  exit 1
}

die() { echo "error: $*" >&2; exit 1; }

[ $# -eq 0 ] && usage

# URL-encode a string (Bash 3.2 compatible)
urlencode() {
  local string="$1"
  local len="${#string}"
  local encoded=""
  local i=0
  local c
  while [ "$i" -lt "$len" ]; do
    c="${string:$i:1}"
    case "$c" in
      [a-zA-Z0-9._~-]) encoded="${encoded}${c}" ;;
      *) encoded="${encoded}$(printf '%%%02X' "'$c")" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$encoded"
}

# Unescape JSON string values
json_unescape() {
  sed -e 's/\\n/\n/g' -e 's/\\t/\t/g' -e 's/\\"/"/g' -e 's/\\\\/\\/g' \
      -e 's/\\u[0-9a-fA-F]\{4\}//g'
}

case "${1:-}" in --help|-h) usage ;; esac

command="$1"; shift

case "$command" in
  search)
    query=""
    match_case=""
    match_words=""
    use_regexp=""
    repo=""
    path_filter=""
    langs=""
    num_results=10
    page=1

    while [ $# -gt 0 ]; do
      case "$1" in
        --match-case)        match_case="true";    shift ;;
        --match-whole-words) match_words="true";   shift ;;
        --use-regexp)        use_regexp="true";    shift ;;
        --repo)              repo="$2";            shift 2 ;;
        --path)              path_filter="$2";     shift 2 ;;
        --lang)              langs="${langs} $2";  shift 2 ;;
        --num-results)       num_results="$2";     shift 2 ;;
        --page)              page="$2";            shift 2 ;;
        --help|-h)           usage ;;
        -*)                  die "unknown option: $1" ;;
        *)
          if [ -z "$query" ]; then query="$1"; else query="$query $1"; fi
          shift ;;
      esac
    done

    [ -z "$query" ] && die "query is required"

    # Build URL
    url="https://grep.app/api/search?q=$(urlencode "$query")"
    [ -n "$match_case"  ] && url="${url}&case=true"
    [ -n "$match_words" ] && url="${url}&words=true"
    [ -n "$use_regexp"  ] && url="${url}&regexp=true"
    [ -n "$repo"        ] && url="${url}&repo=$(urlencode "$repo")"
    [ -n "$path_filter" ] && url="${url}&path=$(urlencode "$path_filter")"

    # Append repeated lang[] params (langs has a leading space; word-split handles it)
    for lang in $langs; do
      url="${url}&lang[]=$(urlencode "$lang")"
    done

    url="${url}&per_page=${num_results}&page=${page}"

    # Fetch
    response=$(curl -s -w '\n%{http_code}' --max-time 15 \
      -H "Accept: application/json" \
      -H "User-Agent: grepapp-skill/1.0" \
      "$url") || die "request to grep.app API failed (network error)"

    http_code="${response##*$'\n'}"
    response="${response%$'\n'*}"
    [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -lt 300 ] || die "grep.app API returned HTTP $http_code"

    # Single-pass: extract total and hits array together
    # Response structure: {"time":...,"facets":{...},"hits":{"total":N,"hits":[...]}}
    total=$(printf '%s' "$response" | sed 's/.*"hits":{"total"://' | sed 's/,.*//' | tr -d '[:space:]')
    [ -z "$total" ] && total="0"

    if [ "$total" = "0" ]; then
      echo "No results found for: $query"
      exit 0
    fi

    printf '=== grep.app: %s (%s total matches) ===\n' "$query" "$total"

    # Isolate the hits array, then split on object boundaries in a single awk pass
    hits_split=$(printf '%s' "$response" \
      | sed 's/.*"hits":\[//' \
      | sed 's/\]}$//' \
      | awk '{gsub(/},\{"owner_id"/, "}\n{\"owner_id\""); print}' \
      | awk '/\"owner_id\"/')

    idx=0
    # Use process substitution (< <(...)) to avoid a subshell so idx increments correctly
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      idx=$((idx + 1))

      # Extract all metadata fields in a single awk pass
      IFS='|' read -r repo_val branch_val path_val matches_val <<EOF
$(printf '%s' "$hit" | awk -F'"' '{
  for (i=1; i<=NF; i++) {
    if ($i == "repo")          repo    = $(i+2)
    if ($i == "branch")        branch  = $(i+2)
    if ($i == "path")          path    = $(i+2)
    if ($i == "total_matches") {
      m = $(i+2); gsub(/[^0-9]/, "", m); matches = m
    }
  }
  printf "%s|%s|%s|%s", repo, branch, path, matches
}')
EOF

      # Extract snippet and parse code lines in one pipeline:
      # strip JSON wrapper → unescape → split on </tr> → keep data-line rows
      # → strip HTML tags + decode entities + trim whitespace (all in awk)
      code_lines=$(printf '%s' "$hit" \
        | sed 's/.*"snippet":"//' \
        | sed 's/"},"total_matches".*//' \
        | tr '\r' '\n' \
        | json_unescape \
        | awk '
            { gsub(/<\/tr>/, "\n") }
            /data-line=/ {
              gsub(/<[^>]*>/, "")
              gsub(/&amp;/,  "\\&")
              gsub(/&lt;/,   "<")
              gsub(/&gt;/,   ">")
              gsub(/&quot;/, "\"")
              gsub(/&#39;/,  "'"'"'")
              gsub(/&nbsp;/, " ")
              gsub(/^[[:space:]]+/, "")
              if (length($0) > 0) print
            }')

      printf '\n[%d] %s  (%s)\n' "$idx" "$repo_val" "$branch_val"
      printf '    %s  [%s matches]\n' "$path_val" "$matches_val"

      if [ -n "$code_lines" ]; then
        printf '%s\n' "$code_lines" | while IFS= read -r line; do
          printf '    | %s\n' "$line"
        done
      fi

      printf '    URL: https://github.com/%s/blob/%s/%s\n' \
        "$repo_val" "$branch_val" "$path_val"
    done < <(printf '%s\n' "$hits_split")
    ;;

  *)
    die "unknown command: $command (use 'search')"
    ;;
esac
