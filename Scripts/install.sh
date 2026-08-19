#!/bin/bash
# Устанавливает Aura в ~/Applications — постоянный путь, по которому macOS
# сможет запомнить выданные разрешения.
#
# Сборка в build/ пересоздаётся каждый раз, и для TCC это каждый раз новое
# приложение: ползунок в «Универсальном доступе» становится неактивным.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$HOME/Applications/Aura.app"

APP="$("$ROOT/Scripts/build.sh" release)"

pkill -x Aura 2>/dev/null || true
sleep 1

mkdir -p "$HOME/Applications"
rm -rf "$TARGET"
cp -R "$APP" "$TARGET"

IDENTITY="Aura Dev Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$TARGET" 2>/dev/null
    echo "подписано сертификатом «$IDENTITY» — разрешения переживут пересборку"
else
    codesign --force --sign - "$TARGET" 2>/dev/null
    echo "ВНИМАНИЕ: сертификата нет, подпись ad-hoc."
    echo "Разрешения будут слетать при каждой переустановке."
    echo "Сначала выполните: Scripts/make-cert.sh"
fi

open "$TARGET"
echo "установлено: $TARGET"
