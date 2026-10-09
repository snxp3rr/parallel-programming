#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GEN="./build/extra/MatrixGenerator"
LAB1="./build/lab_1/lab1"
LAB2="./build/lab_2/lab2"

MAT_DIR="extra/matrices"
RES1_DIR="extra/res/lab_1"
RES2_DIR="extra/res/lab_2"

SEED="${SEED:-12345}"
RUNS="${RUNS:-1}"

# Размеры матриц по умолчанию.
# Можно передать своими аргументами:
# ./scripts/run_lab2_experiments.sh 200 400 800
if [[ $# -gt 0 ]]; then
    SIZES=("$@")
else
    SIZES=(200 400 800 1200 1600 2000)
fi

# Количество потоков по умолчанию.
# Можно переопределить через переменную окружения:
# THREADS="1 2 4 8" ./scripts/run_lab2_experiments.sh
THREADS_STR="${THREADS:-1 2 4 8}"
read -r -a THREADS <<< "$THREADS_STR"

mkdir -p "$MAT_DIR" "$RES1_DIR" "$RES2_DIR"

require_executable() {
    if [[ ! -x "$1" ]]; then
        echo "Не найден исполняемый файл: $1" >&2
        echo "Сначала собери проект:" >&2
        echo "cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release" >&2
        echo "cmake --build build" >&2
        exit 1
    fi
}

get_field() {
    local file="$1"
    local key="$2"

    awk -F= -v k="$key" '$1 == k { print $2; exit }' "$file"
}

require_executable "$GEN"
require_executable "$LAB1"
require_executable "$LAB2"

printf '%6s %8s %14s %12s %12s %12s\n' \
    "N" \
    "threads" \
    "avg_time_s" \
    "GOPS" \
    "speedup" \
    "efficiency"

for side in "${SIZES[@]}"; do
    a_file="$MAT_DIR/A_${side}.txt"
    b_file="$MAT_DIR/B_${side}.txt"

    # Генерируем матрицы, если их ещё нет.
    if [[ ! -f "$a_file" || ! -f "$b_file" ]]; then
        "$GEN" "$side" "$SEED" "$MAT_DIR" >/dev/null
    fi

    # Берём baseline из последовательной версии lab_1.
    base_file="$RES1_DIR/C_${side}.txt"

    if [[ ! -f "$base_file" ]]; then
        "$LAB1" "$side" >/dev/null
    fi

    baseline="$(get_field "$base_file" time_seconds)"

    if [[ -z "$baseline" || "$baseline" == "0" ]]; then
        echo "Не удалось получить baseline для N=$side" >&2
        exit 1
    fi

    for threads in "${THREADS[@]}"; do
        out_file="$RES2_DIR/C_${side}_t${threads}.txt"

        sum_time=0
        sum_gops=0
        sum_speed=0
        sum_eff=0

        # Если RUNS > 1, делаем несколько прогонов и усредняем метрики.
        for ((run = 1; run <= RUNS; run++)); do
            "$LAB2" "$side" "$threads" "$baseline" >/dev/null

            time_seconds="$(get_field "$out_file" time_seconds)"
            gops="$(get_field "$out_file" gops)"
            speedup="$(get_field "$out_file" speedup_vs_sequential)"
            efficiency="$(get_field "$out_file" efficiency)"

            time_seconds="${time_seconds:-0}"
            gops="${gops:-0}"
            speedup="${speedup:-0}"
            efficiency="${efficiency:-0}"

            sum_time="$(awk -v a="$sum_time" -v b="$time_seconds" \
                'BEGIN { printf "%.17g", a + b }')"

            sum_gops="$(awk -v a="$sum_gops" -v b="$gops" \
                'BEGIN { printf "%.17g", a + b }')"

            sum_speed="$(awk -v a="$sum_speed" -v b="$speedup" \
                'BEGIN { printf "%.17g", a + b }')"

            sum_eff="$(awk -v a="$sum_eff" -v b="$efficiency" \
                'BEGIN { printf "%.17g", a + b }')"
        done

        avg="$(
            awk -v n="$RUNS" \
                -v t="$sum_time" \
                -v g="$sum_gops" \
                -v s="$sum_speed" \
                -v e="$sum_eff" \
            'BEGIN {
                printf "%.9f %.6f %.6f %.6f", t / n, g / n, s / n, e / n
            }'
        )"

        read -r avg_time avg_gops avg_speed avg_eff <<< "$avg"

        printf '%6s %8s %14s %12s %12s %12s\n' \
            "$side" \
            "$threads" \
            "$avg_time" \
            "$avg_gops" \
            "$avg_speed" \
            "$avg_eff"
    done
done