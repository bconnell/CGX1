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
    $architecture.matrix_engine.pipeline.issue_interval_cycles = 15
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted a deliberately invalid matrix issue interval." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "matrix issue interval must remain 16 cycles") {
        throw "Matrix design consistency negative control did not report the expected invariant."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.matrix_engine.pipeline.wave_register_reads_per_capture_cycle = 1
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted an invalid matrix VGPR read-port budget." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "matrix VGPR interface must remain two 1024-bit reads") {
        throw "Matrix VGPR interface negative control did not report the expected invariant."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.matrix_engine.register_banking.source_b_base_modulo_8 = 0
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted an invalid matrix bank-class contract." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "matrix register bank classes must remain modulo-8") {
        throw "Matrix bank-class negative control did not report the expected invariant."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.matrix_engine.matrix_to_matrix_dependencies.pending_destination_raw_interlock = $false
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted a disabled matrix RAW interlock." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "matrix RAW interlock against pending destinations must remain enabled") {
        throw "Matrix dependency-interlock negative control did not report the expected invariant."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.matrix_engine.matrix_to_matrix_dependencies.ordinary_vector_source_write_interlock_implemented = $false
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted a disabled ordinary vector WAR interlock." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "ordinary vector WAR interlock logic must remain implemented") {
        throw "Matrix per-wave scoreboard negative control did not report the expected invariant."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.matrix_engine.staging_storage.active_execution_operand_bytes = 1024
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted an invalid matrix active operand storage size." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "matrix logical staging storage must remain 2048/2048/1024 bytes") {
        throw "Matrix staging-storage negative control did not report the expected invariant."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.matrix_engine.staging_storage.output_result_staging_rtl_implemented = $false
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted disabled matrix output-result staging." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "matrix output-result staging RTL must remain implemented") {
        throw "Matrix output-result staging negative control did not report the expected invariant."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.matrix_engine.arithmetic_rtl.fp16_rtl_implemented = $true
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted unsupported floating matrix arithmetic RTL." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "floating matrix arithmetic must remain unimplemented") {
        throw "Matrix INT8-only arithmetic negative control did not report the expected invariant."
    }

    $architecture = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    $architecture.matrix_engine.int8_path_integration.cycle0_result_bypass_required = $false
    $architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probePath -Encoding UTF8

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript, "-ArchitecturePath", $probePath) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted an integrated INT8 path without the cycle-0 bypass." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "integrated signed INT8 path contract is incomplete") {
        throw "Integrated INT8 path negative control did not report the expected invariant."
    }

    Write-Host "[pass] Design consistency negative controls were rejected."
}
finally {
    if (Test-Path -LiteralPath $probePath -PathType Leaf) { Remove-Item -LiteralPath $probePath -Force }
}
