Set-StrictMode -Version Latest

function Get-CgxRepositoryRoot {
    param([Parameter(Mandatory = $true)][string]$ScriptDirectory)
    return (Resolve-Path (Join-Path $ScriptDirectory "..")).Path
}

function Get-CgxGitCommand {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        $command = Get-Command git -ErrorAction SilentlyContinue
    }
    if ($null -eq $command) {
        throw "Git was not found."
    }
    return $command.Source
}

function ConvertTo-CgxNativeArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }
        if ($character -eq '"') {
            if ($backslashCount -gt 0) {
                [void]$builder.Append((('\' * ($backslashCount * 2)) -join ''))
                $backslashCount = 0
            }
            [void]$builder.Append('\"')
            continue
        }
        if ($backslashCount -gt 0) {
            [void]$builder.Append((('\' * $backslashCount) -join ''))
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashCount -gt 0) {
        [void]$builder.Append((('\' * ($backslashCount * 2)) -join ''))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-CgxNativeArgumentString {
    param([string[]]$Arguments = @())
    return (@($Arguments | ForEach-Object { ConvertTo-CgxNativeArgument -Value ([string]$_) }) -join ' ')
}

function Invoke-CgxExpectedFailure {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [int]$TimeoutMilliseconds = 120000
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ConvertTo-CgxNativeArgumentString -Arguments $Arguments
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Process failed to start: $FilePath"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try { $process.Kill() } catch { }
            throw "Expected-failure probe exceeded timeout ${TimeoutMilliseconds}ms."
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Stdout = $stdoutTask.GetAwaiter().GetResult()
            Stderr = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-CgxCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Write-Host ""
    Write-Host "==> $Label"
    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "$Label failed with exit code $exitCode."
        }
    }
    finally {
        Pop-Location
    }
}
