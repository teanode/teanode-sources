#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  scripts/verify-index.sh --public-key <base64-raw-ed25519-pubkey> [--index index.json]
  scripts/verify-index.sh --public-key-file <ed25519-public.pem> [--index index.json]

Verifies each index entry message:
  name + "\\n" + version + "\\n" + url + "\\n" + lowercase(sha256)
against .sources[].signature (base64).
USAGE
}

INDEX="index.json"
PUBLIC_KEY_B64=""
PUBLIC_KEY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index)
      INDEX="$2"
      shift 2
      ;;
    --public-key)
      PUBLIC_KEY_B64="$2"
      shift 2
      ;;
    --public-key-file)
      PUBLIC_KEY_FILE="$2"
      shift 2
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

if [[ ! -f "$INDEX" ]]; then
  echo "index file not found: $INDEX" >&2
  exit 1
fi

if [[ -n "$PUBLIC_KEY_FILE" ]]; then
  if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
    echo "public key file not found: $PUBLIC_KEY_FILE" >&2
    exit 1
  fi
  PUBLIC_KEY_B64="$(openssl pkey -pubin -in "$PUBLIC_KEY_FILE" -outform DER | tail -c 32 | base64 -w0)"
fi

if [[ -z "$PUBLIC_KEY_B64" ]]; then
  echo "provide --public-key or --public-key-file" >&2
  exit 1
fi

PUB_RAW="$(mktemp)"
printf '%s' "$PUBLIC_KEY_B64" | base64 -d > "$PUB_RAW"
if [[ "$(wc -c < "$PUB_RAW")" -ne 32 ]]; then
  echo "invalid public key length; expected 32 raw bytes after base64 decode" >&2
  rm -f "$PUB_RAW"
  exit 1
fi

PUB_DER="$(mktemp)"
{
  printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'
  cat "$PUB_RAW"
} > "$PUB_DER"

PUB_PEM="$(mktemp)"
openssl pkey -pubin -inform DER -in "$PUB_DER" -out "$PUB_PEM" >/dev/null 2>&1

COUNT="$(jq '.sources | length' "$INDEX")"
OK=0
FAIL=0

for ((i=0; i<COUNT; i++)); do
  NAME="$(jq -r ".sources[$i].name" "$INDEX")"
  VERSION="$(jq -r ".sources[$i].version" "$INDEX")"
  URL="$(jq -r ".sources[$i].url" "$INDEX")"
  SHA="$(jq -r ".sources[$i].sha256" "$INDEX" | tr '[:upper:]' '[:lower:]')"
  SIG_B64="$(jq -r ".sources[$i].signature" "$INDEX")"

  if [[ -z "$SIG_B64" || "$SIG_B64" == "null" ]]; then
    echo "FAIL sources[$i] $NAME: missing signature"
    FAIL=$((FAIL+1))
    continue
  fi

  MSG_FILE="$(mktemp)"
  printf '%s\n%s\n%s\n%s' "$NAME" "$VERSION" "$URL" "$SHA" > "$MSG_FILE"

  SIG_FILE="$(mktemp)"
  if ! printf '%s' "$SIG_B64" | base64 -d > "$SIG_FILE" 2>/dev/null; then
    echo "FAIL sources[$i] $NAME: invalid base64 signature"
    rm -f "$MSG_FILE" "$SIG_FILE"
    FAIL=$((FAIL+1))
    continue
  fi

  if openssl pkeyutl -verify -rawin -pubin -inkey "$PUB_PEM" -in "$MSG_FILE" -sigfile "$SIG_FILE" >/dev/null 2>&1; then
    echo "OK   sources[$i] $NAME@$VERSION"
    OK=$((OK+1))
  else
    echo "FAIL sources[$i] $NAME@$VERSION: signature mismatch"
    FAIL=$((FAIL+1))
  fi

  rm -f "$MSG_FILE" "$SIG_FILE"
done

rm -f "$PUB_RAW" "$PUB_DER" "$PUB_PEM"

echo "Verified: ok=$OK fail=$FAIL total=$COUNT"
[[ "$FAIL" -eq 0 ]]
