#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GEN="${GEN:-./build/extra/MatrixGenerator}"
LAB1="${LAB1:-./build/lab_1/lab1}"
LAB4="${LAB4:-./build/lab_4/lab4_cuda}"

MAT_DIR="${MAT_DIR:-extra/matrices}"
RES1_DIR="${RES1_DIR:-extra/res/lab_1}"
RES4_DIR="${RES4_DIR:-extra/res/lab_4}"

SEED="${SEED:-12345}"
RUNS="${RUNS:-3}"

# Размеры по умолчанию.
# Можно передать аргументами:
# ./scripts/run_lab4_experiments.sh 200 400 800
if [[ $# -gt 0 ]]; then
    SIZES=("$@")
else
    SIZES=(200 400 800 1200 1600 2000)
fi

# Tile sizes по умолчанию.
# Можно переопределить:
# TILES="8 16 32" ./scripts/run_lab4_experiments.sh
TILES_STR="${TILES:-8 16 32}"
read -r -a TILES <<< "$TILES_STR"

# Kernels по умолчанию.
# Можно: KERNELS="tiled" или KERNELS="tiled naive"
KERNELS_STR="${KERNELS:-tiled}"
read -r -a KERNELS <<< "$KERNELS_STR"

mkdir -p "$MAT_DIR" "$RES1_DIR" "$RES4_DIR"

require_executable() {
    if [[ ! -x "$1" ]]; then
        echo "Не найден исполняемый файл: $1" >&2
        echo "Сначала собери проект, например:" >&2
        echo "cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DPP_ENABLE_CUDA=ON" >&2
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
require_executable "$LAB4"

printf '%6s %6s %8s %14s %12s %12s\n' \
    "side" \
    "tile" \
    "kernel" \
    "avg_time_s" \
    "GOPS" \
    "speedup"

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
        echo "Не удалось получить baseline для N=$side из $base_file" >&2
        exit 1
    fi

    for tile in "${TILES[@]}"; do
        for kernel in "${KERNELS[@]}"; do
            out_file="$RES4_DIR/C_${side}_${kernel}_t${tile}.txt"

            sum_time=0
            sum_gops=0
            sum_speed=0

            flag=""
            if [[ "$kernel" == "tiled" ]]; then
                flag="--tiled"
            elif [[ "$kernel" == "naive" ]]; then
                flag="--naive"
            else
                echo "Неизвестный kernel: $kernel" >&2
                exit 1
            fi

            for ((run = 1; run <= RUNS; run++)); do
                "$LAB4" "$side" "$tile" "$baseline" "$flag" >/dev/null

                time_seconds="$(get_field "$out_file" time_seconds)"
                gops="$(get_field "$out_file" gops)"
                speedup="$(get_field "$out_file" speedup_vs_sequential)"

                time_seconds="${time_seconds:-0}"
                gops="${gops:-0}"
                speedup="${speedup:-0}"

                sum_time="$(awk -v a="$sum_time" -v b="$time_seconds" \
                    'BEGIN { printf "%.17g", a + b }')"

                sum_gops="$(awk -v a="$sum_gops" -v b="$gops" \
                    'BEGIN { printf "%.17g", a + b }')"

                sum_speed="$(awk -v a="$sum_speed" -v b="$speedup" \
                    'BEGIN { printf "%.17g", a + b }')"
            done

            avg="$(
                awk -v n="$RUNS" \
                    -v t="$sum_time" \
                    -v g="$sum_gops" \
                    -v s="$sum_speed" \
                'BEGIN {
                    printf "%.9f %.6f %.6f", t / n, g / n, s / n
                }'
            )"

            read -r avg_time avg_gops avg_speed <<< "$avg"

            printf '%6s %6s %8s %14s %12s %12s\n' \
                "$side" \
                "$tile" \
                "$kernel" \
                "$avg_time" \
                "$avg_gops" \
                "$avg_speed"
        done
    done
done