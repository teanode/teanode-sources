#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  scripts/sign-index.sh --key <ed25519-private-key.pem> [--index index.json] [--output index.signed.json] [--in-place] [--print-public-key]

Notes:
  - Signs each entry message as:
      name + "\\n" + version + "\\n" + url + "\\n" + lowercase(sha256)
  - Signature is base64 and written to .sources[].signature
  - --print-public-key prints the base64 raw 32-byte Ed25519 public key for TeaNode config skillsRegistry.sources[].publicKeys
USAGE
}

INDEX="index.json"
OUTPUT=""
KEY=""
IN_PLACE=0
PRINT_PUBLIC_KEY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index)
      INDEX="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --key)
      KEY="$2"
      shift 2
      ;;
    --in-place)
      IN_PLACE=1
      shift
      ;;
    --print-public-key)
      PRINT_PUBLIC_KEY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required" >&2
  exit 1
fi

if [[ -z "$KEY" ]]; then
  echo "--key is required" >&2
  exit 1
fi
if [[ ! -f "$KEY" ]]; then
  echo "key file not found: $KEY" >&2
  exit 1
fi
if [[ ! -f "$INDEX" ]]; then
  echo "index file not found: $INDEX" >&2
  exit 1
fi

if [[ "$PRINT_PUBLIC_KEY" -eq 1 ]]; then
  openssl pkey -in "$KEY" -pubout -outform DER | tail -c 32 | base64 -w0
  echo
  exit 0
fi

if [[ "$IN_PLACE" -eq 1 ]]; then
  OUTPUT="$INDEX"
fi
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="index.signed.json"
fi

TMP="$(mktemp)"
cp "$INDEX" "$TMP"

COUNT="$(jq '.sources | length' "$TMP")"
for ((i=0; i<COUNT; i++)); do
  NAME="$(jq -r ".sources[$i].name" "$TMP")"
  VERSION="$(jq -r ".sources[$i].version" "$TMP")"
  URL="$(jq -r ".sources[$i].url" "$TMP")"
  SHA="$(jq -r ".sources[$i].sha256" "$TMP" | tr '[:upper:]' '[:lower:]')"

  if [[ -z "$NAME" || -z "$VERSION" || -z "$URL" || -z "$SHA" || "$NAME" == "null" || "$VERSION" == "null" || "$URL" == "null" || "$SHA" == "null" ]]; then
    echo "invalid entry at sources[$i]: missing name/version/url/sha256" >&2
    rm -f "$TMP"
    exit 1
  fi

  MESSAGE="${NAME}"$'\n'"${VERSION}"$'\n'"${URL}"$'\n'"${SHA}"
  MSG_FILE="$(mktemp)"
  printf '%s' "$MESSAGE" > "$MSG_FILE"
  SIG="$(openssl pkeyutl -sign -rawin -inkey "$KEY" -in "$MSG_FILE" | base64 -w0)"
  rm -f "$MSG_FILE"

  UPDATED="$(mktemp)"
  jq ".sources[$i].signature = \"$SIG\"" "$TMP" > "$UPDATED"
  mv "$UPDATED" "$TMP"
done

mv "$TMP" "$OUTPUT"
echo "Signed $COUNT sources -> $OUTPUT"
