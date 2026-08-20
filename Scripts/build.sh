#!/bin/bash
# Собирает Aura.app из SwiftPM-таргета.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/build/Aura.app"

cd "$ROOT"
swift build -c "$CONFIG" >&2
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Aura"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Aura"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ресурсы SwiftPM лежат отдельными бандлами рядом с бинарём — без них
# приложение остаётся без переводов.
BIN_DIR="$(dirname "$BIN")"
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Стабильный сертификат, если он создан (Scripts/make-cert.sh), иначе ad-hoc.
# С ad-hoc подписью CDHash меняется при каждой сборке и выданное разрешение
# Accessibility слетает — см. риск R3 в PLAN.md.
IDENTITY="Aura Dev Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null
else
    codesign --force --sign - "$APP" 2>/dev/null
fi

echo "$APP"
