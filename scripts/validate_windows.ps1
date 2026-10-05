param([switch]$CleanCandidate, [switch]$DeferCmakeToUnprivilegedWsl)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "cgx_script_common.ps1")
$repoRoot = Get-CgxRepositoryRoot -ScriptDirectory $PSScriptRoot

try {
    $systemDrive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($repoRoot).Substring(0,1)) -ErrorAction SilentlyContinue
    if ($null -ne $systemDrive -and $null -ne $systemDrive.Free) {
        $freeGb = [Math]::Round($systemDrive.Free / 1GB, 2)
        Write-Host "Repository volume free space: $freeGb GB"
        if ($systemDrive.Free -lt 2GB) { throw "Less than 2 GB is free on the repository volume." }
    }

    if (-not $CleanCandidate) {
        $candidateArguments = @("-3", "scripts/validate_clean_candidate.py", "--root", $repoRoot)
        if ($env:GITHUB_ACTIONS -eq "true") {
            # The required RTL CI job validates this same pushed SHA in a clean Linux checkout.
            $candidateArguments += "--skip-rtl"
        }
        Invoke-CgxCommand -FilePath "py.exe" -Arguments $candidateArguments -WorkingDirectory $repoRoot -Label "Validate staged candidate in a clean exact-tree worktree"
        Write-Host ""
        Write-Host "[pass] CGX 1 Windows validation completed on the clean candidate."
        exit 0
    }

    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\check_public_repo_hygiene.ps1")) -WorkingDirectory $repoRoot -Label "Check public repository hygiene"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\test_public_repo_hygiene_windows.ps1")) -WorkingDirectory $repoRoot -Label "Test public repository hygiene negative controls"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\check_repository_integrity.ps1")) -WorkingDirectory $repoRoot -Label "Check repository integrity"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\test_repository_integrity_windows.ps1")) -WorkingDirectory $repoRoot -Label "Test repository integrity negative control"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\check_design_consistency.ps1")) -WorkingDirectory $repoRoot -Label "Check shared design consistency"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\test_design_consistency_windows.ps1")) -WorkingDirectory $repoRoot -Label "Test design consistency negative control"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\check_markdown_links.ps1")) -WorkingDirectory $repoRoot -Label "Check local Markdown links"
    Invoke-CgxCommand -FilePath "py.exe" -Arguments @("-3", "-m", "unittest", "discover", "-s", "scripts/tests", "-v") -WorkingDirectory $repoRoot -Label "Run validation-tool tests"
    Invoke-CgxCommand -FilePath "py.exe" -Arguments @("-3", "scripts/validate_resource_limits.py") -WorkingDirectory $repoRoot -Label "Validate classified resource limits and boundary references"
    Invoke-CgxCommand -FilePath "py.exe" -Arguments @("-3", "scripts/validate_hardening_ledgers.py") -WorkingDirectory $repoRoot -Label "Validate escaped-defect and lifecycle fault-injection ledgers"
    Invoke-CgxCommand -FilePath "py.exe" -Arguments @("-3", "scripts/validate_rtl_inventory.py") -WorkingDirectory $repoRoot -Label "Validate complete bounded RTL compile/run inventory"
    Invoke-CgxCommand -FilePath "py.exe" -Arguments @("-3", "scripts/validate_randomized_tests.py") -WorkingDirectory $repoRoot -Label "Require deterministic randomized-test diagnostics"
    Invoke-CgxCommand -FilePath "py.exe" -Arguments @("-3", "scripts/check_branch_state.py", "--root", $repoRoot, "--max-unpublished", "3") -WorkingDirectory $repoRoot -Label "Report completeness-branch and hosted evidence state"
    Invoke-CgxCommand -FilePath "py.exe" -Arguments @("-3", "scripts/check_release_test_checks.py") -WorkingDirectory $repoRoot -Label "Reject NDEBUG-sensitive test assertions"
    $cmake = Get-Command "cmake.exe" -ErrorAction SilentlyContinue
    if ($null -eq $cmake) { $cmake = Get-Command "cmake" -ErrorAction SilentlyContinue }
    if ($null -eq $cmake) {
        if (-not $DeferCmakeToUnprivilegedWsl -or $env:GITHUB_ACTIONS -eq "true") {
            throw "CMake is unavailable to Windows validation and no local unprivileged WSL handoff was authorized."
        }
        Write-Host "[deferred] Release/NDEBUG failure proof and clean Debug/Release CTest will run on this exact candidate in unprivileged WSL."
    }
    else {
        Invoke-CgxCommand -FilePath "py.exe" -Arguments @("-3", "scripts/run_clean_cmake_tests.py", "--root", $repoRoot, "--config", "both", "--jobs", "2", "--budget-seconds", "900", "--summary-json", "build/cgx1-clean-validation-summary.json") -WorkingDirectory $repoRoot -Label "Fresh Debug and Release build plus CTest"
        Invoke-CgxCommand -FilePath "py.exe" -Arguments @("-3", "scripts/prove_release_test_check_failure.py", "--root", $repoRoot) -WorkingDirectory $repoRoot -Label "Prove Release test expectations remain active"
    }
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\get_source_identity.ps1")) -WorkingDirectory $repoRoot -Label "Report source identity"

    Write-Host ""
    Write-Host "[pass] CGX 1 Windows validation completed."
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
