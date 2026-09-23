#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-keys}"
NAME="${2:-teanode-sources}"

mkdir -p "$OUT_DIR"
PRIV="$OUT_DIR/$NAME-ed25519-private.pem"
PUB="$OUT_DIR/$NAME-ed25519-public.pem"

if [[ -f "$PRIV" ]]; then
  echo "refusing to overwrite existing key: $PRIV" >&2
  exit 1
fi

openssl genpkey -algorithm Ed25519 -out "$PRIV"
chmod 600 "$PRIV"
openssl pkey -in "$PRIV" -pubout -out "$PUB"

echo "Private key: $PRIV"
echo "Public key:  $PUB"
echo "TeaNode publicKeys value (base64 raw 32-byte key):"
openssl pkey -in "$PRIV" -pubout -outform DER | tail -c 32 | base64 -w0
echo
