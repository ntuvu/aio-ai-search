#!/usr/bin/env bash
# github — Search GitHub source code using the gh CLI
# Usage:
#   github code-search <query> [--limit n] [--owner org] [--repo owner/repo] [--filename name]
#   github fetch-file <owner/repo> <path>
#
# Query tip: embed filters inline — e.g. "MonthlyPartitionsDefinition language:python"
# Special chars (@, {, }, #, !) are auto-stripped from query before sending to GitHub

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

GH=$(command -v gh 2>/dev/null) || die "gh CLI not found — install via: brew install gh"

[ $# -eq 0 ] && { sed -n '2,9p' "$0" | sed 's/^# //'; exit 1; }

# Unescape JSON string to plain text
json_unescape() {
  sed -e 's/\\n/\n/g' -e 's/\\t/\t/g' -e 's/\\r//g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}

# Strip chars that break GitHub code search: @ { } # ! ( )
sanitize_query() {
  printf '%s' "$1" | tr -d '@{}#!()'
}

command="$1"; shift

case "$command" in
  code-search)
    query=""
    limit=10
    owner=""
    repo=""
    filename=""

    while [ $# -gt 0 ]; do
      _opt="$1"
      case "$_opt" in --*=*) _val="${_opt#*=}"; _opt="${_opt%%=*}"; shift; set -- "$_opt" "$_val" "$@" ;; esac
      case "$1" in
        --limit)      limit="$2";     shift 2 ;;
        --owner)      owner="$2";     shift 2 ;;
        --repo)       repo="$2";      shift 2 ;;
        --filename)   filename="$2";  shift 2 ;;
        --language)
          echo "warning: --language flag often returns empty results. Use 'language:$2' inside the query string instead." >&2
          shift 2 ;;
        --help|-h)    sed -n '2,9p' "$0" | sed 's/^# //'; exit 0 ;;
        -*)           die "unknown option: $1" ;;
        *)
          if [ -z "$query" ]; then query="$1"; else query="$query $1"; fi
          shift ;;
      esac
    done

    [ -z "$query" ] && die "query is required"

    # Auto-sanitize: strip special chars that break GitHub search
    clean_query=$(sanitize_query "$query")
    if [ "$clean_query" != "$query" ]; then
      echo "info: query sanitized: '$query' → '$clean_query'" >&2
    fi

    set -- "$clean_query" --json path,repository,url,textMatches --limit "$limit"
    [ -n "$owner" ]     && set -- "$@" --owner="$owner"
    [ -n "$repo" ]      && set -- "$@" --repo="$repo"
    [ -n "$filename" ]  && set -- "$@" --filename="$filename"

    gh_stderr=$(mktemp)
    trap 'rm -f "$gh_stderr"' EXIT
    raw=$("$GH" search code "$@" 2>"$gh_stderr") || {
      err=$(cat "$gh_stderr")
      die "gh search code failed: $err — run 'gh auth status' to verify"
    }

    if [ -z "$raw" ] || [ "$raw" = "[]" ] || [ "$raw" = "null" ]; then
      echo "No results found for: $clean_query" >&2
      echo "Tip: use a single key identifier + inline language filter, e.g. \"MonthlyPartitionsDefinition language:python\"" >&2
      exit 1
    fi

    results=$(printf '%s' "$raw" | sed 's/},{"path"/}\n{"path"/g')

    count=0
    while IFS= read -r obj; do
      [ -z "$obj" ] && continue
      path=$(printf '%s' "$obj" | sed -e 's/.*"path":"//' -e 's/".*//')
      name_with_owner=$(printf '%s' "$obj" | sed -e 's/.*"nameWithOwner":"//' -e 's/".*//')
      url=$(printf '%s' "$obj" | sed -e 's/.*"url":"//' -e 's/".*//')
      fragment=$(printf '%s' "$obj" \
        | sed 's/.*"fragment":"//' \
        | sed 's/","matches":\[.*//' \
        | json_unescape)

      count=$((count + 1))
      printf -- '--- Result %d ---\n' "$count"
      printf 'Repo: %s\n' "$name_with_owner"
      printf 'File: %s\n' "$path"
      printf 'URL:  %s\n' "$url"
      printf 'Raw:  https://raw.githubusercontent.com/%s/HEAD/%s\n' "$name_with_owner" "$path"
      printf 'Code:\n%s\n\n' "$fragment"
    done <<< "$results"

    [ "$count" -eq 0 ] && { echo "No results parsed." >&2; exit 1; }
    ;;

  fetch-file)
    # Usage: fetch-file <owner/repo> <path>
    [ $# -lt 2 ] && die "usage: fetch-file <owner/repo> <path/to/file>"
    repo_arg="$1"
    file_path="$2"
    raw_url="https://raw.githubusercontent.com/${repo_arg}/HEAD/${file_path}"

    echo "Fetching: $raw_url" >&2
    curl -fsSL "$raw_url" || die "failed to fetch $raw_url"
    ;;

  *)
    die "unknown command: $command (valid: code-search, fetch-file)"
    ;;
esac
