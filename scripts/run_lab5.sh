#!/usr/bin/env bash

set -euo pipefail

BIN="${BIN:-./build/mandelbrot}"
OUT="${OUT:-lab5_results.csv}"

if [[ ! -x "$BIN" ]]; then
    echo "Не найден исполняемый файл: $BIN" >&2
    echo "Собери проект:" >&2
    echo "cmake -S lab_5 -B build_lab_5 -DCMAKE_BUILD_TYPE=Release" >&2
    echo "cmake --build build_lab_5" >&2
    exit 1
fi

printf 'view,threads,serial_ms,thread_ms,speedup\n' > "$OUT"

for view in 1 2; do
    for threads in 1 2 3 4 5 6 7 8 16; do
        echo "=== view=$view threads=$threads ===" >&2

        output="$("$BIN" -t "$threads" -v "$view")"

        serial_ms="$(printf '%s\n' "$output" | sed -n 's/.*\[mandelbrot serial\]:.*\[\([0-9.]*\)\] ms.*/\1/p')"
        thread_ms="$(printf '%s\n' "$output" | sed -n 's/.*\[mandelbrot thread\]:.*\[\([0-9.]*\)\] ms.*/\1/p')"
        speedup="$(printf '%s\n' "$output" | sed -n 's/.*(\([0-9.]*\)x speedup.*/\1/p')"

        if [[ -z "$serial_ms" || -z "$thread_ms" || -z "$speedup" ]]; then
            echo "Не удалось распарсить вывод для view=$view threads=$threads" >&2
            printf '%s\n' "$output" >&2
            exit 1
        fi

        printf '%s,%s,%s,%s,%s\n' \
            "$view" \
            "$threads" \
            "$serial_ms" \
            "$thread_ms" \
            "$speedup" >> "$OUT"
    done
done

echo "Результаты сохранены в $OUT"