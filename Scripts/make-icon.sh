#!/bin/bash
# Рисует обложку приложения и собирает Resources/Aura.icns.
# Иконка рисуется кодом (Sources/AuraCore/Snapshots/AppIconRenderer.swift):
# правку видно в истории, а не только в бинарном файле.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product AuraShots >/dev/null
ICONSET="build/Aura.iconset"
rm -rf "$ICONSET"
.build/debug/AuraShots icon "$PWD/$ICONSET" >/dev/null

iconutil --convert icns --output Resources/Aura.icns "$ICONSET"
echo "готово: Resources/Aura.icns"
