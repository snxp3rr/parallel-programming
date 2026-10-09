$exe = ".\build_cuda\lab_4\Release\lab4_cuda.exe"

$sides = 200, 400, 800, 1200, 1600, 2000
$tiles = 8, 16, 32
$runs = 3

"side`ttile`tkernel`tavg_time_s`tGOPS`tspeedup"

foreach ($side in $sides) {
    $baseFile = "extra\res\lab_1\C_$side.txt"

    if (-not (Test-Path $baseFile)) {
        throw "Не найден baseline файл: $baseFile"
    }

    $baselineLine = (Select-String -Path $baseFile -Pattern '^time_seconds=').Line
    $baseline = [double]($baselineLine.Split('=')[1])

    foreach ($tile in $tiles) {
        $sumTime = 0.0
        $sumGops = 0.0
        $sumSpeed = 0.0

        for ($r = 1; $r -le $runs; $r++) {
            & $exe $side $tile $baseline --tiled | Out-Null

            $outFile = "extra\res\lab_4\C_${side}_tiled_t${tile}.txt"

            $timeLine = (Select-String -Path $outFile -Pattern '^time_seconds=').Line
            $gopsLine = (Select-String -Path $outFile -Pattern '^gops=').Line
            $speedLine = (Select-String -Path $outFile -Pattern '^speedup_vs_sequential=').Line

            $time = [double]($timeLine.Split('=')[1])
            $gops = [double]($gopsLine.Split('=')[1])
            $speed = [double]($speedLine.Split('=')[1])

            $sumTime += $time
            $sumGops += $gops
            $sumSpeed += $speed
        }

        $avgTime = $sumTime / $runs
        $avgGops = $sumGops / $runs
        $avgSpeed = $sumSpeed / $runs

        "{0}`t{1}`t{2}`t{3:N9}`t{4:N6}`t{5:N6}" -f `
            $side, $tile, "tiled", $avgTime, $avgGops, $avgSpeed
    }
}