#!/bin/bash
# Замер расхода в покое: сколько процессор и память тратит приложение,
# когда его никто не трогает.
#
# Зачем отдельный скрипт: расход растёт незаметно. Скрытое окно витрины
# держало таймер и перерисовывалось за кадром — 1.29% процессора вместо 0.10%
# и лишние 60 МБ. Глазами такое не видно, только замером.
#
# Выход: 0 — уложились, 1 — превышен бюджет, 2 — замерить не вышло
# (нет графической сессии; так бывает на голом раннере).
set -uo pipefail
cd "$(dirname "$0")/.."

# Бюджеты. Взяты с запасом от текущих значений на M1: 0.1% и 81 МБ.
BUDGET_CPU="${AURA_BUDGET_CPU:-1.5}"     # проценты одного ядра
BUDGET_RSS="${AURA_BUDGET_RSS:-220}"     # мегабайты
SETTLE="${AURA_BENCH_SETTLE:-20}"        # прогрев перед замером, секунды
WINDOW="${AURA_BENCH_WINDOW:-30}"        # длина замера, секунды

APP="build/Aura.app"
started_here=false

say() { printf '%s\n' "$*"; }

# --- Приложение --------------------------------------------------------

pid_of_aura() { pgrep -x Aura | head -1; }

if [ -z "$(pid_of_aura)" ]; then
    [ -d "$APP" ] || ./Scripts/build.sh release >/dev/null || exit 2

    open "$APP" 2>/dev/null || { say "не удалось запустить — нет сессии"; exit 2; }
    started_here=true

    for _ in $(seq 1 20); do
        [ -n "$(pid_of_aura)" ] && break
        sleep 1
    done
fi

PID="$(pid_of_aura)"
[ -n "$PID" ] || { say "приложение не запустилось"; exit 2; }

cleanup() { $started_here && kill "$PID" 2>/dev/null; }
trap cleanup EXIT

# --- Замер -------------------------------------------------------------

# Первые секунды после запуска не показательны: строятся окна, опрашиваются
# источники, прогреваются кэши. Мерить нужно установившийся покой.
say "прогрев ${SETTLE} с…"
sleep "$SETTLE"

say "замер ${WINDOW} с…"
samples=0
cpu_total=0
rss_peak=0

end=$(( $(date +%s) + WINDOW ))
while [ "$(date +%s)" -lt "$end" ]; do
    read -r cpu rss <<< "$(ps -o %cpu=,rss= -p "$PID" 2>/dev/null)"
    [ -n "${cpu:-}" ] || { say "процесс исчез во время замера"; exit 2; }

    cpu_total=$(echo "$cpu_total + $cpu" | bc)
    samples=$(( samples + 1 ))
    rss_mb=$(( rss / 1024 ))
    [ "$rss_mb" -gt "$rss_peak" ] && rss_peak=$rss_mb
    sleep 2
done

[ "$samples" -gt 0 ] || { say "ни одного замера"; exit 2; }
cpu_avg=$(echo "scale=2; $cpu_total / $samples" | bc)

# --- Итог --------------------------------------------------------------

say ""
say "процессор в покое: ${cpu_avg}%  (бюджет ${BUDGET_CPU}%)"
say "память, пик:       ${rss_peak} МБ  (бюджет ${BUDGET_RSS} МБ)"

over=0
[ "$(echo "$cpu_avg > $BUDGET_CPU" | bc)" -eq 1 ] && { say "❌ процессор вне бюджета"; over=1; }
[ "$rss_peak" -gt "$BUDGET_RSS" ] && { say "❌ память вне бюджета"; over=1; }

[ "$over" -eq 0 ] && say "✅ в бюджете"
exit "$over"
