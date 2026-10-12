#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

BIN="${BIN:-./build/mandelbrot}"
SCHEME="${SCHEME:-round_robin}"
VIEWS="${VIEWS:-1 2}"

# Для block decomposition обычно считаем 1..8 потоков.
# Для round-robin можно добавить 16.
if [[ "$SCHEME" == "block" ]]; then
    DEFAULT_THREADS="1 2 3 4 5 6 7 8"
else
    DEFAULT_THREADS="1 2 3 4 5 6 7 8 16"
fi

THREADS="${THREADS:-$DEFAULT_THREADS}"

if [[ ! -x "$BIN" ]]; then
    echo "Не найден исполняемый файл: $BIN" >&2
    echo "Собери проект:" >&2
    echo "cmake -S lab_5 -B build_lab_5 -DCMAKE_BUILD_TYPE=Release" >&2
    echo "cmake --build build_lab_5" >&2
    exit 1
fi

for view in $VIEWS; do
    out="lab5_${SCHEME}_view${view}.csv"

    printf '"Потоки","Время, мс","Speedup","Max время потока, мс","Min время потока, мс","Imbalance"\n' > "$out"

    for threads in $THREADS; do
        echo "=== scheme=$SCHEME view=$view threads=$threads ===" >&2

        tmp="$(mktemp)"

        PRINT_THREAD_TIMES=1 "$BIN" -t "$threads" -v "$view" >"$tmp" 2>&1

        awk -v threads="$threads" '
            function bracket_ms(line,   s) {
                if (!match(line, /\[[0-9.]+\] ms/)) return "";
                s = substr(line, RSTART, RLENGTH);
                sub(/^\[/, "", s);
                sub(/\] ms$/, "", s);
                return s;
            }

            function speedup_value(line,   s) {
                if (!match(line, /\([0-9.]+x speedup/)) return "";
                s = substr(line, RSTART, RLENGTH);
                gsub(/[^0-9.]/, "", s);
                return s;
            }

            /\[mandelbrot serial\]/ {
                serial = bracket_ms($0)
            }

            /\[mandelbrot thread\]/ {
                thread = bracket_ms($0)
            }

            /x speedup/ {
                speed = speedup_value($0)
            }

            $1 == "thread" && $2 ~ /^[0-9]+:$/ {
                tid = $2;
                sub(/:$/, "", tid);
                val = $3 + 0;

                if (!(tid in mn) || val < mn[tid]) {
                    mn[tid] = val;
                }
            }

            END {
                if (thread == "" || speed == "") {
                    print "Не удалось распарсить время или speedup" > "/dev/stderr";
                    exit 1;
                }

                maxt = -1.0;
                mint = 1e30;

                for (t in mn) {
                    if (mn[t] > maxt) maxt = mn[t];
                    if (mn[t] < mint) mint = mn[t];
                }

                if (maxt < 0.0) {
                    maxt = thread + 0.0;
                    mint = thread + 0.0;
                }

                imb = (mint > 0.0) ? (maxt / mint) : 0.0;

                printf "%s,%.3f,%.2f,%.3f,%.3f,%.3f\n",
                    threads,
                    thread + 0.0,
                    speed + 0.0,
                    maxt,
                    mint,
                    imb;
            }
        ' "$tmp" >> "$out"

        rm -f "$tmp"
    done

    echo "Сохранено: $out" >&2
done