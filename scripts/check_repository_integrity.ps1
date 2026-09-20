Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "cgx_script_common.ps1")
$repoRoot = Get-CgxRepositoryRoot -ScriptDirectory $PSScriptRoot
$git = Get-CgxGitCommand
$findings = New-Object System.Collections.Generic.List[string]

function Add-Finding { param([string]$Message) $findings.Add($Message) }
function Convert-CodePoints { param([int[]]$Values) return -join @($Values | ForEach-Object { [char]$_ }) }

$paths = @(& $git -C $repoRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate repository files." }
$paths = @($paths | ForEach-Object { ([string]$_).Trim().Replace("\", "/") })

$forbiddenRoots = @("build/", "out/", ".vs/", "Testing/", "CMakeFiles/", "_deps/", "scratch/", "evidence/")
$forbiddenExtensions = @(
    ".exe", ".dll", ".lib", ".obj", ".o", ".pdb", ".ilk", ".log", ".tmp", ".temp", ".cache", ".bak", ".orig",
    ".pfx", ".p12", ".pem", ".key", ".snk", ".docx", ".pdf", ".zip", ".7z", ".rar"
)

$textExtensions = @(".c", ".h", ".cpp", ".hpp", ".sv", ".scad", ".md", ".txt", ".ps1", ".yml", ".yaml", ".json", ".svg", ".cff")
$privateKeyPattern = Convert-CodePoints @(45,45,45,45,45,66,69,71,73,78,32,40,82,83,65,124,69,67,124,79,80,69,78,83,83,72,124,80,82,73,86,65,84,69,41,63,32,80,82,73,86,65,84,69,32,75,69,89,45,45,45,45,45)
$classicTokenPrefix = Convert-CodePoints @(103,104,112,95)
$fineTokenPrefix = Convert-CodePoints @(103,105,116,104,117,98,95,112,97,116,95)
$cloudAccessPrefix = Convert-CodePoints @(65,75,73,65)
$secretAssignmentPattern = '(?i)\b(password|secret|api[_-]?key|access[_-]?token)\s*[:=]\s*["'']?[A-Za-z0-9+/=_-]{16,}'

foreach ($relativePath in $paths) {
    foreach ($root in $forbiddenRoots) {
        if ($relativePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            Add-Finding "${relativePath}: generated or local-only path is visible to Git"
        }
    }

    $fileName = [IO.Path]::GetFileName($relativePath)
    $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
    if ($fileName -eq ".env" -or $fileName.StartsWith(".env.", [StringComparison]::OrdinalIgnoreCase)) {
        Add-Finding "${relativePath}: local environment file is visible to Git"
    }
    if ($extension -in $forbiddenExtensions) {
        Add-Finding "${relativePath}: forbidden generated, private, office, or archive extension"
    }

    $absolutePath = Join-Path $repoRoot ($relativePath.Replace("/", "\"))
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        Add-Finding "${relativePath}: Git-visible path is missing from the checkout"
        continue
    }

    if ((Get-Item -LiteralPath $absolutePath).Length -gt 10MB -and -not $relativePath.StartsWith("mechanical/", [StringComparison]::OrdinalIgnoreCase)) {
        Add-Finding "${relativePath}: first-party file exceeds 10 MiB outside the intentional mechanical artifact path"
    }

    $isText = $extension -in $textExtensions -or $fileName -in @("CMakeLists.txt", "LICENSE", ".gitignore", ".gitattributes", ".editorconfig")
    if (-not $isText) { continue }
    $bytes = [IO.File]::ReadAllBytes($absolutePath)
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { continue }
    $text = [IO.File]::ReadAllText($absolutePath)
    $lines = [IO.File]::ReadAllLines($absolutePath)

    for ($index = 0; $index -lt $lines.Length; ++$index) {
        if ($lines[$index] -match '^(<<<<<<<|=======|>>>>>>>)') {
            Add-Finding "${relativePath}:$($index + 1): merge conflict marker"
        }
    }

    if ($text -match $privateKeyPattern) { Add-Finding "${relativePath}: private key material" }
    if ($text -match ([Regex]::Escape($classicTokenPrefix) + '[A-Za-z0-9]{36}')) { Add-Finding "${relativePath}: repository access token" }
    if ($text -match ([Regex]::Escape($fineTokenPrefix) + '[A-Za-z0-9_]{20,}')) { Add-Finding "${relativePath}: fine-grained repository access token" }
    if ($text -match ([Regex]::Escape($cloudAccessPrefix) + '[0-9A-Z]{16}')) { Add-Finding "${relativePath}: cloud access key" }
    if ($text -match $secretAssignmentPattern) { Add-Finding "${relativePath}: probable embedded credential assignment" }

    if ($extension -eq ".ps1") {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($absolutePath, [ref]$tokens, [ref]$parseErrors)
        foreach ($parseError in @($parseErrors)) {
            Add-Finding "${relativePath}:$($parseError.Extent.StartLineNumber): PowerShell parse error: $($parseError.Message)"
        }
    }

    if ($extension -in @(".yml", ".yaml")) {
        foreach ($line in $lines) {
            if ($line -match '^\s*-\s*uses:\s*([^@\s]+)@([^\s#]+)') {
                $actionName = $Matches[1]
                $actionRef = $Matches[2]
                if (-not $actionName.StartsWith("./") -and $actionRef -notmatch '^[0-9a-f]{40}$') {
                    Add-Finding "${relativePath}: external action is not pinned to a full commit"
                }
            }
        }
    }
}

$gitignore = [IO.File]::ReadAllText((Join-Path $repoRoot ".gitignore"))
foreach ($required in @("/build/", "/out/", "*.pfx", "*.p12", "*.pem", "*.key", "*.snk", ".env")) {
    if (-not $gitignore.Contains($required)) { Add-Finding ".gitignore: missing required pattern $required" }
}

if ($findings.Count -gt 0) {
    Write-Host "Repository integrity check failed:"
    $findings | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "[pass] Repository integrity check passed."
