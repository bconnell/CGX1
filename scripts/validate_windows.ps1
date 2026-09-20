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

    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\check_public_repo_hygiene.ps1")) -WorkingDirectory $repoRoot -Label "Check public repository hygiene"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\test_public_repo_hygiene_windows.ps1")) -WorkingDirectory $repoRoot -Label "Test public repository hygiene negative controls"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\check_repository_integrity.ps1")) -WorkingDirectory $repoRoot -Label "Check repository integrity"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\test_repository_integrity_windows.ps1")) -WorkingDirectory $repoRoot -Label "Test repository integrity negative control"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\check_design_consistency.ps1")) -WorkingDirectory $repoRoot -Label "Check shared design consistency"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\test_design_consistency_windows.ps1")) -WorkingDirectory $repoRoot -Label "Test design consistency negative control"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\check_markdown_links.ps1")) -WorkingDirectory $repoRoot -Label "Check local Markdown links"

    $buildPath = Join-Path $repoRoot "build"
    Invoke-CgxCommand -FilePath "cmake.exe" -Arguments @("-S", $repoRoot, "-B", $buildPath) -WorkingDirectory $repoRoot -Label "Configure C and C++ build"
    Invoke-CgxCommand -FilePath "cmake.exe" -Arguments @("--build", $buildPath, "--config", "Release") -WorkingDirectory $repoRoot -Label "Build analytical model and firmware tests"
    Invoke-CgxCommand -FilePath "ctest.exe" -Arguments @("--test-dir", $buildPath, "--output-on-failure", "-C", "Release") -WorkingDirectory $repoRoot -Label "Run executable tests"
    Invoke-CgxCommand -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $repoRoot "scripts\get_source_identity.ps1")) -WorkingDirectory $repoRoot -Label "Report source identity"

    Write-Host ""
    Write-Host "[pass] CGX 1 Windows validation completed."
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
