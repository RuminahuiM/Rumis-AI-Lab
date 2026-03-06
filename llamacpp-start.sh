#!/bin/bash
set -e

# ─── llama.cpp Model Downloader ─────────────────────────────────────────────
# Downloads GGUF models from HuggingFace into /models/ volume.
# Each model is defined as:  HF_REPO  (and optionally HF_FILE for a specific file)
#
# Usage: This script is run by the llamacpp-init container.
#        Models defined in MODELS array below.
# ─────────────────────────────────────────────────────────────────────────────

apt-get update -qq && apt-get install -y -qq curl jq > /dev/null 2>&1

# ── Define models to download ──
# Add more entries here to download additional models.
# Format: "repo|filename" — leave filename empty to auto-detect.
MODELS=(
  "ggml-org/gpt-oss-20b-GGUF|gpt-oss-20b-mxfp4.gguf"
)

for entry in "${MODELS[@]}"; do
  REPO=$(echo "$entry" | cut -d'|' -f1)
  FILE=$(echo "$entry" | cut -d'|' -f2)
  SAFE_REPO=$(echo "$REPO" | tr '/' '_')

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 Processing: $REPO"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # If no specific file given, find the GGUF file in the repo
  if [ -z "$FILE" ]; then
    echo "🔍 Looking up GGUF files in repo..."
    API_URL="https://huggingface.co/api/models/${REPO}"
    FILE=$(curl -sL "$API_URL" | jq -r '[.siblings[].rfilename | select(endswith(".gguf"))][0] // empty')
    if [ -z "$FILE" ]; then
      echo "❌ No .gguf file found in $REPO"
      continue
    fi
    echo "Found: $FILE"
  fi

  DEST="/models/${FILE}"

  if [ -f "$DEST" ]; then
    echo "✅ Already downloaded: $FILE"
    continue
  fi

  echo "⏳ Downloading $FILE from $REPO ..."
  DOWNLOAD_URL="https://huggingface.co/${REPO}/resolve/main/${FILE}"

  HTTP_ARGS="-L -o ${DEST} --progress-bar"
  if [ -n "$HF_TOKEN" ] && [ "$HF_TOKEN" != "" ]; then
    HTTP_ARGS="$HTTP_ARGS -H \"Authorization: Bearer ${HF_TOKEN}\""
  fi

  eval curl $HTTP_ARGS "$DOWNLOAD_URL"

  if [ -f "$DEST" ]; then
    echo ""
    echo "✅ Downloaded: $FILE ($(du -h "$DEST" | cut -f1))"
  else
    echo "❌ Download failed for $FILE"
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Models in /models/:"
ls -lh /models/*.gguf 2>/dev/null || echo "(none)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Init complete."