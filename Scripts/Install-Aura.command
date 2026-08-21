#!/bin/bash
#
# Установщик Aura для тех, у кого ничего не настроено.
#
# Двойной клик по этому файлу — и всё: проверит систему, поставит
# инструменты сборки, если их нет, скачает исходники, соберёт и запустит.
#
# Готового приложения нет намеренно: без Developer ID за 99 долларов в год
# macOS помечает скачанное приложение как повреждённое и открывать
# отказывается. Сборка из исходников обходит это полностью.

set -euo pipefail

REPO="https://github.com/fqfqfqff/Dynamic-Island-Clipboard-MacOS.git"
SOURCE="$HOME/Developer/Aura"
MIN_MAJOR=14
MIN_MINOR=4

# Язык сообщений по системному: у проекта два README, пусть и установщик
# говорит на понятном.
if [[ "${LANG:-}" == ru* ]]; then RU=1; else RU=0; fi
say() { if [[ $RU == 1 ]]; then echo "$1"; else echo "$2"; fi; }

trap 'echo; say "Не получилось. Строка $LINENO." "Failed at line $LINENO."; \
      say "Напишите об этом в issues — приложите вывод выше." \
          "Please open an issue and include the output above."; \
      echo; read -r -p "" -n 1' ERR

echo
say "  Aura — установка" "  Aura — installer"
say "  ────────────────" "  ─────────────────"
echo

# ── 1. Система ────────────────────────────────────────────────────────────
VERSION="$(sw_vers -productVersion)"
MAJOR="${VERSION%%.*}"
REST="${VERSION#*.}"
MINOR="${REST%%.*}"
[[ "$MINOR" == "$VERSION" ]] && MINOR=0

if (( MAJOR < MIN_MAJOR )) || { (( MAJOR == MIN_MAJOR )) && (( MINOR < MIN_MINOR )); }; then
    say "  Нужна macOS $MIN_MAJOR.$MIN_MINOR или новее, а здесь $VERSION." \
        "  macOS $MIN_MAJOR.$MIN_MINOR or newer is required, this is $VERSION."
    say "  Раньше в системе не было API аудио-процессов, без которого" \
        "  Earlier versions lack the audio process API that Aura needs"
    say "  Aura не умеет главного — видеть, что играет." \
        "  to see what is playing."
    echo; read -r -p "" -n 1; exit 1
fi
say "  ✓ macOS $VERSION" "  ✓ macOS $VERSION"

# ── 2. Инструменты сборки ─────────────────────────────────────────────────
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    say "  · Нет инструментов разработчика — запрашиваю установку." \
        "  · Developer tools are missing — requesting them."
    say "    Система покажет окно. Дождитесь конца и запустите этот файл снова." \
        "    macOS will show a dialog. Wait for it to finish, then run this again."
    xcode-select --install 2>/dev/null || true
    echo; read -r -p "" -n 1; exit 0
fi
say "  ✓ Инструменты сборки на месте" "  ✓ Build tools ready"

# ── 3. Исходники ──────────────────────────────────────────────────────────
if [[ -d "$SOURCE/.git" ]]; then
    say "  · Обновляю исходники в $SOURCE" "  · Updating sources in $SOURCE"
    git -C "$SOURCE" fetch --quiet origin
    git -C "$SOURCE" reset --hard --quiet origin/main
else
    say "  · Скачиваю исходники в $SOURCE" "  · Downloading sources into $SOURCE"
    mkdir -p "$(dirname "$SOURCE")"
    rm -rf "$SOURCE"
    git clone --quiet --depth 1 "$REPO" "$SOURCE"
fi
say "  ✓ Исходники готовы" "  ✓ Sources ready"

# ── 4. Сборка и установка ─────────────────────────────────────────────────
echo
say "  · Собираю и устанавливаю. Первый раз это около минуты." \
    "  · Building and installing. The first run takes about a minute."
say "    Может понадобиться пароль — он нужен для сертификата подписи," \
    "    A password may be required: it creates a signing certificate so"
say "    без которого выданные разрешения слетают при каждой пересборке." \
    "    the permissions you grant survive future rebuilds."
echo

"$SOURCE/Scripts/setup.sh"

echo
say "  ✓ Готово. Aura запущена и живёт в вырезе." \
    "  ✓ Done. Aura is running and lives in the notch."
say "    Наведите курсор на вырез камеры." "    Move the pointer over the camera notch."
echo
say "    Значок в строке меню — настройки и выход." \
    "    The menu bar icon has settings and quit."
say "    ⌥⌘V — история буфера обмена." "    ⌥⌘V — clipboard history."
echo
say "  Окно можно закрыть." "  You can close this window."
echo
read -r -p "" -n 1
