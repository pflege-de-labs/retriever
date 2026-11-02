#!/bin/sh
set -eu
# spec line: <owner/repo> <tag> <asset-glob> <dest>   (dest ending in / = directory)
spec=${SPEC:-/config/artifacts}
# no list means nothing to fetch; the app must still start
[ -f "$spec" ] || { echo "no artifact list at $spec, nothing to fetch"; exit 0; }

hdr=$(mktemp) rel=$(mktemp) assets=$(mktemp)
trap 'rm -f "$hdr" "$rel" "$assets"' EXIT
# token optional so public repos work; header file keeps it out of the process list
[ -z "${GH_TOKEN:-}" ] || printf 'Authorization: Bearer %s\n' "$GH_TOKEN" >"$hdr"

# get <url> <file> <accept>: exits with a message on any non-2xx answer
get() {
  code=$(curl -sSL -H @"$hdr" -H "Accept: $3" -o "$2" -w '%{http_code}' "$1" </dev/null) ||
    { echo "error: request failed: $1" >&2; exit 1; }
  case "$code" in
    2??) return ;;
    401|403) echo "error: HTTP $code for $repo@$tag: GH_TOKEN missing, invalid or without access (or rate limit hit)" >&2 ;;
    404) echo "error: HTTP 404 for $repo@$tag: not found (private repos need GH_TOKEN)" >&2 ;;
    *) echo "error: HTTP $code for $repo@$tag ($1)" >&2 ;;
  esac
  rm -f "$2"
  exit 1
}

# `|| [ -n ]` keeps a last line without trailing newline
while read -r repo tag pattern dest || [ -n "${repo:-}" ]; do
  case "$repo" in ''|\#*) continue ;; esac
  echo "fetching $repo@$tag $pattern -> $dest"
  get "https://api.github.com/repos/$repo/releases/tags/$tag" "$rel" application/vnd.github+json
  # count matches before downloading, so a bad line writes nothing
  jq -r '.assets[] | "\(.url) \(.name)"' "$rel" | while read -r url name; do
    # unquoted on purpose: the pattern is a glob
    # shellcheck disable=SC2254
    case "$name" in $pattern) echo "$url $name" ;; esac
  done >"$assets"
  n=$(wc -l <"$assets")
  [ "$n" -gt 0 ] || { echo "error: no asset of $repo@$tag matches $pattern" >&2; exit 1; }
  case "$dest" in
    */) ;;
    *) [ "$n" -eq 1 ] || { echo "error: $pattern matches $n assets of $repo@$tag; end $dest with / for a directory" >&2; exit 1; } ;;
  esac
  while read -r url name; do
    case "$dest" in */) out=$dest$name ;; *) out=$dest ;; esac
    mkdir -p "$(dirname "$out")"
    # .part so a failed download never leaves a truncated file behind
    get "$url" "$out.part" application/octet-stream
    mv "$out.part" "$out"
  done <"$assets"
done <"$spec"
