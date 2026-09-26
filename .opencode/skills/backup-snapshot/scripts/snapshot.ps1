<#
.SYNOPSIS
    Pre-change snapshot of the live config (agents / full) with SHA256 verify.

.DESCRIPTION
    Copies live agent .md files (-Agents, default) or agents + live
    opencode.json + live plugin + live and root documentation (-Full) into
    backup/<yyyy-MM-dd_HHmmss>[_<label>]/ with HASHES.txt (SHA256, sorted) and
    MANIFEST.json, byte-verifying every copy. -Compare <dir> re-hashes the
    current state against a snapshot (SAME/CHANGED/MISSING_NOW/NEW/CORRUPT
    report; -Strict turns differences into exit 3). NEVER deletes or modifies
    sources; partial snapshots are kept with MANIFEST status=FAILED.

.PARAMETER Agents
    Snapshot live agent .md files only (default mode).

.PARAMETER Full
    Agents + live opencode.json + live plugin + live docs + root docs (~50 files).

.PARAMETER Label
    Suffix for the auto dest dir name: backup/<ts>_<label>/.

.PARAMETER Dest
    Explicit snapshot dir (must not exist; relative -> repo root).

.PARAMETER Compare
    Compare mode: current state vs an existing snapshot dir.

.PARAMETER Strict
    With -Compare: differences (changed/missing/new/corrupt) -> exit 3.

.PARAMETER ExpectedAgents
    Informational WARN threshold for the live agents count. Default 38.

.PARAMETER Json
    JSON report instead of token lines.

.OUTPUTS
    COPIED:/SAME:/CHANGED:/MISSING_NOW:/NEW:/CORRUPT:/SUMMARY:/STATUS:/WARN:/ERROR:/BLOCK: lines

.NOTES
    Exit codes: 0 snapshot created / compare report, 2 usage/environment error,
    3 copy/verify/manifest failure, invalid compare inputs, -Strict differences.

.EXAMPLE
    .\snapshot.ps1 -Agents
    .\snapshot.ps1 -Full -Label before_agent_add
    .\snapshot.ps1 -Compare backup\2026-09-23_120000_before_agent_add -Strict
#>

param(
    [switch]$Agents,
    [switch]$Full,
    [string]$Label = '',
    [string]$Dest = '',
    [string]$Compare = '',
    [switch]$Strict,
    [int]$ExpectedAgents = 38,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
# git emits UTF-8; keep non-ASCII repo paths intact.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Native command helper (read-only git fallback for repo root detection) --
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

# --- Byte-safe I/O -------------------------------------------------------
# PS 5.1: Get-Content/Set-Content would ANSI-decode / add BOM. Read raw bytes.
function Read-RawText([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hasBom) {
        if ($bytes.Length -eq 3) { return @{ Text = ''; Bom = $true } }
        $text = [System.Text.Encoding]::UTF8.GetString($bytes[3..($bytes.Length - 1)])
    } else {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    return @{ Text = $text; Bom = $hasBom }
}

function Write-RawText([string]$Path, [string]$Text, [bool]$Bom) {
    $enc = New-Object System.Text.UTF8Encoding($Bom)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# --- Flag validation -----------------------------------------------------
if ($Compare -ne '') {
    if ($Agents -or $Full -or $Label -ne '' -or $Dest -ne '') {
        Write-Output 'ERROR:-Compare is mutually exclusive with -Agents/-Full/-Label/-Dest'
        exit 2
    }
} else {
    if ($Strict) {
        Write-Output 'ERROR:-Strict requires -Compare'
        exit 2
    }
    if ($Agents -and $Full) {
        Write-Output 'ERROR:-Agents and -Full are mutually exclusive'
        exit 2
    }
    if (-not $Agents -and -not $Full) { $Agents = $true }
}

# --- Paths ----------------------------------------------------------------
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy-package"))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}
if (-not (Test-Path -LiteralPath $repoRoot -PathType Container)) {
    Write-Output "ERROR:repo root not found: $repoRoot"
    exit 2
}
$liveDir = Join-Path $env:USERPROFILE '.config\opencode'
if (-not (Test-Path -LiteralPath $liveDir -PathType Container)) {
    Write-Output "ERROR:live config dir not found: $liveDir"
    exit 2
}

function Get-RelToRepo([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($full -replace '\\', '/')
    }
    $rel = $full.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    return $rel
}

# --- Scope -----------------------------------------------------------------
function Get-Scope([string]$Mode) {
    $scope = @()
    $agentsDir = Join-Path $liveDir 'agents'
    foreach ($f in @(Get-ChildItem -LiteralPath $agentsDir -Filter '*.md' -File | Sort-Object Name)) {
        $scope += @{ Src = $f.FullName; Rel = ('live/agents/' + $f.Name) }
    }
    if ($Mode -eq 'full') {
        $scope += @{ Src = (Join-Path $liveDir 'opencode.json'); Rel = 'live/opencode.json' }
        $scope += @{ Src = (Join-Path $liveDir 'plugins\workflow-enforcement.ts'); Rel = 'live/plugins/workflow-enforcement.ts' }
        foreach ($f in @('AGENTS', 'ARCHITECTURE', 'MCP_SETUP', 'PLUGIN', 'REVIEW_CONTEXT')) {
            $scope += @{ Src = (Join-Path $liveDir ($f + '.md')); Rel = ('live/docs/' + $f + '.md') }
        }
        foreach ($f in @('ARCHITECTURE', 'AGENTS', 'PLUGIN', 'MCP_SETUP', 'REVIEW_CONTEXT', 'CHANGELOG')) {
            $scope += @{ Src = (Join-Path $repoRoot ($f + '.md')); Rel = ('repo/docs/' + $f + '.md') }
        }
    }
    return $scope
}

# ============================================================================
# Compare mode
# ============================================================================
if ($Compare -ne '') {
    if ([System.IO.Path]::IsPathRooted($Compare)) {
        $cmpFull = [System.IO.Path]::GetFullPath($Compare)
    } else {
        $cmpFull = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Compare))
    }
    if (-not (Test-Path -LiteralPath $cmpFull -PathType Container)) {
        Write-Output "ERROR:compare dir not found: $cmpFull"
        exit 2
    }
    $manifestPath = Join-Path $cmpFull 'MANIFEST.json'
    $hashesPath = Join-Path $cmpFull 'HASHES.txt'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $hashesPath -PathType Leaf)) {
        Write-Output "BLOCK:MANIFEST.json and/or HASHES.txt missing in: $cmpFull"
        exit 3
    }
    try {
        $manifest = (Read-RawText $manifestPath).Text | ConvertFrom-Json
    } catch {
        Write-Output "BLOCK:MANIFEST.json does not parse: $_"
        exit 3
    }
    $hashesMap = @{}
    try {
        $hashRaw = (Read-RawText $hashesPath).Text
    } catch {
        Write-Output "BLOCK:HASHES.txt unreadable: $_"
        exit 3
    }
    foreach ($line in ($hashRaw -split "`n")) {
        $t = $line.TrimEnd("`r")
        if (-not $t) { continue }
        $m = [regex]::Match($t, '^([0-9A-F]{64})  (.+)$')
        if (-not $m.Success) {
            Write-Output "BLOCK:HASHES.txt line has bad format: $t"
            exit 3
        }
        $hashesMap[$m.Groups[2].Value] = $m.Groups[1].Value
    }

    $entries = @()
    $same = 0; $changed = 0; $missing = 0; $new = 0; $corrupt = 0
    foreach ($f in @($manifest.files)) {
        $rel = [string]$f.rel
        $backupSha = [string]$f.sha256
        $src = [string]$f.src
        $status = ''
        $curSha = ''
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            $status = 'MISSING_NOW'
            $missing++
        } else {
            $curSha = Get-Sha256 $src
            if ($curSha -eq $backupSha) { $status = 'SAME'; $same++ } else { $status = 'CHANGED'; $changed++ }
        }
        if (-not $Json) {
            switch ($status) {
                'SAME' { Write-Output "SAME:$rel" }
                'CHANGED' { Write-Output ("CHANGED:{0} backup={1} current={2}" -f $rel, $backupSha.Substring(0,8), $curSha.Substring(0,8)) }
                'MISSING_NOW' { Write-Output "MISSING_NOW:$rel" }
            }
        }
        $entries += @{ rel = $rel; status = $status; backup_sha = $backupSha; current_sha = $curSha }
        # Backup self-integrity: disk copy vs MANIFEST sha AND vs the HASHES.txt record.
        $diskPath = Join-Path $cmpFull ($rel -replace '/', '\')
        $diskSha = ''
        if (Test-Path -LiteralPath $diskPath -PathType Leaf) { $diskSha = Get-Sha256 $diskPath }
        $hashesSha = $null
        if ($hashesMap.ContainsKey($rel)) { $hashesSha = $hashesMap[$rel] }
        $bad = $false
        if ($diskSha -ne $backupSha) { $bad = $true }
        if ($null -ne $hashesSha -and $hashesSha -ne $backupSha) { $bad = $true }
        if ($bad) {
            $corrupt++
            $disk8 = if ($diskSha) { $diskSha.Substring(0,8) } else { '--------' }
            if (-not $Json) { Write-Output ("CORRUPT:{0} backup={1} disk={2}" -f $rel, $backupSha.Substring(0,8), $disk8) }
            for ($i = 0; $i -lt $entries.Count; $i++) {
                if ($entries[$i].rel -eq $rel) { $entries[$i].status = 'CORRUPT' }
            }
        }
    }
    # NEW: current live agents absent from the manifest rel set.
    $manifestRels = @{}
    foreach ($f in @($manifest.files)) { $manifestRels[[string]$f.rel] = $true }
    $liveAgentsDir = Join-Path $liveDir 'agents'
    foreach ($f in @(Get-ChildItem -LiteralPath $liveAgentsDir -Filter '*.md' -File | Sort-Object Name)) {
        $rel = 'live/agents/' + $f.Name
        if (-not $manifestRels.ContainsKey($rel)) {
            $new++
            $entries += @{ rel = $rel; status = 'NEW'; backup_sha = ''; current_sha = (Get-Sha256 $f.FullName) }
            if (-not $Json) { Write-Output "NEW:$rel" }
        }
    }
    $differences = $changed + $missing + $new + $corrupt
    if ($Json) {
        $doc = @{ entries = $entries; summary = @{ same = $same; changed = $changed; missing = $missing; new = $new; corrupt = $corrupt } }
        $doc | ConvertTo-Json -Depth 5
    } else {
        Write-Output ("SUMMARY:same={0} changed={1} missing={2} new={3} corrupt={4}" -f $same, $changed, $missing, $new, $corrupt)
        if ($differences -eq 0) { Write-Output 'STATUS:IDENTICAL' } else { Write-Output 'STATUS:DIFFERENCES' }
    }
    if ($Strict -and $differences -gt 0) { exit 3 }
    exit 0
}

# ============================================================================
# Snapshot mode
# ============================================================================
$mode = if ($Full) { 'full' } else { 'agents' }
$scope = Get-Scope $mode
if ($scope.Count -eq 0) {
    Write-Output 'ERROR:no files in scope'
    exit 2
}

# Pre-check: every source exists and is readable (ReadWrite sharing so we do
# not block/gets blocked by a running opencode process holding the file).
foreach ($f in $scope) {
    if (-not (Test-Path -LiteralPath $f.Src -PathType Leaf)) {
        Write-Output "ERROR:source missing/unreadable: $($f.Src)"
        exit 2
    }
    try {
        $fs = [System.IO.File]::Open($f.Src, 'Open', 'Read', 'ReadWrite')
        $fs.Close()
    } catch {
        Write-Output "ERROR:source missing/unreadable: $($f.Src)"
        exit 2
    }
}

# Dest: explicit (relative -> repo root) or auto timestamp [+ label].
if ($Dest -ne '') {
    if (-not [System.IO.Path]::IsPathRooted($Dest)) { $Dest = Join-Path $repoRoot $Dest }
} else {
    $Dest = Join-Path $repoRoot ('backup\' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + $(if ($Label) { "_$Label" }))
}
if (Test-Path -LiteralPath $Dest) {
    Write-Output "ERROR:dest already exists: $Dest"
    exit 2
}
try {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
} catch {
    Write-Output "ERROR:dest creation failed: $Dest ($_)"
    exit 3
}

$agentsCount = @(Get-ChildItem -LiteralPath (Join-Path $liveDir 'agents') -Filter '*.md' -File).Count

# Copy + verify loop.
$failed = 0; $copied = 0; $totalBytes = 0
$hashLines = @(); $manifestFiles = @()
foreach ($f in $scope) {
    $dst = Join-Path $Dest ($f.Rel -replace '/', '\')
    $dstParent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstParent)) { New-Item -ItemType Directory -Force -Path $dstParent | Out-Null }
    $srcSha = Get-Sha256 $f.Src
    try {
        Copy-Item -LiteralPath $f.Src -Destination $dst -Force
    } catch {
        Write-Output "ERROR:copy failed: $($f.Rel) $_"
        $failed++
        continue
    }
    $dstSha = Get-Sha256 $dst
    if ($srcSha -ne $dstSha) {
        Write-Output "ERROR:hash mismatch after copy: $($f.Rel)"
        $failed++
        continue
    }
    $bytes = (Get-Item -LiteralPath $dst).Length
    $copied++
    $totalBytes += $bytes
    $hashLines += ('{0}  {1}' -f $srcSha, $f.Rel)
    $manifestFiles += @{ src = $f.Src; rel = $f.Rel; sha256 = $srcSha; bytes = $bytes }
    if (-not $Json) {
        Write-Output ("COPIED:{0} sha={1} bytes={2}" -f $f.Rel, $srcSha.Substring(0,8), $bytes)
    }
}

$status = if ($failed -gt 0) { 'FAILED' } else { 'SUCCESS' }
$createdUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# HASHES.txt: <SHA256-UPPER>  <rel/path>, sorted by rel, LF, no BOM.
# Sort key = the rel part after the 'HASH  ' prefix (SKILL.md: "sorted by rel path").
$hashesText = (($hashLines | Sort-Object { ($_ -split '  ', 2)[-1] }) -join "`n") + "`n"
try {
    Write-RawText -Path (Join-Path $Dest 'HASHES.txt') -Text $hashesText -Bom $false
} catch {
    Write-Output "ERROR:HASHES.txt write failed: $_"
    exit 3
}
# MANIFEST.json (PS 5.1: -Depth 4 is mandatory, default 2 truncates files[]).
$manifestDoc = @{
    mode = $mode
    label = $Label
    created_utc = $createdUtc
    status = $status
    expected_agents = $ExpectedAgents
    agents_count = $agentsCount
    files_count = $copied
    total_bytes = $totalBytes
    files = $manifestFiles
}
try {
    $manifestJson = $manifestDoc | ConvertTo-Json -Depth 4
    Write-RawText -Path (Join-Path $Dest 'MANIFEST.json') -Text ($manifestJson -replace "`r`n", "`n") -Bom $false
} catch {
    Write-Output "ERROR:MANIFEST.json write failed: $_"
    exit 3
}

if ($failed -gt 0) {
    Write-Output "STATUS:FAILED copied=$copied failed=$failed (copied files are KEPT — re-run with a fresh dest)"
    exit 3
}
if ($agentsCount -ne $ExpectedAgents) {
    Write-Output "WARN:live agents count=$agentsCount expected=$ExpectedAgents (snapshot taken anyway)"
}
$destRel = Get-RelToRepo $Dest
if ($Json) {
    $doc = @{
        mode = $mode
        label = $Label
        created_utc = $createdUtc
        status = $status
        dest = $destRel
        files_count = $copied
        total_bytes = $totalBytes
        files = @($manifestFiles | ForEach-Object { @{ rel = $_.rel; sha256 = $_.sha256; bytes = $_.bytes } })
    }
    $doc | ConvertTo-Json -Depth 5
} else {
    Write-Output ("SUMMARY:mode={0} files={1} bytes={2} dest={3}" -f $mode, $copied, $totalBytes, $destRel)
    Write-Output 'STATUS:SUCCESS'
}
exit 0
