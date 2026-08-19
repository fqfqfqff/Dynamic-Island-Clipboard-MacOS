#!/bin/bash
# Пересобирает и перезапускает Aura.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pkill -x Aura 2>/dev/null || true
APP="$("$ROOT/Scripts/build.sh" "${1:-debug}")"
open "$APP"
echo "запущено: $APP"
