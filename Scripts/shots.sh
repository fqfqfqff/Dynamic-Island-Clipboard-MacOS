#!/bin/bash
# Снимки интерфейса в build/shots. Разрешений не требует: рисуются
# собственные виды, а не экран.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product AuraShots >/dev/null
OUT="${1:-$PWD/build/shots}"
# Каталог чистится: иначе снимки удалённых сцен остаются и вводят в заблуждение.
rm -rf "$OUT"
.build/debug/AuraShots "$OUT"
