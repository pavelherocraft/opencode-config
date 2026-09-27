<#
.SYNOPSIS
    Fast LLM-free integrity check of the live<->repo orchestration config.

.DESCRIPTION
    Checks (all read-only, no hardcoded expectations — counters are DERIVED
    from the fact and cross-checked against each other):
      1. 5 sync pairs (live <-> repo) SHA256 — drift reported as DRIFT: lines
         with the hint "config-sync --save"
      2. JSON validity: live + repo opencode.json
      3. Agent counts: live agents/*.md == repo agents/*.md == opencode.json
         agent entries
      4. Routing counts (derived): plugin ROUTING_TABLES vs opencode.json
         task-allowlists vs ARCHITECTURE.md whitelist headers/rows
      5. Frontmatter model key format + existence in opencode.json provider
         models (prefix bifrost-litellm/)

.PARAMETER Json
    Emit a single JSON document instead of token lines.

.OUTPUTS
    STATUS:/PAIR:/DRIFT:/JSON:/COUNT:/FORMAT:/EXISTS:/WARN:/SUMMARY:/ERROR: lines

.NOTES
    Exit codes: 0 all pass (WARNs allowed), 2 usage/environment error,
    3 one or more FAIL findings. Read-only: never writes anything.

.EXAMPLE
    .\check.ps1
    .\check.ps1 -Json
#>

param(
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

# --- Byte-safe I/O -------------------------------------------------------
# PS 5.1: Get-Content/Set-Content would ANSI-decode / add BOM. Read raw bytes.
function Read-RawText([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hasBom) {
        if ($bytes.Length -eq 3) { return '' }
        return [System.Text.Encoding]::UTF8.GetString($bytes[3..($bytes.Length - 1)])
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-FmModel([string]$Text) {
    $m = [regex]::Match($Text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $m.Success) { return $null }
    $mm = [regex]::Match($m.Groups[1].Value, '(?m)^model:[ \t]*(.*)$')
    if (-not $mm.Success) { return $null }
    return $mm.Groups[1].Value.Trim()
}

# --- Check bookkeeping ---------------------------------------------------
$script:Checks = @()
$script:Counts = @{ pass = 0; fail = 0; warn = 0 }

function Add-Check {
    param([string]$Id, [string]$Target, [ValidateSet('PASS','FAIL','WARN')][string]$Status, [string]$Detail)
    $script:Checks += @{ id = $Id; target = $Target; status = $Status; detail = $Detail }
    switch ($Status) {
        'PASS' { $script:Counts.pass++ }
        'FAIL' { $script:Counts.fail++ }
        'WARN' { $script:Counts.warn++ }
    }
    if (-not $Json) {
        $display = $Status
        if ($Id -eq 'PAIR' -and $Status -eq 'PASS') { $display = 'OK' }
        $payload = ''
        if ($Target) { $payload = $Target }
        if ($Detail) { if ($payload) { $payload = "$payload $Detail" } else { $payload = $Detail } }
        Write-Output ("{0}:{1} -> {2}" -f $Id, $payload, $display)
    }
}

# --- Routing counters ----------------------------------------------------
function Count-TaskAllow($CfgObj, [string]$Primary) {
    try {
        $node = $CfgObj.agent.$Primary.permission.task
        if (-not $node) { return $null }
        return @($node.PSObject.Properties | Where-Object { $_.Name -ne '*' -and [string]$_.Value -eq 'allow' }).Count
    } catch { return $null }
}

function Count-RoutingPlugin([string]$TsText, [string]$Primary) {
    $outer = [regex]::Match($TsText, '(?s)const ROUTING_TABLES = \{(.*?)\r?\n\}')
    if (-not $outer.Success) { return $null }
    $inner = [regex]::Match($outer.Groups[1].Value, ('(?s)' + [regex]::Escape($Primary) + '\s*:\s*\[(.*?)\]'))
    if (-not $inner.Success) { return $null }
    return [regex]::Matches($inner.Groups[1].Value, '"[^"]+"').Count
}

function Get-WhitelistCount([string]$ArchText, [string]$Primary) {
    $headerPat = '^### ' + [regex]::Escape($Primary) + ' Whitelist \((\d+) agents\)'
    $hm = [regex]::Match($ArchText, $headerPat, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $hm.Success) { return $null }
    $after = $ArchText.Substring($hm.Index + $hm.Length)
    $firstPipe = [regex]::Match($after, '(?m)^\|')
    if (-not $firstPipe.Success) { return @{ Header = [int]$hm.Groups[1].Value; Rows = -1 } }
    $rest = $after.Substring($firstPipe.Index)
    $blank = [regex]::Match($rest, '\r?\n[ \t]*\r?\n')
    $tbl = if ($blank.Success) { $rest.Substring(0, $blank.Index) } else { $rest }
    $rows = [regex]::Matches($tbl, '(?m)^\|\s*\d+\s*\|').Count
    return @{ Header = [int]$hm.Groups[1].Value; Rows = $rows }
}

# --- Paths ----------------------------------------------------------------
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.opencode'))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}

$liveDir = Join-Path $env:USERPROFILE '.config\opencode'
$liveAgentsDir = Join-Path $liveDir 'agents'
$repoAgentsDir = Join-Path $repoRoot 'agents'

if (-not (Test-Path -LiteralPath $liveAgentsDir -PathType Container)) {
    Write-Output "ERROR: live agents dir not found: $liveAgentsDir"
    exit 2
}
if (-not (Test-Path -LiteralPath $repoAgentsDir -PathType Container)) {
    Write-Output "ERROR: repo agents dir not found: $repoAgentsDir"
    exit 2
}
$liveCfgPath = Join-Path $liveDir 'opencode.json'
if (-not (Test-Path -LiteralPath $liveCfgPath -PathType Leaf)) {
    Write-Output "ERROR: live opencode.json not found: $liveCfgPath"
    exit 2
}

if (-not $Json) { Write-Output 'STATUS:CHECK_START' }

# --- 1. JSON validity (live + repo) — C5 -----------------------------------
$cfg = $null
$jsonLiveOk = $true
try {
    $cfg = Read-RawText $liveCfgPath | ConvertFrom-Json
} catch {
    $jsonLiveOk = $false
}
Add-Check -Id 'JSON' -Target 'opencode.json live' -Status $(if ($jsonLiveOk) { 'PASS' } else { 'FAIL' }) -Detail $(if ($jsonLiveOk) { 'parse ok' } else { 'invalid JSON' })
$jsonRepoOk = $true
try {
    Read-RawText (Join-Path $repoRoot 'opencode.json') | Out-Null
    $repoCfg = Read-RawText (Join-Path $repoRoot 'opencode.json') | ConvertFrom-Json
} catch {
    $jsonRepoOk = $false
}
Add-Check -Id 'JSON' -Target 'opencode.json repo' -Status $(if ($jsonRepoOk) { 'PASS' } else { 'FAIL' }) -Detail $(if ($jsonRepoOk) { 'parse ok' } else { 'invalid JSON' })

# --- 2. Sync-pair drift (5 pairs) — C3 -------------------------------------
$pairDefs = @(
    @{ Name = 'agents';           Kind = 'agents'; Live = $liveAgentsDir;                                          Repo = $repoAgentsDir },
    @{ Name = 'opencode.json';    Kind = 'file';   Live = $liveCfgPath;                                            Repo = (Join-Path $repoRoot 'opencode.json') },
    @{ Name = 'plugin';           Kind = 'file';   Live = (Join-Path $liveDir 'plugins\workflow-enforcement.ts'); Repo = (Join-Path $repoRoot 'plugins\workflow-enforcement.ts') },
    @{ Name = 'skills/git-commit'; Kind = 'dir';   Live = (Join-Path $liveDir 'skills\git-commit');               Repo = (Join-Path $repoRoot 'skills\git-commit') },
    @{ Name = 'AGENTS.md';        Kind = 'file';   Live = (Join-Path $liveDir 'AGENTS.md');                       Repo = (Join-Path $repoRoot 'AGENTS.global.md') }
)
foreach ($p in $pairDefs) {
    if ($p.Kind -eq 'agents') {
        $liveFilesP = @(Get-ChildItem -LiteralPath $p.Live -Filter '*.md' -File)
        $repoFilesP = @(Get-ChildItem -LiteralPath $p.Repo -Filter '*.md' -File)
        $liveNamesP = @($liveFilesP | ForEach-Object { $_.Name })
        $repoNamesP = @($repoFilesP | ForEach-Object { $_.Name })
        $union = @($liveNamesP + $repoNamesP | Select-Object -Unique)
        foreach ($n in $union) {
            $lp = Join-Path $p.Live $n
            $rp = Join-Path $p.Repo $n
            if ((Test-Path -LiteralPath $lp) -and (Test-Path -LiteralPath $rp)) {
                $h1 = Get-Sha256 $lp
                $h2 = Get-Sha256 $rp
                if ($h1 -eq $h2) {
                    Add-Check -Id 'PAIR' -Target "agents/$n" -Status 'PASS' -Detail ''
                } else {
                    Add-Check -Id 'DRIFT' -Target "agents/$n" -Status 'FAIL' -Detail ("live={0} repo={1} (use: config-sync --save)" -f $h1.Substring(0,8), $h2.Substring(0,8))
                }
            } else {
                Add-Check -Id 'DRIFT' -Target "agents/$n" -Status 'FAIL' -Detail 'side missing (use: config-sync --save)'
            }
        }
    } elseif ($p.Kind -eq 'dir') {
        $liveRels = @()
        $repoRels = @()
        if (Test-Path -LiteralPath $p.Live -PathType Container) {
            $liveRels = @(Get-ChildItem -LiteralPath $p.Live -File -Recurse | ForEach-Object { $_.FullName.Substring($p.Live.Length).TrimStart('\','/') -replace '\\','/' } | Sort-Object)
        }
        if (Test-Path -LiteralPath $p.Repo -PathType Container) {
            $repoRels = @(Get-ChildItem -LiteralPath $p.Repo -File -Recurse | ForEach-Object { $_.FullName.Substring($p.Repo.Length).TrimStart('\','/') -replace '\\','/' } | Sort-Object)
        }
        $unionRels = @($liveRels + $repoRels | Select-Object -Unique | Sort-Object)
        foreach ($rel in $unionRels) {
            $label = "$($p.Name)/$rel"
            $lp = Join-Path $p.Live ($rel -replace '/', '\')
            $rp = Join-Path $p.Repo ($rel -replace '/', '\')
            if ((Test-Path -LiteralPath $lp) -and (Test-Path -LiteralPath $rp)) {
                $h1 = Get-Sha256 $lp
                $h2 = Get-Sha256 $rp
                if ($h1 -eq $h2) {
                    Add-Check -Id 'PAIR' -Target $label -Status 'PASS' -Detail ''
                } else {
                    Add-Check -Id 'DRIFT' -Target $label -Status 'FAIL' -Detail ("live={0} repo={1} (use: config-sync --save)" -f $h1.Substring(0,8), $h2.Substring(0,8))
                }
            } else {
                Add-Check -Id 'DRIFT' -Target $label -Status 'FAIL' -Detail 'side missing (use: config-sync --save)'
            }
        }
    } else {
        if ((Test-Path -LiteralPath $p.Live -PathType Leaf) -and (Test-Path -LiteralPath $p.Repo -PathType Leaf)) {
            $h1 = Get-Sha256 $p.Live
            $h2 = Get-Sha256 $p.Repo
            if ($h1 -eq $h2) {
                Add-Check -Id 'PAIR' -Target $p.Name -Status 'PASS' -Detail ''
            } else {
                Add-Check -Id 'DRIFT' -Target $p.Name -Status 'FAIL' -Detail ("live={0} repo={1} (use: config-sync --save)" -f $h1.Substring(0,8), $h2.Substring(0,8))
            }
        } else {
            Add-Check -Id 'DRIFT' -Target $p.Name -Status 'FAIL' -Detail 'side missing (use: config-sync --save)'
        }
    }
}

# --- 3. Agent counts (derived) — C2 ----------------------------------------
$liveFiles = @(Get-ChildItem -LiteralPath $liveAgentsDir -Filter '*.md' -File)
$repoFiles = @(Get-ChildItem -LiteralPath $repoAgentsDir -Filter '*.md' -File)
$cfgAgentCount = $null
if ($jsonLiveOk -and $cfg) { $cfgAgentCount = @($cfg.agent.PSObject.Properties).Count }
$liveNames = @($liveFiles | ForEach-Object { $_.BaseName })
$repoNames = @($repoFiles | ForEach-Object { $_.BaseName })
$onlyLive = @($liveNames | Where-Object { $repoNames -notcontains $_ })
$onlyRepo = @($repoNames | Where-Object { $liveNames -notcontains $_ })
$countDetail = "agents_live=$($liveFiles.Count) agents_repo=$($repoFiles.Count) opencode_json=$cfgAgentCount (derived, no hardcoded expectation)"
if ($onlyLive.Count -or $onlyRepo.Count) {
    $countDetail += " live_only=[$($onlyLive -join ',')] repo_only=[$($onlyRepo -join ',')]"
}
$countOk = ($liveFiles.Count -eq $repoFiles.Count)
if ($null -ne $cfgAgentCount) { $countOk = $countOk -and ($cfgAgentCount -eq $liveFiles.Count) }
$countOk = $countOk -and ($onlyLive.Count -eq 0) -and ($onlyRepo.Count -eq 0)
Add-Check -Id 'COUNT' -Target '' -Status $(if ($countOk) { 'PASS' } else { 'FAIL' }) -Detail $countDetail

# --- 4. Routing counts (derived cross-check) — C1/C2 ------------------------
$archPath = Join-Path $repoRoot 'ARCHITECTURE.md'
$archText = $null
if (Test-Path -LiteralPath $archPath -PathType Leaf) { $archText = Read-RawText $archPath }
else { Add-Check -Id 'WARN' -Target 'ARCHITECTURE.md' -Status 'WARN' -Detail 'not found — whitelist cross-check skipped' }

$tsPath = Join-Path $liveDir 'plugins\workflow-enforcement.ts'
$tsText = $null
if (Test-Path -LiteralPath $tsPath -PathType Leaf) { $tsText = Read-RawText $tsPath }

foreach ($primary in @('orchestrator', 'plankestrator')) {
    $jsonN = $null
    if ($jsonLiveOk) { $jsonN = Count-TaskAllow $cfg $primary }
    $plugN = $null
    if ($null -ne $tsText) { $plugN = Count-RoutingPlugin $tsText $primary }
    $archH = $null; $archR = $null
    if ($null -ne $archText) {
        $wl = Get-WhitelistCount $archText $primary
        if ($null -ne $wl) { $archH = $wl.Header; $archR = $wl.Rows }
    }
    $values = @($jsonN, $plugN, $archH, $archR | Where-Object { $null -ne $_ })
    $ok = ($values.Count -ge 2 -and (@($values | Select-Object -Unique).Count -eq 1))
    Add-Check -Id 'COUNT' -Target '' -Status $(if ($ok) { 'PASS' } else { 'FAIL' }) -Detail "routing_$primary json=$jsonN plugin=$plugN arch_header=$archH arch_rows=$archR (derived cross-check)"
    if ($null -eq $plugN) {
        Add-Check -Id 'WARN' -Target 'routing' -Status 'WARN' -Detail "$primary plugin anchor not parsed (skipped plugin source)"
    }
    if ($null -eq $archH -and $null -ne $archText) {
        Add-Check -Id 'WARN' -Target 'routing' -Status 'WARN' -Detail "$primary ARCHITECTURE whitelist anchor not parsed"
    }
}

# --- 5. Model key format + existence — C4 -----------------------------------
foreach ($f in $liveFiles) {
    $name = $f.BaseName
    $m = Get-FmModel (Read-RawText $f.FullName)
    if (-not $m) {
        Add-Check -Id 'FORMAT' -Target $name -Status 'FAIL' -Detail 'frontmatter without model line'
        continue
    }
    $fmtOk = $m -match '^[A-Za-z0-9._-]+/.+$'
    Add-Check -Id 'FORMAT' -Target $name -Status $(if ($fmtOk) { 'PASS' } else { 'FAIL' }) -Detail "model=$m"
    if ($jsonLiveOk) {
        $exists = $false
        if ($fmtOk -and $cfg) {
            $slash = $m.IndexOf('/')
            $prov = $m.Substring(0, $slash)
            $key = $m.Substring($slash + 1)
            $provProp = $cfg.provider.PSObject.Properties[$prov]
            if ($provProp -and $provProp.Value.models) {
                $exists = @($provProp.Value.models.PSObject.Properties.Name) -contains $key
            }
        }
        Add-Check -Id 'EXISTS' -Target $name -Status $(if ($exists) { 'PASS' } else { 'FAIL' }) -Detail $m
    }
}
if (-not $jsonLiveOk) {
    Add-Check -Id 'EXISTS' -Target '' -Status 'WARN' -Detail 'checks skipped (opencode.json parse failed)'
}

# --- 6. Summary --------------------------------------------------------------
$total = $script:Checks.Count
$pass = $script:Counts.pass
$fail = $script:Counts.fail
$warn = $script:Counts.warn

if ($Json) {
    $doc = @{
        checks = $script:Checks
        summary = @{ total = $total; pass = $pass; fail = $fail; warn = $warn }
    }
    $doc | ConvertTo-Json -Depth 5
} else {
    Write-Output ("SUMMARY:checks={0} pass={1} fail={2} warn={3}" -f $total, $pass, $fail, $warn)
    if ($fail -gt 0) {
        Write-Output ("STATUS:FAILURES fail={0}" -f $fail)
        exit 3
    }
    Write-Output 'STATUS:ALL_PASS'
}
if ($fail -gt 0) { exit 3 }
exit 0
