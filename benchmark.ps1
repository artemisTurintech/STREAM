param(
    [int]$ArraySize = 10000000,
    [int]$NTimes = 10,
    [int]$Threads = 0
)

$binary = "stream_c.exe"

Write-Host "Compiling..."
& gcc -O2 -fopenmp "-DSTREAM_ARRAY_SIZE=$ArraySize" "-DNTIMES=$NTimes" stream.c -o $binary
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed."
    exit 1
}

if ($Threads -gt 0) {
    $env:OMP_NUM_THREADS = "$Threads"
    Write-Host "Threads: $Threads (OMP_NUM_THREADS)"
}

Write-Host ""
& ".\$binary"

if ($Threads -gt 0) {
    Remove-Item Env:OMP_NUM_THREADS -ErrorAction SilentlyContinue
}
