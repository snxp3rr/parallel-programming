#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GEN="./build/extra/MatrixGenerator"
LAB1="./build/lab_1/lab1"

MAT_DIR="extra/matrices"
RES_DIR="extra/res/lab_1"

# Количество повторов для каждого размера.
# Например: RUNS=5 ./scripts/run_lab1_.sh
RUNS="${RUNS:-5}"

# Seed для генерации матриц, если файлов ещё нет.
SEED="${SEED:-12345}"

# Если CSV=1, вывод будет в формате CSV.
CSV="${CSV:-0}"

# Если VERIFY=1, после замеров для каждого размера будет запускаться Python-проверка.
# Например: VERIFY=1 ./scripts/run_lab1_experiments.sh
VERIFY="${VERIFY:-0}"

# Размеры по умолчанию для первой лабораторной.
# ./scripts/run_lab1_experiments.sh 200 400 800 1200 1600 2000
if [[ $# -gt 0 ]]; then
    SIZES=("$@")
else
    SIZES=(20 100 250 500 1000 1500 2000)
fi

mkdir -p "$MAT_DIR" "$RES_DIR"

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

VERIFY_SCRIPT=""

if [[ "$VERIFY" == "1" ]]; then
    if [[ -f scripts/verify.py ]]; then
        VERIFY_SCRIPT="scripts/verify.py"
    elif [[ -f scripts/verify_numpy.py ]]; then
        VERIFY_SCRIPT="scripts/verify_numpy.py"
    else
        echo "Не найден скрипт проверки: scripts/verify.py или scripts/verify_numpy.py" >&2
        exit 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Для VERIFY=1 нужен python3" >&2
        exit 1
    fi
fi

if [[ "$CSV" == "1" ]]; then
    printf 'N,total_elements,avg_time_s,min_time_s,max_time_s,gops,integer_operations,memory_bytes\n'
else
    printf '%6s %14s %14s %14s %14s %12s %18s %14s\n' \
        "N" \
        "total_elements" \
        "avg_time_s" \
        "min_time_s" \
        "max_time_s" \
        "gops" \
        "integer_operations" \
        "memory_bytes"
fi

for side in "${SIZES[@]}"; do
    a_file="$MAT_DIR/A_${side}.txt"
    b_file="$MAT_DIR/B_${side}.txt"

    # Генерируем матрицы, если их ещё нет.
    if [[ ! -f "$a_file" || ! -f "$b_file" ]]; then
        "$GEN" "$side" "$SEED" "$MAT_DIR" >/dev/null
    fi

    out_file="$RES_DIR/C_${side}.txt"

    total=$(awk -v n="$side" 'BEGIN { printf "%.0f", n * n }')
    operations=$(awk -v n="$side" 'BEGIN { printf "%.0f", 2 * n * n * n - n * n }')
    memory_bytes=$(awk -v n="$side" 'BEGIN { printf "%.0f", 3 * n * n * 4 }')

    sum_time=0
    sum_gops=0
    min_time=""
    max_time=""

    # Делаем RUNS замеров.
    for ((run = 1; run <= RUNS; run++)); do
        "$LAB1" "$side" >/dev/null

        time_seconds=$(get_field "$out_file" time_seconds)
        gops=$(get_field "$out_file" gops)

        if [[ -z "$time_seconds" || -z "$gops" ]]; then
            echo "Не удалось прочитать метрики из файла: $out_file" >&2
            exit 1
        fi

        if [[ -z "$min_time" ]]; then
            min_time="$time_seconds"
            max_time="$time_seconds"
        else
            min_time=$(awk -v a="$min_time" -v b="$time_seconds" \
                'BEGIN { printf "%.17g", (a < b ? a : b) }')

            max_time=$(awk -v a="$max_time" -v b="$time_seconds" \
                'BEGIN { printf "%.17g", (a > b ? a : b) }')
        fi

        sum_time=$(awk -v a="$sum_time" -v b="$time_seconds" \
            'BEGIN { printf "%.17g", a + b }')

        sum_gops=$(awk -v a="$sum_gops" -v b="$gops" \
            'BEGIN { printf "%.17g", a + b }')
    done

    avg_time=$(awk -v s="$sum_time" -v n="$RUNS" \
        'BEGIN { printf "%.9f", s / n }')

    avg_gops=$(awk -v s="$sum_gops" -v n="$RUNS" \
        'BEGIN { printf "%.6f", s / n }')

    min_time_fmt=$(awk -v x="$min_time" 'BEGIN { printf "%.9f", x }')
    max_time_fmt=$(awk -v x="$max_time" 'BEGIN { printf "%.9f", x }')

    if [[ "$CSV" == "1" ]]; then
        printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
            "$side" \
            "$total" \
            "$avg_time" \
            "$min_time_fmt" \
            "$max_time_fmt" \
            "$avg_gops" \
            "$operations" \
            "$memory_bytes"
    else
        printf '%6s %14s %14s %14s %14s %12s %18s %14s\n' \
            "$side" \
            "$total" \
            "$avg_time" \
            "$min_time_fmt" \
            "$max_time_fmt" \
            "$avg_gops" \
            "$operations" \
            "$memory_bytes"
    fi

    # Опциональная проверка через NumPy.
    if [[ "$VERIFY" == "1" ]]; then
        python3 "$VERIFY_SCRIPT" "$side" >/dev/null
    fi
done