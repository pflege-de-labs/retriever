#!/bin/sh
set -eu
# spec line: <owner/repo> <tag> <asset-glob> <dest>   (dest ending in / = directory)
spec=${SPEC:-/config/artifacts}
# no list means nothing to fetch; the app must still start
[ -f "$spec" ] || { echo "no artifact list at $spec, nothing to fetch"; exit 0; }

api=https://api.github.com
key=${GH_APP_KEY_FILE:-/gh-app/private-key.pem}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rel=$tmp/release.json assets=$tmp/assets auth=$tmp/auth-none
# credentials optional so public repos work; header files keep them out of the process list
: >"$auth"
[ -z "${GH_TOKEN:-}" ] || printf 'Authorization: Bearer %s\n' "$GH_TOKEN" >"$auth"
if [ -z "${GH_TOKEN:-}" ] && [ -n "${GH_APP_ID:-}" ] && [ ! -f "$key" ]; then
  echo "error: GH_APP_ID is set but the private key $key is missing" >&2
  exit 1
fi

# get <url> <file> <accept> [method]: exits with a message naming $ctx on any non-2xx answer
get() {
  code=$(curl -sSL -X "${4:-GET}" -H @"$auth" -H "Accept: $3" -o "$2" -w '%{http_code}' "$1" </dev/null) ||
    { echo "error: request failed: $1" >&2; exit 1; }
  case "$code" in
    2??) return ;;
    401|403) echo "error: HTTP $code for $ctx: credentials missing, invalid or without access (or rate limit hit)" >&2 ;;
    404) echo "error: HTTP 404 for $ctx: not found, or private and not readable with the given credentials" >&2 ;;
    *) echo "error: HTTP $code for $ctx ($1)" >&2 ;;
  esac
  rm -f "$2"
  exit 1
}

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# app_auth <owner/repo>: points $auth at an installation token, one per owner since each owner has its own installation
app_auth() {
  owner_auth=$tmp/auth-${1%%/*}
  if [ ! -f "$owner_auth" ]; then
    now=$(date +%s)
    # iat 60s back against clock drift; GitHub rejects exp more than 10 minutes ahead
    jwt=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$GH_APP_ID" | b64url)
    jwt=$jwt.$(printf '%s' "$jwt" | openssl dgst -sha256 -sign "$key" -binary | b64url)
    auth=$tmp/auth-jwt
    printf 'Authorization: Bearer %s\n' "$jwt" >"$auth"
    ctx="GitHub App $GH_APP_ID on $1 (is it installed there?)"
    get "$api/repos/$1/installation" "$tmp/installation.json" application/vnd.github+json
    ctx="GitHub App $GH_APP_ID token for $1"
    get "$api/app/installations/$(jq -r .id "$tmp/installation.json")/access_tokens" "$tmp/token.json" application/vnd.github+json POST
    printf 'Authorization: Bearer %s\n' "$(jq -r .token "$tmp/token.json")" >"$owner_auth"
    rm -f "$auth" "$tmp/token.json"
  fi
  auth=$owner_auth
}

# `|| [ -n ]` keeps a last line without trailing newline
while read -r repo tag pattern dest || [ -n "${repo:-}" ]; do
  case "$repo" in ''|\#*) continue ;; esac
  echo "fetching $repo@$tag $pattern -> $dest"
  [ -n "${GH_TOKEN:-}" ] || [ -z "${GH_APP_ID:-}" ] || app_auth "$repo"
  ctx=$repo@$tag
  get "$api/repos/$repo/releases/tags/$tag" "$rel" application/vnd.github+json
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
