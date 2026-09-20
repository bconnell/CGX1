Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "cgx_script_common.ps1")
$repoRoot = Get-CgxRepositoryRoot -ScriptDirectory $PSScriptRoot
$hygieneScript = Join-Path $repoRoot "scripts\check_public_repo_hygiene.ps1"

function Convert-CodePoints {
    param([int[]]$Values)
    return -join @($Values | ForEach-Object { [char]$_ })
}

$cases = @(
    [pscustomobject]@{ Name = "private-development"; RuleName = "private development wording 4"; Text = Convert-CodePoints @(112, 114, 105, 118, 97, 116, 101, 32, 112, 114, 111, 109, 112, 116, 115) }
    [pscustomobject]@{ Name = "tool-reference"; RuleName = "internal tool reference 2"; Text = Convert-CodePoints @(67, 104, 97, 116, 71, 80, 84) }
    [pscustomobject]@{ Name = "promotional-style"; RuleName = "promotional wording 1"; Text = Convert-CodePoints @(103, 97, 109, 101, 45, 99, 104, 97, 110, 103, 105, 110, 103) }
    [pscustomobject]@{ Name = "personal-host"; RuleName = "personal host wording 2"; Text = Convert-CodePoints @(83, 117, 101, 118, 101, 114, 121) }
    [pscustomobject]@{ Name = "sandbox-path"; RuleName = "local sandbox path"; Text = Convert-CodePoints @(47, 109, 110, 116, 47, 100, 97, 116, 97, 47, 116, 101, 115, 116, 46, 116, 120, 116) }
)

$paths = @()
try {
    foreach ($case in $cases) {
        $path = Join-Path $repoRoot (".cgx-hygiene-probe-$PID-" + $case.Name + ".md")
        if (Test-Path -LiteralPath $path) { throw "Probe path already exists: $path" }
        [IO.File]::WriteAllText($path, $case.Text)
        $paths += $path
    }

    $result = Invoke-CgxExpectedFailure `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $hygieneScript) `
        -WorkingDirectory $repoRoot

    if ($result.ExitCode -eq 0) {
        throw "The public repository hygiene gate accepted the invalid regression probes."
    }

    $output = ([string]$result.Stdout) + [Environment]::NewLine + ([string]$result.Stderr)
    foreach ($case in $cases) {
        if ($output -notmatch [Regex]::Escape($case.RuleName)) {
            throw "Expected hygiene finding was not reported for $($case.Name)."
        }
    }

    Write-Host "[pass] Public repository hygiene negative controls were rejected."
}
finally {
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}
