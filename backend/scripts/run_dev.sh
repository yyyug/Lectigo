#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

python -m uvicorn app.main:app --host "${LECTIGO_HOST:-0.0.0.0}" --port "${LECTIGO_PORT:-8000}"
