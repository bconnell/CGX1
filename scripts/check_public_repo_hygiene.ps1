param(
    [string]$CandidateCommitSubject = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
if ($null -eq $git) { throw "Git was not found." }

function Convert-CodePoints {
    param([int[]]$Values)
    return -join @($Values | ForEach-Object { [char]$_ })
}

function New-WholeWordRule {
    param(
        [string]$Name,
        [int[]]$CodePoints,
        [bool]$CaseSensitive = $false
    )

    $token = Convert-CodePoints $CodePoints
    $escaped = [Regex]::Escape($token)
    $pattern = "(?<![A-Za-z0-9])$escaped(?![A-Za-z0-9])"
    $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    if (-not $CaseSensitive) {
        $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    }

    return [pscustomobject]@{
        Name = $Name
        Pattern = $pattern
        Options = $options
    }
}

$rules = @(
    New-WholeWordRule "unfinished public wording" @(112,108,97,99,101,104,111,108,100,101,114)
    New-WholeWordRule "private development wording 1" @(97,103,101,110,116,105,99,32,119,111,114,107,101,114,115)
    New-WholeWordRule "private development wording 2" @(115,117,98,97,103,101,110,116,45,100,114,105,118,101,110,45,100,101,118,101,108,111,112,109,101,110,116)
    New-WholeWordRule "private development wording 3" @(97,103,101,110,116,45,114,111,108,101,32,108,97,110,103,117,97,103,101)
    New-WholeWordRule "private development wording 4" @(112,114,105,118,97,116,101,32,112,114,111,109,112,116,115)
    New-WholeWordRule "internal tool reference 2" @(67,104,97,116,71,80,84)
    New-WholeWordRule "internal tool reference 3" @(67,111,100,101,120)
    New-WholeWordRule "internal tool reference 4" @(79,112,101,110,65,73)
    New-WholeWordRule "internal tool reference 7" @(99,111,100,105,110,103,32,97,103,101,110,116)
    New-WholeWordRule "internal tool reference 8" @(103,101,110,101,114,97,116,101,100,32,98,121)
    New-WholeWordRule "private workflow wording 1" @(114,101,112,97,105,114,32,98,97,116,99,104)
    New-WholeWordRule "private workflow wording 2" @(99,111,110,116,105,110,117,97,116,105,111,110,32,112,97,99,107,97,103,101)
    New-WholeWordRule "private workflow wording 3" @(115,111,117,114,99,101,32,102,105,110,103,101,114,112,114,105,110,116)
    New-WholeWordRule "private workflow wording 4" @(99,111,109,112,108,101,116,105,111,110,32,104,97,110,100,111,102,102)
    New-WholeWordRule "private workflow wording 5" @(102,97,105,108,117,114,101,32,104,97,110,100,111,102,102)
    New-WholeWordRule "private workflow wording 6" @(112,114,111,109,112,116,32,119,111,114,107,102,108,111,119)
    New-WholeWordRule "private workflow wording 7" @(99,104,97,105,110,32,111,102,32,116,104,111,117,103,104,116)
    New-WholeWordRule "private governance wording" @(71,111,108,100,32,83,116,97,110,100,97,114,100)
    New-WholeWordRule "unrelated project wording" @(72,101,110,107,97)
    New-WholeWordRule "personal host wording 1" @(73,100,101,97,67,101,110,116,114,101,32,53,49,48,83)
    New-WholeWordRule "personal host wording 2" @(83,117,101,118,101,114,121)
    New-WholeWordRule "personal host wording 3" @(99,108,111,110,101,100,32,102,114,111,109,32,97,110,32,111,108,100,101,114,32,115,121,115,116,101,109)
    New-WholeWordRule "promotional wording 1" @(103,97,109,101,45,99,104,97,110,103,105,110,103)
    New-WholeWordRule "promotional wording 2" @(114,101,118,111,108,117,116,105,111,110,97,114,121)
    New-WholeWordRule "promotional wording 3" @(117,110,112,97,114,97,108,108,101,108,101,100)
    New-WholeWordRule "promotional wording 4" @(103,114,111,117,110,100,98,114,101,97,107,105,110,103)
    New-WholeWordRule "promotional wording 5" @(99,117,116,116,105,110,103,45,101,100,103,101)
    New-WholeWordRule "promotional wording 6" @(100,101,108,118,101,32,105,110,116,111)
    New-WholeWordRule "promotional wording 7" @(105,116,32,105,115,32,119,111,114,116,104,32,110,111,116,105,110,103)
)

$textExtensions = @(
    ".c", ".h", ".cpp", ".hpp", ".sv", ".scad", ".md", ".txt", ".ps1",
    ".yml", ".yaml", ".json", ".svg", ".gitignore", ".gitattributes", ".editorconfig", ".cff"
)

$paths = @(& $git.Source -C $repoRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate repository files." }

$findings = New-Object System.Collections.Generic.List[string]
foreach ($rawPath in $paths) {
    $relativePath = ([string]$rawPath).Trim().Replace("\", "/")
    if ([string]::IsNullOrWhiteSpace($relativePath) -or $relativePath.StartsWith("third_party/", [StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $fileName = [IO.Path]::GetFileName($relativePath)
    $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
    $isText = $extension -in $textExtensions -or $fileName -in @("CMakeLists.txt", "LICENSE")
    if (-not $isText) { continue }

    $absolutePath = Join-Path $repoRoot ($relativePath.Replace("/", "\"))
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) { continue }

    $bytes = [IO.File]::ReadAllBytes($absolutePath)
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { continue }

    $text = [IO.File]::ReadAllText($absolutePath)

    foreach ($rule in $rules) {
        if ([Regex]::IsMatch($text, $rule.Pattern, $rule.Options)) {
            $findings.Add("$($relativePath): $($rule.Name)")
        }
    }

    $windowsUserPattern = '[A-Za-z]:\\Users\\[^\\\r\n\t ]+'
    $unixHomePattern = '/home/[A-Za-z0-9._-]+(?:/|$)'
    $sandboxPrefix = Convert-CodePoints @(47,109,110,116,47,100,97,116,97,47)

    if ($text -match $windowsUserPattern) { $findings.Add("$($relativePath): private Windows user path") }
    if ($text -match $unixHomePattern) { $findings.Add("$($relativePath): private Unix home path") }
    if ($text.IndexOf($sandboxPrefix, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $findings.Add("$($relativePath): local sandbox path") }
}

$subjects = New-Object System.Collections.Generic.List[string]
$currentSubject = @(& $git.Source -C $repoRoot log -1 --pretty=%s 2>$null)
if ($LASTEXITCODE -eq 0 -and $currentSubject.Count -gt 0) {
    $subjects.Add(([string]$currentSubject[0]).Trim())
}
if (-not [string]::IsNullOrWhiteSpace($CandidateCommitSubject)) {
    $subjects.Add($CandidateCommitSubject)
}

foreach ($subject in $subjects) {
    foreach ($rule in $rules) {
        if ([Regex]::IsMatch($subject, $rule.Pattern, $rule.Options)) {
            $findings.Add("commit subject: $($rule.Name)")
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Host "Public repository hygiene check failed:"
    $findings | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "[pass] Public repository hygiene check passed."
