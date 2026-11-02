#!/bin/sh
set -eu
# spec line: <owner/repo> <tag> <asset-glob> <dest>   (dest ending in / = directory)
# `|| [ -n ]` keeps a last line without trailing newline
while read -r repo tag pattern dest || [ -n "${repo:-}" ]; do
  case "$repo" in ''|\#*) continue ;; esac
  echo "fetching $repo@$tag $pattern -> $dest"
  case "$dest" in
    */) gh release download "$tag" -R "$repo" -p "$pattern" -D "$dest" --clobber ;;
    *)  mkdir -p "$(dirname "$dest")"
        gh release download "$tag" -R "$repo" -p "$pattern" -O "$dest" --clobber ;;
  esac
done < "${SPEC:-/config/artifacts}"
