#!/bin/bash
# Собирает и ставит заставку Aura — единственный способ показать плеер
# поверх заблокированного экрана.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="Aura"
TARGET="$HOME/Library/Screen Savers/$NAME.saver"

cd "$ROOT"
swift build -c release --product AuraSaver

BIN="$(swift build -c release --show-bin-path)/libAuraSaver.dylib"
[ -f "$BIN" ] || BIN="$(swift build -c release --show-bin-path)/libAuraSaver.so"

rm -rf "$TARGET"
mkdir -p "$TARGET/Contents/MacOS" "$TARGET/Contents/Resources"
cp "$BIN" "$TARGET/Contents/MacOS/$NAME"

cat > "$TARGET/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundleExecutable</key>
    <string>$NAME</string>
    <key>CFBundleIdentifier</key>
    <string>dev.kekch.aura.saver</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>AuraSaverView</string>
</dict>
PLIST
echo "</plist>" >> "$TARGET/Contents/Info.plist"

IDENTITY="Aura Dev Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$TARGET" 2>/dev/null
else
    codesign --force --sign - "$TARGET" 2>/dev/null
fi

echo "установлено: $TARGET"
echo
echo "Дальше:"
echo "  1. Системные настройки → Заставка → выберите «$NAME»"
echo "  2. Экран блокировки → «Начинать заставку при бездействии» и"
echo "     «Требовать пароль после начала заставки» — по вкусу"
echo
echo "Заставка читает /Users/Shared/Aura/nowplaying.json, который пишет Aura."
