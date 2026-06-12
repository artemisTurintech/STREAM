param(
    [int]$ArraySize = 10000000,
    [int]$NTimes = 10
)

$root   = "$PSScriptRoot\.."
$source = "$root\stream.c"
$binary = "$root\stream_c.exe"

Write-Host "Compiling..."
& gcc -O2 -fopenmp "-DSTREAM_ARRAY_SIZE=$ArraySize" "-DNTIMES=$NTimes" $source -o $binary
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed."
    exit 1
}

Write-Host "Running validation..."
$output = & $binary 2>&1
$output | Write-Host

if ($output -match "Solution Validates") {
    Write-Host ""
    Write-Host "PASS: Solution validates."
    exit 0
} else {
    Write-Error "FAIL: Validation not found in output."
    exit 1
}
