#!/bin/bash

#SBATCH --job-name=lab3_mpi_all
#SBATCH --partition=batch
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=1
#SBATCH --output=logs/lab3_all_%j.out
#SBATCH --error=logs/lab3_all_%j.err

set -euo pipefail

cd "$SLURM_SUBMIT_DIR"

mkdir -p logs extra/matrices extra/res/lab_3

# ============================================================
# Информация об окружении для отчёта
# ============================================================

{
    echo "=== Job info ==="
    echo "JobId: ${SLURM_JOB_ID:-unknown}"
    echo "NodeList: ${SLURM_JOB_NODELIST:-unknown}"
    echo "CPUs: ${SLURM_JOB_CPUS_PER_NODE:-unknown}"
    echo

    echo "=== hostname ==="
    hostname
    echo

    echo "=== nproc ==="
    nproc || true
    echo

    echo "=== lscpu ==="
    lscpu | grep -E "Model name|CPU\(s\)|Thread|Core|Socket" || true
    echo

    echo "=== mpicxx ==="
    mpicxx --version | head -n 1 || true
    echo

    echo "=== g++ ==="
    g++ --version | head -n 1 || true
    echo
} >> "logs/hardware_${SLURM_JOB_ID:-unknown}.txt"

# ============================================================
# Параметры экспериментов
# ============================================================

SIDES=(200 400 800 1200 1600 2000)
PROCS=(1 2 4 8)

CSV="lab3_results.csv"

printf 'side,processes,time_seconds,gops,speedup\n' > "$CSV"

# ============================================================
# Генерация матриц, если их ещё нет
# ============================================================

for side in "${SIDES[@]}"; do
    a_file="extra/matrices/A_${side}.txt"
    b_file="extra/matrices/B_${side}.txt"

    if [[ ! -f "$a_file" || ! -f "$b_file" ]]; then
        echo "=== Генерация матриц для side=${side} ==="
        srun -n 1 ./gen_matrices "$side" 12345 extra/matrices
    fi
done

# ============================================================
# Эксперименты
# ============================================================

for side in "${SIDES[@]}"; do
    echo
    echo "=============================="
    echo "side = ${side}"
    echo "=============================="

    base_out="extra/res/lab_3/C_${side}_p1.txt"

    # Получаем baseline: MPI с одним процессом.
    if [[ ! -f "$base_out" ]]; then
        echo "--- baseline p=1 ---"
        srun -n 1 ./lab3_mpi "$side" > /dev/null
    fi

    baseline="$(
        awk -F= '/^time_seconds=/{print $2; exit}' "$base_out"
    )"

    if [[ -z "$baseline" || "$baseline" == "0" ]]; then
        echo "Ошибка: не удалось получить baseline для side=${side}" >&2
        exit 1
    fi

    echo "baseline time_seconds = ${baseline}"

    for p in "${PROCS[@]}"; do
        echo "--- side=${side}, processes=${p} ---"

        out_file="extra/res/lab_3/C_${side}_p${p}.txt"

        srun -n "$p" ./lab3_mpi "$side" "$baseline" > /dev/null

        awk -F= -v side="$side" -v p="$p" '
            /^time_seconds=/ { time=$2 }
            /^gops=/ { gops=$2 }
            /^speedup_vs_sequential=/ { speed=$2 }
            END {
                if (speed == "") speed = 1.0
                printf "%s,%s,%s,%s,%s\n", side, p, time, gops, speed
            }
        ' "$out_file" >> "$CSV"
    done
done

echo
echo "Готово."
echo "Результаты: ${CSV}"
echo "Логи: logs/"