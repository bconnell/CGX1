Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "cgx_script_common.ps1")
$repoRoot = Get-CgxRepositoryRoot -ScriptDirectory $PSScriptRoot
$git = Get-CgxGitCommand

$paths = @(& $git -C $repoRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate source files." }
$normalized = @($paths | ForEach-Object { ([string]$_).Trim().Replace("\", "/") } | Sort-Object -Unique)
$builder = New-Object System.Text.StringBuilder
foreach ($relativePath in $normalized) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
    $absolutePath = Join-Path $repoRoot ($relativePath.Replace("/", "\"))
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) { throw "Source file disappeared during hashing: $relativePath" }
    $hash = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [void]$builder.Append($relativePath)
    [void]$builder.Append("`0")
    [void]$builder.Append($hash)
    [void]$builder.Append("`0")
}
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($builder.ToString()))
} finally {
    $sha.Dispose()
}
$identity = -join ($digest | ForEach-Object { $_.ToString("x2") })
$head = @(& $git -C $repoRoot rev-parse HEAD 2>$null)
$commit = if ($LASTEXITCODE -eq 0 -and $head.Count -eq 1) { ([string]$head[0]).Trim() } else { "uncommitted" }
$status = @(& $git -C $repoRoot status --porcelain=v1 --untracked-files=all)
$state = if ($status.Count -eq 0) { "clean" } else { "working-tree" }
Write-Host "commit=$commit"
Write-Host "source_state=$state"
Write-Host "source_identity=$identity"
