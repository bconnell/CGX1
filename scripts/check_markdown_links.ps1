Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$checker = Join-Path $PSScriptRoot "check_markdown_links.py"
$python = Get-Command py.exe -ErrorAction SilentlyContinue
if ($null -eq $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if ($null -eq $python) { throw "The Python launcher (py) was not found." }

& $python.Source -3 $checker --root $repoRoot
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    exit $exitCode
}
