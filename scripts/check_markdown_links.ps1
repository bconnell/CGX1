Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
if ($null -eq $git) { throw "Git was not found." }
$paths = @(& $git.Source -C $repoRoot ls-files --cached --others --exclude-standard "*.md")
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate Markdown files." }
$findings = New-Object System.Collections.Generic.List[string]

foreach ($rawPath in $paths) {
    $relativePath = ([string]$rawPath).Trim().Replace("\", "/")
    $absolutePath = Join-Path $repoRoot ($relativePath.Replace("/", "\"))
    $text = [IO.File]::ReadAllText($absolutePath)
    foreach ($match in [Regex]::Matches($text, '\[[^\]]+\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value.Trim()
        if ($target -match '^(https?://|mailto:|#)') { continue }
        $targetWithoutAnchor = ($target -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($targetWithoutAnchor)) { continue }
        $decoded = [Uri]::UnescapeDataString($targetWithoutAnchor)
        $baseDirectory = Split-Path -Parent $absolutePath
        $resolved = [IO.Path]::GetFullPath((Join-Path $baseDirectory ($decoded.Replace('/', '\'))))
        if (-not $resolved.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $findings.Add("${relativePath}: local link escapes repository: $target")
            continue
        }
        if (-not (Test-Path -LiteralPath $resolved)) {
            $findings.Add("${relativePath}: broken local link: $target")
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Host "Markdown link check failed:"
    $findings | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "[pass] Local Markdown links passed."
