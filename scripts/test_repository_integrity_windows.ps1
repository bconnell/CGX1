Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "cgx_script_common.ps1")
$repoRoot = Get-CgxRepositoryRoot -ScriptDirectory $PSScriptRoot
$checkScript = Join-Path $repoRoot "scripts\check_repository_integrity.ps1"
$probePath = Join-Path $repoRoot (".cgx-integrity-probe-$PID.md")

if (Test-Path -LiteralPath $probePath) { throw "Probe path already exists: $probePath" }
try {
    [IO.File]::WriteAllText($probePath, "<<<<<<< invalid`nprobe`n=======`nother`n>>>>>>> invalid`n")
    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $checkScript) `
        -WorkingDirectory $repoRoot
    if ($result.ExitCode -eq 0) { throw "Repository integrity gate accepted a merge-conflict regression probe." }
    $output = ([string]$result.Stdout) + [Environment]::NewLine + ([string]$result.Stderr)
    if ($output -notmatch "merge conflict marker") { throw "Repository integrity gate did not report the expected finding." }
    Write-Host "[pass] Repository integrity negative control was rejected."
}
finally {
    if (Test-Path -LiteralPath $probePath -PathType Leaf) { Remove-Item -LiteralPath $probePath -Force }
}
