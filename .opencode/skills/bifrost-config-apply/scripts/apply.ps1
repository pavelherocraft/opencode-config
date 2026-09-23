<#
.SYNOPSIS
    Apply a pasted bifrost-litellm provider config to opencode.json

.DESCRIPTION
    Reads a JSON paste, diffs vs current opencode.json, applies a per-model
    merge (preserving every other config section), validates the merged JSON,
    syncs to deploy-package/, verifies SHA256, generates a conventional commit
    message, commits (and optionally pushes).

.PARAMETER PasteJson
    Path to the JSON paste file

.PARAMETER PlanOnly
    Dry-run: show diff only, no edits

.PARAMETER Apply
    Apply edits, sync, commit

.PARAMETER Push
    After commit, push to origin

.OUTPUTS
    STATUS:/DIFF:/EDITED:/SYNCED:/SHA256:/COMMITTED:/PUSHED:/ERROR: lines

.NOTES
    Exit codes: 0 success, 2 usage/environment error, 3 gate block.

.EXAMPLE
    .\apply.ps1 -PasteJson "C:\paste.json" -PlanOnly
    .\apply.ps1 -PasteJson "C:\paste.json" -Apply
    .\apply.ps1 -PasteJson "C:\paste.json" -Apply -Push
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PasteJson,

    [switch]$PlanOnly,
    [switch]$Apply,
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
# git emits UTF-8; keep non-ASCII repo paths intact.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Native command helper ----------------------------------------------
# Native stderr combined with $ErrorActionPreference='Stop' throws a
# terminating NativeCommandError before $LASTEXITCODE can be inspected.
# This helper temporarily relaxes the preference and normalises output to
# strings while preserving $LASTEXITCODE for the caller.
function Invoke-Native {
    param([string]$FilePath, [object[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $FilePath @Arguments 2>&1
    } finally {
        $ErrorActionPreference = $prev
    }
    return @($out | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { $_ }
    })
}

# --- Paths ---------------------------------------------------------------
# Skills are project-level: <repo>\.opencode\skills\<skill>\scripts\apply.ps1
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))

# Fall back to git root detection if the relative layout does not resolve.
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy-package"))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}

$deployed = "$env:USERPROFILE\.config\opencode\opencode.json"
$package = Join-Path $repoRoot "deploy-package\opencode.json"
$diffScript = Join-Path $skillDir "diff.js"
$tempDir = Join-Path $env:TEMP "opencode"
$mergedTemp = Join-Path $tempDir "merged-opencode.json"
$commitMsgFile = Join-Path $tempDir "commit-msg.txt"

# --- Secret gate (mirror git-commit gates) -------------------------------
$SecretPatterns = @(
    @{ Name = 'OpenAI-style key';  Regex = 'sk-[A-Za-z0-9_-]{20,}' },
    @{ Name = 'GitHub token';      Regex = 'gh[pousr]_[A-Za-z0-9]{30,}' },
    @{ Name = 'GitHub PAT';        Regex = 'github_pat_[A-Za-z0-9_]{22,}' },
    @{ Name = 'AWS access key';    Regex = 'AKIA[0-9A-Z]{16}' },
    @{ Name = 'Private key block'; Regex = '-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----' },
    @{ Name = 'Slack token';       Regex = 'xox[baprs]-[A-Za-z0-9-]{10,}' },
    @{ Name = 'Google API key';    Regex = 'AIza[0-9A-Za-z_-]{35}' },
    @{ Name = 'Bearer literal';    Regex = 'Bearer\s+[A-Za-z0-9]{30,}' }
)

function Find-Secrets([string]$Text) {
    $hits = @()
    if (-not $Text) { return $hits }
    foreach ($p in $SecretPatterns) {
        $m = [regex]::Matches($Text, $p.Regex)
        if ($m.Count -gt 0) { $hits += ("{0} (x{1})" -f $p.Name, $m.Count) }
    }
    return $hits
}

# --- Validate inputs -----------------------------------------------------
if (-not (Test-Path -LiteralPath $PasteJson)) {
    Write-Output "ERROR: PasteJson not found: $PasteJson"
    exit 2
}

if (-not (Test-Path -LiteralPath $deployed)) {
    Write-Output "ERROR: deployed opencode.json not found: $deployed"
    exit 2
}

if (-not (Test-Path -LiteralPath $package)) {
    Write-Output "ERROR: deploy-package/opencode.json not found: $package"
    exit 2
}

# Gate: secret scan on the raw paste (BLOCK before any edit).
$pasteText = Get-Content -LiteralPath $PasteJson -Raw
$secretHits = @(Find-Secrets $pasteText)
if ($secretHits.Count -gt 0) {
    foreach ($hit in $secretHits) { Write-Output "BLOCK: secret pattern in paste: $hit" }
    Write-Output "ERROR: paste blocked by $($secretHits.Count) secret gate(s)"
    exit 3
}

# --- Step 1: Diff --------------------------------------------------------
Write-Output "STATUS:DIFF_START"
$diffOutput = Invoke-Native -FilePath "node" -Arguments @($diffScript, "-PasteJson", $PasteJson, "-Current", $deployed)
$diffExit = $LASTEXITCODE
if ($diffExit -ne 0) {
    Write-Output "ERROR:diff failed: $diffOutput"
    if ($diffExit -eq 3) { exit 3 }
    exit 2
}

$diff = $diffOutput | ConvertFrom-Json
$added = @($diff.added).Count
$removed = @($diff.removed).Count
$modified = @($diff.modified).Count

Write-Output "DIFF:added=$added removed=$removed modified=$modified"

if ($added -eq 0 -and $removed -eq 0 -and $modified -eq 0) {
    Write-Output "STATUS:NO_CHANGES"
    exit 0
}

if ($PlanOnly) {
    Write-Output "STATUS:PLAN_ONLY"
    Write-Output "DIFF:$($diffOutput | ConvertTo-Json -Depth 10)"
    exit 0
}

if (-not $Apply) {
    Write-Output "STATUS:DRY_RUN (use -Apply to apply)"
    exit 0
}

# --- Step 2: Apply merged edits (preserve all non-model sections) --------
Write-Output "STATUS:APPLY_START"

if (-not (Test-Path -LiteralPath $tempDir)) {
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
}

# diff.js performs the per-model merge into a temporary full config.
$mergeOutput = Invoke-Native -FilePath "node" -Arguments @($diffScript, "-PasteJson", $PasteJson, "-Current", $deployed, "-Merge", "-Out", $mergedTemp)
if ($LASTEXITCODE -ne 0) {
    Write-Output "ERROR:merge failed: $mergeOutput"
    exit 3
}

# Per-edit JSON validation of the merged config before replacing the deployed one.
try {
    $null = Get-Content -LiteralPath $mergedTemp -Raw | ConvertFrom-Json
} catch {
    Write-Output "ERROR: merged JSON failed validation: $_"
    exit 3
}

Copy-Item -LiteralPath $mergedTemp -Destination $deployed -Force
Write-Output "EDITED:deployed=$deployed"

# --- Step 3: Sync to deploy-package --------------------------------------
Copy-Item -LiteralPath $deployed -Destination $package -Force
Write-Output "SYNCED:package=$package"

# --- Step 4: SHA256 verify -----------------------------------------------
$hash1 = (Get-FileHash -LiteralPath $deployed -Algorithm SHA256).Hash
$hash2 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
if ($hash1 -ne $hash2) {
    Write-Output "ERROR:SHA256 mismatch: deployed=$hash1 package=$hash2"
    exit 3
}
Write-Output "SHA256:identical=$hash1"

# --- Step 5: Generate commit message -------------------------------------
$parts = @()
if ($added -gt 0) { $parts += "add $added model(s)" }
if ($removed -gt 0) { $parts += "remove $removed model(s)" }
if ($modified -gt 0) { $parts += "modify $modified model(s)" }
$summary = $parts -join ", "

$commitMsg = "feat(provider): $summary"

# --- Step 6: Commit (user's configured identity) -------------------------
$gitName = (Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "config", "user.name") | Select-Object -First 1)
$gitEmail = (Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "config", "user.email") | Select-Object -First 1)
if (-not $gitName -or -not $gitEmail) {
    Write-Output "ERROR: git identity missing (user.name='$gitName' user.email='$gitEmail') - set it with: git config user.name \"...\"; git config user.email \"...\""
    exit 3
}

Write-Output "STATUS:COMMIT_START"
if (-not (Test-Path -LiteralPath $tempDir)) {
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
}
$commitMsg | Set-Content -LiteralPath $commitMsgFile -Encoding UTF8

Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "add", "deploy-package/opencode.json") | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output "ERROR:git add failed"
    exit 3
}

Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "commit", "-F", $commitMsgFile) | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output "ERROR:git commit failed"
    exit 3
}

$commitHash = (Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "rev-parse", "HEAD") | Select-Object -First 1)
if ($commitHash) { $commitHash = $commitHash.Trim() }
Write-Output "COMMITTED:hash=$commitHash msg=$commitMsg"

# --- Step 7: Push (optional, current branch) -----------------------------
if ($Push) {
    Write-Output "STATUS:PUSH_START"
    $branch = ((Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "branch", "--show-current")) | Select-Object -First 1)
    if ($branch) { $branch = $branch.Trim() }
    if (-not $branch) {
        Write-Output "ERROR: could not determine current branch"
        exit 3
    }
    Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "push", "origin", $branch) | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "ERROR:git push failed"
        exit 3
    }
    Write-Output "PUSHED:branch=$branch"
}

Write-Output "STATUS:SUCCESS"
exit 0