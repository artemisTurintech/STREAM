param(
    [int]$ArraySize = 10000000,
    [int]$NTimes = 10
)

$output = "stream_c.exe"
$flags = @("-O2", "-fopenmp", "-DSTREAM_ARRAY_SIZE=$ArraySize", "-DNTIMES=$NTimes")

Write-Host "Compiling STREAM benchmark (C)..."
Write-Host "  Array size : $ArraySize elements"
Write-Host "  Iterations : $NTimes"

& gcc @flags stream.c -o $output
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed."
    exit 1
}

Write-Host "Done: $output"
