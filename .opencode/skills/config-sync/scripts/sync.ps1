<#
.SYNOPSIS
    live <-> repo config sync (5 sync pairs).

.DESCRIPTION
    Compares and synchronizes the 5 sync pairs declared in ARCHITECTURE.md
    (§File Locations "Sync-механика"):
      1. agents/*.md                     live  <-> repo agents/*.md
      2. opencode.json                   live  <-> repo opencode.json
      3. plugins/workflow-enforcement.ts live  <-> repo plugins/workflow-enforcement.ts
      4. skills/git-commit/*             live  <-> repo skills/git-commit/*
      5. AGENTS.md                       live  <-> repo AGENTS.global.md
    -Save (default) snapshots live -> repo before a commit; -Restore rolls the
    repo back into live (explicit emergency rollback only); -Plan reports drift
    without changes. Pure byte copy + SHA256 — no content parsing, never deletes.

.PARAMETER Save
    live -> repo (default when no mode flag is given).

.PARAMETER Restore
    repo -> live. Prints a warning; overwrites the LIVE config.

.PARAMETER Plan
    Drift report only (no writes). Exit 3 when drift is detected.

.PARAMETER Pair
    Limit to one pair: agents, opencode.json, plugin, skills/git-commit, AGENTS.md.

.PARAMETER Json
    JSON report instead of token lines.

.OUTPUTS
    STATUS:/PAIR:/SYNCED:/DRIFT:/MISSING:/EXTRA:/ERROR:/WARN:/SUMMARY: lines

.NOTES
    Exit codes: 0 ok (plan without drift; save/restore without failures),
    2 usage/environment error, 3 drift detected (-Plan); copy/verify failures.

.EXAMPLE
    .\sync.ps1 -Save
    .\sync.ps1 -Plan
    .\sync.ps1 -Restore
    .\sync.ps1 -Plan -Pair agents
#>

param(
    [switch]$Save,
    [switch]$Restore,
    [switch]$Plan,
    [ValidateSet('', 'agents', 'opencode.json', 'plugin', 'skills/git-commit', 'AGENTS.md')]
    [string]$Pair = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
# git emits UTF-8; keep non-ASCII repo paths intact.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Native command helper ----------------------------------------------
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

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# --- Flag validation -----------------------------------------------------
$modes = @($Save, $Restore, $Plan | Where-Object { $_ })
if ($modes.Count -gt 1) {
    Write-Output 'ERROR: -Save, -Restore and -Plan are mutually exclusive'
    exit 2
}
if ($modes.Count -eq 0) { $Save = $true }

# --- Paths ----------------------------------------------------------------
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.opencode'))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}

$liveDir = Join-Path $env:USERPROFILE '.config\opencode'
if (-not (Test-Path -LiteralPath $liveDir -PathType Container)) {
    Write-Output "ERROR: live config dir not found: $liveDir"
    exit 2
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.opencode') -PathType Container)) {
    Write-Output "ERROR: repo root not found (no .opencode\ under it): $repoRoot"
    exit 2
}

# --- 5 sync pairs -----------------------------------------------------------
$pairDefs = @(
    @{ Name = 'agents';           Kind = 'multi'; Pattern = '*.md'; Live = (Join-Path $liveDir 'agents');                     Repo = (Join-Path $repoRoot 'agents') },
    @{ Name = 'opencode.json';    Kind = 'file';                                              Live = (Join-Path $liveDir 'opencode.json');               Repo = (Join-Path $repoRoot 'opencode.json') },
    @{ Name = 'plugin';           Kind = 'file';                                              Live = (Join-Path $liveDir 'plugins\workflow-enforcement.ts'); Repo = (Join-Path $repoRoot 'plugins\workflow-enforcement.ts') },
    @{ Name = 'skills/git-commit'; Kind = 'multi'; Pattern = '*';                             Live = (Join-Path $liveDir 'skills\git-commit');           Repo = (Join-Path $repoRoot 'skills\git-commit') },
    @{ Name = 'AGENTS.md';        Kind = 'file';                                              Live = (Join-Path $liveDir 'AGENTS.md');                   Repo = (Join-Path $repoRoot 'AGENTS.global.md') }
)
if ($Pair) { $pairDefs = @($pairDefs | Where-Object { $_.Name -eq $Pair }) }

$srcSide = if ($Restore) { 'Repo' } else { 'Live' }
$dstSide = if ($Restore) { 'Live' } else { 'Repo' }

# Recursive relative posix paths for multi pairs (*.md = top level only).
function Get-MultiFiles([string]$Dir, [string]$Pattern) {
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return @() }
    $items = if ($Pattern -eq '*.md') {
        Get-ChildItem -LiteralPath $Dir -Filter $Pattern -File
    } else {
        Get-ChildItem -LiteralPath $Dir -File -Recurse
    }
    return @($items | ForEach-Object {
        $rel = $_.FullName.Substring($Dir.Length).TrimStart('\', '/') -replace '\\', '/'
        $rel
    } | Sort-Object)
}

if (-not $Json) {
    Write-Output 'STATUS:SCAN_START'
    if ($Restore) {
        Write-Output 'WARN:RESTORE mode — repo -> live OVERWRITES the live config (explicit emergency rollback). Recommended: backup-snapshot first.'
    }
}

$script:pairResults = @()
foreach ($p in $pairDefs) {
    $findings = @()
    if ($p.Kind -eq 'multi') {
        $srcRoot = $p.$srcSide
        $dstRoot = $p.$dstSide
        $srcFiles = Get-MultiFiles $srcRoot $p.Pattern
        $dstFiles = Get-MultiFiles $dstRoot $p.Pattern
        $all = @($srcFiles + $dstFiles | Select-Object -Unique | Sort-Object)
        foreach ($rel in $all) {
            $label = if ($p.Name -ne 'AGENTS.md') { "$($p.Name)/$rel" } else { $p.Name }
            $sp = Join-Path $srcRoot ($rel -replace '/', '\')
            $dp = Join-Path $dstRoot ($rel -replace '/', '\')
            $inSrc = $srcFiles -contains $rel
            $inDst = $dstFiles -contains $rel
            if ($inSrc -and $inDst) {
                $h1 = Get-Sha256 $sp
                $h2 = Get-Sha256 $dp
                if ($h1 -eq $h2) {
                    $findings += @{ Kind = 'ok'; Path = $label }
                } else {
                    $findings += @{ Kind = 'drift'; Path = $label; Detail = ("{0}={1} {2}={3}" -f $srcSide.ToLower(), $h1.Substring(0,8), $dstSide.ToLower(), $h2.Substring(0,8)); Src = $sp; Dst = $dp }
                }
            } elseif ($inSrc) {
                $findings += @{ Kind = 'missing'; Path = $label; Detail = "absent on $($dstSide.ToLower())"; Src = $sp; Dst = $dp }
            } else {
                $findings += @{ Kind = 'extra'; Path = $label; Detail = "exists on $($dstSide.ToLower()) only (never deleted)" }
            }
        }
    } else {
        $sp = $p.$srcSide
        $dp = $p.$dstSide
        if (-not (Test-Path -LiteralPath $sp -PathType Leaf)) {
            $findings += @{ Kind = 'error'; Path = $p.Name; Detail = "$($srcSide.ToLower()) source missing" }
        } elseif (-not (Test-Path -LiteralPath $dp -PathType Leaf)) {
            $findings += @{ Kind = 'missing'; Path = $p.Name; Detail = "absent on $($dstSide.ToLower())"; Src = $sp; Dst = $dp }
        } else {
            $h1 = Get-Sha256 $sp
            $h2 = Get-Sha256 $dp
            if ($h1 -eq $h2) {
                $findings += @{ Kind = 'ok'; Path = $p.Name }
            } else {
                $findings += @{ Kind = 'drift'; Path = $p.Name; Detail = ("{0}={1} {2}={3}" -f $srcSide.ToLower(), $h1.Substring(0,8), $dstSide.ToLower(), $h2.Substring(0,8)); Src = $sp; Dst = $dp }
            }
        }
    }
    $script:pairResults += @{ Name = $p.Name; Findings = $findings }

    if (-not $Json) {
        $ok = @($findings | Where-Object { $_.Kind -eq 'ok' }).Count
        $drift = @($findings | Where-Object { $_.Kind -eq 'drift' }).Count
        $missing = @($findings | Where-Object { $_.Kind -eq 'missing' }).Count
        $extra = @($findings | Where-Object { $_.Kind -eq 'extra' }).Count
        Write-Output ("PAIR:{0} ok={1} drift={2} missing={3} extra={4}" -f $p.Name, $ok, $drift, $missing, $extra)
        foreach ($f in $findings) {
            if ($f.Kind -eq 'ok') { continue }
            $hint = ''
            if ($Plan -and ($f.Kind -eq 'drift' -or $f.Kind -eq 'missing')) { $hint = ' (use --save)' }
            Write-Output ("{0}:{1} {2}{3}" -f $f.Kind.ToUpperInvariant(), $f.Path, $f.Detail, $hint)
        }
    }
}

$allFindings = @($script:pairResults | ForEach-Object { $_.Findings })
$totalDrift = @($allFindings | Where-Object { $_.Kind -eq 'drift' }).Count
$totalMissing = @($allFindings | Where-Object { $_.Kind -eq 'missing' }).Count
$totalExtra = @($allFindings | Where-Object { $_.Kind -eq 'extra' }).Count
$totalErrors = @($allFindings | Where-Object { $_.Kind -eq 'error' }).Count

# --- Plan mode ------------------------------------------------------------
if ($Plan) {
    if ($Json) {
        $doc = @{
            mode = 'plan'
            pairs = @($script:pairResults | ForEach-Object {
                @{ name = $_.Name; findings = @($_.Findings | ForEach-Object { @{ kind = $_.Kind; path = $_.Path; detail = $_.Detail } }) }
            })
            summary = @{ drift = $totalDrift; missing = $totalMissing; extra = $totalExtra; errors = $totalErrors }
        }
        $doc | ConvertTo-Json -Depth 5
    } else {
        Write-Output ("SUMMARY:mode=plan drift={0} missing={1} extra={2} errors={3}" -f $totalDrift, $totalMissing, $totalExtra, $totalErrors)
    }
    if ($totalDrift -or $totalMissing -or $totalErrors) {
        Write-Output 'STATUS:DRIFT_DETECTED (fix with: config-sync --save)'
        exit 3
    }
    Write-Output 'STATUS:IN_SYNC'
    exit 0
}

# --- Save / Restore ---------------------------------------------------------
$mode = if ($Restore) { 'restore' } else { 'save' }
$direction = if ($Restore) { 'repo->live' } else { 'live->repo' }
if (-not $Json) { Write-Output "STATUS:APPLY_START mode=$mode direction=$direction" }

$synced = 0
$failed = $totalErrors
foreach ($res in $script:pairResults) {
    foreach ($f in $res.Findings) {
        if ($f.Kind -ne 'drift' -and $f.Kind -ne 'missing') { continue }
        try {
            $dstParent = Split-Path -Parent $f.Dst
            if (-not (Test-Path -LiteralPath $dstParent -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $dstParent | Out-Null
            }
            Copy-Item -LiteralPath $f.Src -Destination $f.Dst -Force
            $h1 = Get-Sha256 $f.Src
            $h2 = Get-Sha256 $f.Dst
            if ($h1 -ne $h2) {
                Write-Output "ERROR:SHA256 mismatch after copy: $($f.Path)"
                $failed++
                continue
            }
            $synced++
            if (-not $Json) {
                Write-Output ("SYNCED:{0} direction={1} sha={2}" -f $f.Path, $direction, $h1.Substring(0,8))
            }
        } catch {
            Write-Output "ERROR:copy failed: $($f.Path) - $_"
            $failed++
        }
    }
}

if ($Json) {
    @{ summary = @{ mode = $mode; direction = $direction; synced = $synced; failed = $failed; extra_reported = $totalExtra } } | ConvertTo-Json -Depth 5
} else {
    Write-Output ("SUMMARY:mode={0} synced={1} failed={2} extra_reported={3}" -f $mode, $synced, $failed, $totalExtra)
}
if ($failed -gt 0) {
    Write-Output "STATUS:FAILED failed=$failed"
    exit 3
}
if ($synced -gt 0) { Write-Output 'STATUS:SUCCESS' } else { Write-Output 'STATUS:NO_CHANGES' }
exit 0
