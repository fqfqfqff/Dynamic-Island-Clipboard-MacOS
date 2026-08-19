#!/bin/bash
# Полная установка Aura с нуля.
#
# Делает всё, что нужно для рабочего приложения: сертификат для стабильной
# подписи, сборку, установку в ~/Applications, заставку и автозапуск.
# Разрешения система спросит сама — их выдаёт только человек.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

step() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }
ok()   { printf "  ✓ %s\n" "$1"; }
warn() { printf "  ! %s\n" "$1"; }

step "Проверяю окружение"
VERSION="$(sw_vers -productVersion)"
MAJOR="${VERSION%%.*}"
if [ "$MAJOR" -lt 14 ]; then
    echo "  Нужна macOS 14.4 или новее, у вас $VERSION"
    exit 1
fi
ok "macOS $VERSION"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "  Не найдены инструменты разработчика. Установите: xcode-select --install"
    exit 1
fi
ok "инструменты сборки на месте"

step "Сертификат для подписи"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Aura Dev Signing"; then
    ok "уже создан"
else
    warn "создаю — связка ключей может спросить пароль"
    "$ROOT/Scripts/make-cert.sh" >/dev/null 2>&1 && ok "создан" || warn "не создан: разрешения будут слетать при пересборке"
fi

step "Сборка и установка приложения"
"$ROOT/Scripts/install.sh" >/dev/null
ok "установлено в ~/Applications/Aura.app"

step "Заставка для экрана блокировки"
"$ROOT/Scripts/install-saver.sh" >/dev/null 2>&1 && ok "установлена" || warn "не установилась, попробуйте Scripts/install-saver.sh"

step "Автозапуск"
sleep 4   # приложению нужно подняться и открыть управляющий сокет
if "$ROOT/Scripts/aura" autostart >/dev/null 2>&1; then
    ok "включён — Aura будет стартовать при входе в систему"
else
    warn "не включился, поставьте галочку в Настройки → Система"
fi

step "Готово"
cat <<'NOTE'

  Осталось выдать разрешения — их система спрашивает сама, при первом
  обращении. Что и зачем:

    Универсальный доступ   вставка из буфера по ⌥⌘V
    Автоматизация          что играет в Музыке и Spotify
    Запись звука           полоски эквалайзера по реальным частотам

  Если запрос не появился, откройте Настройки Aura (правый клик по иконке
  в строке меню) → Система → «Запросить разрешения заново».

  Заставку нужно выбрать один раз: Системные настройки → Заставка → Aura.

  Проверить состояние в любой момент:  Scripts/aura status

NOTE
