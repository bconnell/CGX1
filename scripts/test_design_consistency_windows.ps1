Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "cgx_script_common.ps1")
$repoRoot = Get-CgxRepositoryRoot -ScriptDirectory $PSScriptRoot
$checkScript = Join-Path $repoRoot "scripts\check_design_consistency.ps1"
$sourcePath = Join-Path $repoRoot "design\cgx1_architecture.json"
$probePath = Join-Path ([IO.Path]::GetTempPath()) ("cgx1-architecture-probe-" + [Guid]::NewGuid().ToString("N") + ".json")

try {
    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.mechanical_mm.length = 168.0
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted a deliberately inconsistent mechanical target." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "expected value is missing") {
        throw "Mechanical design consistency negative control did not report a mismatch."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.power_management.fixed_active_tile_count_by_board_state = $true
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted a deliberately invalid power-management contract." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "must not encode a fixed active tile count") {
        throw "Power-management design consistency negative control did not report the expected invariant."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.matrix_engine.throughput_frozen = $true
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted a deliberately invalid matrix-throughput claim." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "matrix throughput must remain unfrozen") {
        throw "Matrix design consistency negative control did not report the expected invariant."
    }

    Write-Host "[pass] Design consistency negative controls were rejected."
}
finally {
    if (Test-Path -LiteralPath $probePath -PathType Leaf) { Remove-Item -LiteralPath $probePath -Force }
}
