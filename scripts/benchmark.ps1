param(
    [int]$Runs      = 1,
    [int]$ArraySize = 10000000,
    [int]$NTimes    = 10,
    [int]$Threads   = 0
)

$root        = "$PSScriptRoot\.."
$source      = "$root\stream.c"
$binary      = "$root\stream_c.exe"
$resultsFile = "$root\artemis_results.json"

# ── Compile ───────────────────────────────────────────────────────────────────
Write-Host "Compiling..."
& gcc -O2 -fopenmp "-DSTREAM_ARRAY_SIZE=$ArraySize" "-DNTIMES=$NTimes" $source -o $binary
if ($LASTEXITCODE -ne 0) { Write-Error "Compilation failed."; exit 1 }

if ($Threads -gt 0) {
    $env:OMP_NUM_THREADS = "$Threads"
    Write-Host "Threads: $Threads (OMP_NUM_THREADS)"
}

# ── Collect runs ──────────────────────────────────────────────────────────────
$kernels = @("Copy", "Scale", "Add", "Triad")
$samples = @{}
foreach ($k in $kernels) { $samples[$k] = [System.Collections.Generic.List[double]]::new() }
$runResults = [System.Collections.Generic.List[hashtable]]::new()

Write-Host "Running $Runs run(s)..."
for ($i = 1; $i -le $Runs; $i++) {
    Write-Host "  Run $i / $Runs ..." -NoNewline
    $out = & $binary 2>&1 | Out-String

    $runRow = @{}
    foreach ($k in $kernels) {
        if ($out -match "${k}:\s+([\d.]+)") {
            $val = [math]::Round([double]$Matches[1], 2)
            $samples[$k].Add($val)
            $runRow["${k}_MB_s"] = $val
        }
    }
    $runResults.Add($runRow)
    Write-Host " done"
}

if ($Threads -gt 0) { Remove-Item Env:OMP_NUM_THREADS -ErrorAction SilentlyContinue }

# ── Stats (mean + sample std dev) ────────────────────────────────────────────
function Get-Stats([System.Collections.Generic.List[double]]$values) {
    $n    = $values.Count
    $mean = ($values | Measure-Object -Sum).Sum / $n
    $std  = 0.0
    if ($n -gt 1) {
        $ss  = ($values | ForEach-Object { [math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum
        $std = [math]::Sqrt($ss / ($n - 1))
    }
    return [pscustomobject]@{ mean = [math]::Round($mean, 2); std = [math]::Round($std, 2) }
}

# ── Print results ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("  {0,-10} {1,14}  {2,14}  {3}" -f "Kernel", "Mean (MB/s)", "Std (MB/s)", "Unit")
Write-Host ("  " + "-" * 50)

$metrics = @{}
foreach ($k in $kernels) {
    $s = Get-Stats $samples[$k]
    $metrics[$k] = $s
    Write-Host ("  {0,-10} {1,14:F2}  {2,14:F2}  MB/s" -f "${k}:", $s.mean, $s.std)
}

Write-Host ("  " + "-" * 50)
Write-Host "  Runs=$Runs"

# ── Write artemis_results.json ────────────────────────────────────────────────
# Single-row array: one object with mean and std per metric.
$summary = [ordered]@{}
foreach ($k in $kernels) {
    $s = Get-Stats $samples[$k]
    $summary["${k}_MB_s_mean"] = $s.mean
    $summary["${k}_MB_s_std"]  = $s.std
}

$json      = "[" + ($summary | ConvertTo-Json -Depth 2) + "]"
$utf8NoBOM = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($resultsFile, $json, $utf8NoBOM)
Write-Host ""
Write-Host "Results written to $resultsFile"
