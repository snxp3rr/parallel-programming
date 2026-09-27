import argparse
import io
import sys
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
MARKER = "--- MATRIX ---"


def read_matrix(
    path: Path,
    reported: bool = False,
    expected_side: int | None = None
) -> np.ndarray:
    with path.open("r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    idx = 0

    if reported:
        while idx < len(lines) and lines[idx].strip() != MARKER:
            idx += 1

        if idx == len(lines):
            raise ValueError(f"{path}: не найден маркер {MARKER!r}")

        idx += 1

    while idx < len(lines) and not lines[idx].strip():
        idx += 1

    if idx >= len(lines):
        raise ValueError(f"{path}: не найден размер матрицы")

    side = int(lines[idx].strip())
    idx += 1

    if side <= 0:
        raise ValueError(f"{path}: количество элементов в строке должно быть положительным")

    if expected_side is not None and side != expected_side:
        raise ValueError(
            f"{path}: ожидалось side={expected_side}, получено side={side}"
        )

    body = "\n".join(lines[idx:])

    arr = np.loadtxt(io.StringIO(body), dtype=np.int64, ndmin=2)

    if arr.shape != (side, side):
        raise ValueError(
            f"{path}: ожидалась форма ({side}, {side}), получена {arr.shape}"
        )

    return arr


def read_report(path: Path) -> dict[str, str]:
    meta = {}

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()

            if line == MARKER:
                break

            if "=" in line:
                key, value = line.split("=", 1)
                meta[key] = value

    return meta


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Проверка умножения матриц через NumPy."
    )

    parser.add_argument(
        "side",
        nargs="?",
        type=int,
        default=None,
        help=(
            "Количество элементов в строке, то есть сторона квадратной матрицы. "
            "Например, для матрицы 20x20 нужно передать 20."
        ),
    )

    parser.add_argument(
        "--a",
        type=Path,
        default=None,
        help="Путь к матрице A",
    )

    parser.add_argument(
        "--b",
        type=Path,
        default=None,
        help="Путь к матрице B",
    )

    parser.add_argument(
        "--c",
        type=Path,
        default=None,
        help="Путь к результату C из C++ программы",
    )

    args = parser.parse_args()

    expected_side = None
    if args.side is not None:
        expected_side = args.side

        if args.a is None:
            args.a = ROOT / "extra" / "matrices" / f"A_{expected_side}.txt"

        if args.b is None:
            args.b = ROOT / "extra" / "matrices" / f"B_{expected_side}.txt"

        if args.c is None:
            args.c = ROOT / "extra" / "res" / f"C_{expected_side}.txt"
    else:
        if args.a is None or args.b is None or args.c is None:
            parser.error("Укажите side или все пути --a --b --c")

    A = read_matrix(args.a, reported=False, expected_side=expected_side)
    B = read_matrix(args.b, reported=False, expected_side=expected_side)
    C = read_matrix(args.c, reported=True, expected_side=expected_side)

    if A.shape != B.shape:
        print("FAIL: размеры A и B не совпадают", file=sys.stderr)
        return 1

    if C.shape != A.shape:
        print("FAIL: размер C не совпадает с A/B", file=sys.stderr)
        return 1

    side = A.shape[0]
    size = A.size

    C_ref = A @ B

    ok = bool(np.array_equal(C, C_ref))

    report = read_report(args.c)

    print(f"side = {side}")
    print(f"size = {size}")

    if "time_seconds" in report:
        print(f"time_seconds = {report['time_seconds']}")

    if "time_ms" in report:
        print(f"time_ms = {report['time_ms']}")

    if "integer_operations" in report:
        print(f"integer_operations = {report['integer_operations']}")

    if "memory_bytes" in report:
        print(f"memory_bytes = {report['memory_bytes']}")

    if "gops" in report:
        print(f"gops = {report['gops']}")

    print("OK" if ok else "FAIL")

    if not ok:
        diff = np.abs(C - C_ref)
        max_abs = int(diff.max()) if diff.size else 0
        bad_count = int(np.count_nonzero(diff))

        print(f"max_abs_error = {max_abs}")
        print(f"bad_elements = {bad_count}")

    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)