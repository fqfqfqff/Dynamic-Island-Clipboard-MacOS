#!/bin/bash
# Пересобрать эталоны для сравнения снимков.
#
# Запускать осознанно: эталон — это «так и должно выглядеть». Обновили
# по ошибке — и тест больше не поймает ничего.
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/shots.sh >/dev/null
for scene in 01-collapsed-empty 03-peek 06-notification \
             08-peek-hint 09-notification-badge 12-notification-long; do
    cp "build/shots/$scene.png" "Tests/Baselines/$scene.png"
    echo "обновлён: $scene"
done
