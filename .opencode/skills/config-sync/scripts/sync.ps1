<#
.SYNOPSIS
    SHA256 compare and sync live vs deploy-package vs project mirrors.

.DESCRIPTION
    Compares mirror groups (38 agent pairs, opencode.json,
    workflow-enforcement.ts x3, ARCHITECTURE.md x3, MCP_SETUP.md x2, AGENTS.md x4,
    PLUGIN.md x3) by SHA256 and synchronizes them by byte-level copy.
    -Plan (default) reports drift without changes; -Apply publishes live/root
    (source of truth) to deploy; -Apply -Reverse restores deploy to live.
    Pure copy + hash — no content parsing, never deletes.

.PARAMETER Plan
    Report only (default when neither -Plan nor -Apply given).

.PARAMETER Apply
    Perform the sync (direction per direction-semantics table in SKILL.md).

.PARAMETER Reverse
    With -Apply: deploy-package is the source (restore direction).

.PARAMETER Backup
    With -Apply: snapshot each to-be-changed target into
    backup\<yyyyMMdd_HHmmss>_config_sync\<group>\ before any write.

.PARAMETER Group
    Limit to one group: agents, config, plugin, architecture, mcp-setup, agents-md, plugin-md.

.PARAMETER Agent
    With agents group: single agent pair.

.PARAMETER Json
    JSON report instead of token lines.

.OUTPUTS
    STATUS:/GROUP:/DRIFT:/MISSING:/EXTRA:/ERROR:/SYNCED:/VERIFY:/WARN:/ERROR: lines

.NOTES
    Exit codes: 0 plan scan / apply without failures, 2 usage/environment error,
    3 apply failures (copy/verify/backup errors).

.EXAMPLE
    .\sync.ps1 -Plan
    .\sync.ps1 -Apply -Backup
    .\sync.ps1 -Apply -Reverse
    .\sync.ps1 -Plan -Group agents -Agent worker
#>

param(
    [switch]$Plan,
    [switch]$Apply,
    [switch]$Reverse,
    [switch]$Backup,
    [ValidateSet('', 'agents', 'config', 'plugin', 'architecture', 'mcp-setup', 'agents-md', 'plugin-md')]
    [string]$Group = '',
    [string]$Agent = '',
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
if ($Plan -and $Apply) {
    Write-Output 'ERROR: -Plan and -Apply are mutually exclusive'
    exit 2
}
if ($Reverse -and -not $Apply) {
    Write-Output 'ERROR: -Reverse requires -Apply'
    exit 2
}
if ($Agent -and $Group -and $Group -ne 'agents') {
    Write-Output 'ERROR: -Agent is only valid with -Group agents'
    exit 2
}
if ($Agent -and -not $Group) {
    Write-Output 'WARN:narrowing to group agents (-Agent given without -Group)'
    $Group = 'agents'
}
if (-not $Plan -and -not $Apply) { $Plan = $true }

# --- Paths ----------------------------------------------------------------
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy-package"))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}

$liveDir = Join-Path $env:USERPROFILE '.config\opencode'
if (-not (Test-Path -LiteralPath $liveDir -PathType Container)) {
    Write-Output "ERROR: live config dir not found: $liveDir"
    exit 2
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'deploy-package') -PathType Container)) {
    Write-Output "ERROR: deploy-package not found under repo root: $repoRoot"
    exit 2
}

# --- Groups ---------------------------------------------------------------
# Apply source  = Chain[0] (live for config/plugin; repo root for doc groups;
#                 live dir for the agents group).
# Reverse source = the chain member that lives under deploy-package.
$groupDefs = @(
    @{ Name = 'agents';       Kind = 'multi'; LiveDir = (Join-Path $liveDir 'agents'); DeployDir = (Join-Path $repoRoot 'deploy-package\agents') },
    @{ Name = 'config';       Kind = 'chain'; Chain = @((Join-Path $liveDir 'opencode.json'), (Join-Path $repoRoot 'deploy-package\opencode.json')) },
    @{ Name = 'plugin';       Kind = 'chain'; Chain = @((Join-Path $liveDir 'plugins\workflow-enforcement.ts'), (Join-Path $repoRoot 'plugins\workflow-enforcement.ts'), (Join-Path $repoRoot 'deploy-package\plugins\workflow-enforcement.ts')) },
    @{ Name = 'architecture'; Kind = 'chain'; Chain = @((Join-Path $repoRoot 'ARCHITECTURE.md'), (Join-Path $repoRoot 'opencode-config\ARCHITECTURE.md'), (Join-Path $repoRoot 'deploy-package\project-files\ARCHITECTURE.md')) },
    @{ Name = 'mcp-setup';    Kind = 'chain'; Chain = @((Join-Path $repoRoot 'MCP_SETUP.md'), (Join-Path $repoRoot 'deploy-package\project-files\MCP_SETUP.md')) },
    @{ Name = 'agents-md';    Kind = 'chain'; Chain = @((Join-Path $repoRoot 'AGENTS.md'), (Join-Path $repoRoot 'opencode-config\AGENTS.md'), (Join-Path $repoRoot 'deploy-package\project-files\AGENTS.md'), (Join-Path $liveDir 'AGENTS.md')) },
    @{ Name = 'plugin-md';    Kind = 'chain'; Chain = @((Join-Path $repoRoot 'PLUGIN.md'), (Join-Path $repoRoot 'opencode-config\PLUGIN.md'), (Join-Path $repoRoot 'deploy-package\project-files\PLUGIN.md')) }
)
if ($Group) { $groupDefs = @($groupDefs | Where-Object { $_.Name -eq $Group }) }

# Path label for direction strings: live / deploy / root.
function Get-PathLabel([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($liveDir, [System.StringComparison]::OrdinalIgnoreCase)) { return 'live' }
    $deployPrefix = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'deploy-package'))
    if ($full.StartsWith($deployPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return 'deploy' }
    return 'root'
}

# Repo-relative display path (forward slashes); live: prefix for live files.
function Get-RelPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($liveDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $full.Substring($liveDir.Length).TrimStart('\', '/') -replace '\\', '/'
        return "live:$rel"
    }
    $rel = $full.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    return $rel
}

# --- Scan -----------------------------------------------------------------
$script:groupResults = @()
$script:totalDrift = 0
$script:totalMissing = 0
$script:totalExtra = 0

if (-not $Json) { Write-Output 'STATUS:SCAN_START' }

function Compare-Chain($g) {
    $chain = @($g.Chain)
    $srcIdx = 0
    if ($Reverse) {
        $srcIdx = [array]::IndexOf(@($chain | ForEach-Object { if ($_ -match '\\deploy-package\\') { 1 } else { 0 } }), 1)
        if ($srcIdx -lt 0) { $srcIdx = $chain.Count - 1 }
    }
    $findings = @()
    $ok = 0; $drift = 0; $missing = 0
    $src = $chain[$srcIdx]
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        $findings += @{ Kind = 'error'; Origin = 'chain'; Rel = (Get-RelPath $src); Detail = 'source missing'; Src = $null; Dst = $null }
    } else {
        $srcHash = Get-Sha256 $src
        for ($i = 0; $i -lt $chain.Count; $i++) {
            if ($i -eq $srcIdx) { continue }
            $dst = $chain[$i]
            $rel = Get-RelPath $dst
            if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) {
                $findings += @{ Kind = 'missing'; Origin = 'chain'; Rel = $rel; Detail = 'target absent'; Src = $src; Dst = $dst }
                $missing++
            } elseif ((Get-Sha256 $dst) -ne $srcHash) {
                $dstHash = Get-Sha256 $dst
                $findings += @{ Kind = 'drift'; Origin = 'chain'; Rel = $rel; Detail = ("src={0} dst={1}" -f $srcHash.Substring(0,8), $dstHash.Substring(0,8)); Src = $src; Dst = $dst }
                $drift++
            } else {
                $ok++
                if ($Json) { $findings += @{ Kind = 'ok'; Origin = 'chain'; Rel = $rel; Detail = 'identical'; Src = $null; Dst = $null } }
            }
        }
    }
    return @{ Name = $g.Name; Total = ($chain.Count - 1); Ok = $ok; Drift = $drift; Missing = $missing; Extra = 0; Findings = $findings }
}

function Compare-Agents($g) {
    $findings = @()
    $ok = 0; $drift = 0; $missing = 0; $extra = 0
    $liveDirA = $g.LiveDir
    $deployDirA = $g.DeployDir
    $liveNames = @()
    $deployNames = @()
    if (Test-Path -LiteralPath $liveDirA -PathType Container) { $liveNames = @(Get-ChildItem -LiteralPath $liveDirA -Filter '*.md' -File | ForEach-Object { $_.BaseName }) }
    if (Test-Path -LiteralPath $deployDirA -PathType Container) { $deployNames = @(Get-ChildItem -LiteralPath $deployDirA -Filter '*.md' -File | ForEach-Object { $_.BaseName }) }
    $names = @($liveNames + $deployNames | Select-Object -Unique)
    if ($Agent) { $names = @($names | Where-Object { $_ -eq $Agent }) }
    foreach ($n in $names) {
        $lp = Join-Path $liveDirA "$n.md"
        $dp = Join-Path $deployDirA "$n.md"
        $hasL = Test-Path -LiteralPath $lp -PathType Leaf
        $hasD = Test-Path -LiteralPath $dp -PathType Leaf
        if ($hasL -and $hasD) {
            $h1 = Get-Sha256 $lp
            $h2 = Get-Sha256 $dp
            if ($h1 -eq $h2) {
                $ok++
                if ($Json) { $findings += @{ Kind = 'ok'; Origin = 'agents'; Rel = "agents/$n.md"; Detail = 'identical'; Src = $null; Dst = $null } }
            } else {
                # In Reverse mode the deploy copy is the source of truth (restore).
                if ($Reverse) {
                    $findings += @{ Kind = 'drift'; Origin = 'agents'; Rel = "agents/$n.md"; Detail = ("src={0} dst={1}" -f $h2.Substring(0,8), $h1.Substring(0,8)); Src = $dp; Dst = $lp }
                } else {
                    $findings += @{ Kind = 'drift'; Origin = 'agents'; Rel = "agents/$n.md"; Detail = ("src={0} dst={1}" -f $h1.Substring(0,8), $h2.Substring(0,8)); Src = $lp; Dst = $dp }
                }
                $drift++
            }
        } elseif ($hasL -and -not $hasD) {
            $findings += @{ Kind = 'extra'; Origin = 'agents'; Rel = "agents/$n.md"; Detail = 'live only'; Src = $lp; Dst = $dp }
            $extra++
        } elseif ($hasD -and -not $hasL) {
            $findings += @{ Kind = 'missing'; Origin = 'agents'; Rel = "agents/$n.md"; Detail = 'live absent'; Src = $dp; Dst = $lp }
            $missing++
        }
    }
    return @{ Name = $g.Name; Total = $names.Count; Ok = $ok; Drift = $drift; Missing = $missing; Extra = $extra; Findings = $findings }
}

foreach ($g in $groupDefs) {
    $res = if ($g.Kind -eq 'multi') { Compare-Agents $g } else { Compare-Chain $g }
    $script:groupResults += $res
    $script:totalDrift += $res.Drift
    $script:totalMissing += $res.Missing
    $script:totalExtra += $res.Extra
    if (-not $Json) {
        Write-Output ("GROUP:{0} total={1} ok={2} drift={3} missing={4} extra={5}" -f $res.Name, $res.Total, $res.Ok, $res.Drift, $res.Missing, $res.Extra)
        foreach ($f in $res.Findings) {
            if ($f.Kind -eq 'ok') { continue }
            $token = $f.Kind.ToUpperInvariant()
            Write-Output ("{0}:{1} {2}" -f $token, $f.Rel, $f.Detail)
        }
    }
}

if (-not $Json) {
    Write-Output 'WARN:out-of-scope live doc copies not synced (known drift, separate ticket): ARCHITECTURE.md, MCP_SETUP.md, PLUGIN.md, REVIEW_CONTEXT.md'
}

# --- Plan mode ------------------------------------------------------------
if ($Plan) {
    if ($Json) {
        $doc = @{
            groups = @($script:groupResults | ForEach-Object {
                @{ name = $_.Name; total = $_.Total; ok = $_.Ok; drift = $_.Drift; missing = $_.Missing; extra = $_.Extra;
                   findings = @($_.Findings | ForEach-Object { @{ kind = $_.Kind; path = $_.Rel; detail = $_.Detail } }) }
            })
            summary = @{ drift = $script:totalDrift; missing = $script:totalMissing; extra = $script:totalExtra; mode = 'plan' }
        }
        $doc | ConvertTo-Json -Depth 5
    } else {
        Write-Output ("STATUS:PLAN_ONLY drift={0} missing={1} extra={2}" -f $script:totalDrift, $script:totalMissing, $script:totalExtra)
    }
    exit 0
}

# --- Apply mode -----------------------------------------------------------
$direction = if ($Reverse) { 'deploy->live' } else { 'live->deploy' }
if (-not $Json) { Write-Output "STATUS:APPLY_START direction=$direction" }

# Build the action list first (two-phase: backups before any write).
$actions = @()
$failed = 0
foreach ($res in $script:groupResults) {
    foreach ($f in $res.Findings) {
        if ($f.Kind -eq 'ok') { continue }
        if ($f.Kind -eq 'drift') {
            $actions += @{ Group = $res.Name; Src = $f.Src; Dst = $f.Dst; Rel = $f.Rel;
                           Direction = (Get-PathLabel $f.Src) + '->' + (Get-PathLabel $f.Dst) }
        } elseif ($f.Kind -eq 'missing') {
            if ($f.Origin -eq 'chain') {
                # chain member absent: fill from the chain source (both directions)
                $actions += @{ Group = $res.Name; Src = $f.Src; Dst = $f.Dst; Rel = $f.Rel;
                               Direction = (Get-PathLabel $f.Src) + '->' + (Get-PathLabel $f.Dst) }
            } elseif ($Reverse) {
                # agents: deploy-only file (live absent) -> restore deploy->live
                $actions += @{ Group = $res.Name; Src = $f.Src; Dst = $f.Dst; Rel = $f.Rel;
                               Direction = (Get-PathLabel $f.Src) + '->' + (Get-PathLabel $f.Dst) }
            } else {
                if (-not $Json) { Write-Output "ERROR:live source missing, skipped (restore with -Apply -Reverse): $($f.Rel)" }
                $failed++
            }
        } elseif ($f.Kind -eq 'extra') {
            # live-only file (agents group): publish live->deploy in Apply; WARN skip in Reverse
            if ($Reverse) {
                if (-not $Json) { Write-Output "WARN:extra (live only) skipped in reverse mode (never deletes): $($f.Rel)" }
            } else {
                $actions += @{ Group = $res.Name; Src = $f.Src; Dst = $f.Dst; Rel = $f.Rel;
                               Direction = (Get-PathLabel $f.Src) + '->' + (Get-PathLabel $f.Dst) }
            }
        } elseif ($f.Kind -eq 'error') {
            if (-not $Json) { Write-Output "ERROR:source missing, skipped: $($f.Rel)" }
            $failed++
        }
    }
}

if ($actions.Count -eq 0) {
    if ($Json) {
        $doc = @{ summary = @{ mode = 'apply'; direction = $direction; synced = 0; failed = $failed } }
        $doc | ConvertTo-Json -Depth 5
    } else {
        Write-Output 'STATUS:NO_CHANGES'
    }
    if ($failed -gt 0) { exit 3 }
    exit 0
}

# Backup phase (all-or-nothing before any write).
if ($Backup) {
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupRoot = Join-Path $repoRoot "backup\${ts}_config_sync"
    try {
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
        foreach ($a in $actions) {
            if (Test-Path -LiteralPath $a.Dst -PathType Leaf) {
                $gdir = Join-Path $backupRoot $a.Group
                if (-not (Test-Path -LiteralPath $gdir -PathType Container)) {
                    New-Item -ItemType Directory -Force -Path $gdir | Out-Null
                }
                $fname = Split-Path -Leaf $a.Dst
                Copy-Item -LiteralPath $a.Dst -Destination (Join-Path $gdir $fname) -Force
                if (-not $Json) { Write-Output "BACKUP:$(Get-RelPath $a.Dst) -> $(Get-RelPath (Join-Path $gdir $fname))" }
            }
        }
    } catch {
        Write-Output "ERROR:backup failed: $_"
        exit 3
    }
}

# Sync phase.
$synced = 0
foreach ($a in $actions) {
    try {
        $dstParent = Split-Path -Parent $a.Dst
        if (-not (Test-Path -LiteralPath $dstParent -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $dstParent | Out-Null
        }
        Copy-Item -LiteralPath $a.Src -Destination $a.Dst -Force
        $h1 = Get-Sha256 $a.Src
        $h2 = Get-Sha256 $a.Dst
        if ($h1 -ne $h2) {
            Write-Output "ERROR:SHA256 mismatch after copy: $($a.Rel)"
            $failed++
            continue
        }
        $synced++
        if (-not $Json) {
            Write-Output ("SYNCED:{0} direction={1} sha={2}" -f $a.Rel, $a.Direction, $h1.Substring(0,8))
            Write-Output "VERIFY:$($a.Rel) identical"
        }
    } catch {
        Write-Output "ERROR:copy failed: $($a.Rel) - $_"
        $failed++
    }
}

if ($Json) {
    $doc = @{ summary = @{ mode = 'apply'; direction = $direction; synced = $synced; failed = $failed } }
    $doc | ConvertTo-Json -Depth 5
} else {
    Write-Output ("STATUS:SUCCESS synced={0} failed={1}" -f $synced, $failed)
}
if ($failed -gt 0) { exit 3 }
exit 0
