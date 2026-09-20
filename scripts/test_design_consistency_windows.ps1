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
    if ($result.ExitCode -eq 0) { throw "Design consistency gate accepted a deliberately inconsistent architecture file." }
    if ((([string]$result.Stdout) + ([string]$result.Stderr)) -notmatch "expected value is missing") {
        throw "Design consistency negative control did not report a mismatch."
    }
    Write-Host "[pass] Design consistency negative control was rejected."
}
finally {
    if (Test-Path -LiteralPath $probePath -PathType Leaf) { Remove-Item -LiteralPath $probePath -Force }
}
