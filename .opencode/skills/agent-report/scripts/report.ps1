<#
.SYNOPSIS
    Fast LLM-free fleet report: every agent with model, role, tier, mode,
    permissions and routing membership.

.DESCRIPTION
    Per-agent table (frontmatter model, Model Roles role/tier, mode, flattened
    permissions, routing whitelist membership orch/plan/both/none) plus
    model-distribution and role-distribution summaries. Sources: live (default)
    or deploy agent files, root ARCHITECTURE.md (Model Roles + whitelists),
    live opencode.json (routing cross-check, WARN on mismatch). Formats:
    aligned table (default), markdown, JSON. STRICTLY READ-ONLY.

.PARAMETER Source
    Agents dir: live (default) or deploy-package/agents.

.PARAMETER Format
    Report body format: table (default), markdown, json.

.PARAMETER Agent
    Single-agent report (exact token-equal match; not found -> exit 2).

.PARAMETER Role
    Filter by Model Roles role (exact).

.PARAMETER Model
    Filter by model substring (case-insensitive).

.PARAMETER AgentsDir
    Explicit agents dir (overrides -Source; relative -> repo root).

.PARAMETER Arch
    ARCHITECTURE.md path (default: repo root).

.PARAMETER Config
    opencode.json for the routing cross-check (default: live; missing -> WARN skip).

.OUTPUTS
    STATUS:/WARN:/ERROR:/MODEL_DIST:/ROLE_DIST:/SUMMARY: lines or a JSON document

.NOTES
    Exit codes: 0 report generated (WARNs allowed), 2 usage/environment error.
    No exit 3: a report never gates. Read-only: never writes anything.

.EXAMPLE
    .\report.ps1
    .\report.ps1 -Format json
    .\report.ps1 -Role executor-cheap
    .\report.ps1 -Agent worker
#>

param(
    [string]$Source = 'live',
    [string]$Format = 'table',
    [string]$Agent = '',
    [string]$Role = '',
    [string]$Model = '',
    [string]$AgentsDir = '',
    [string]$Arch = '',
    [string]$Config = ''
)

$ErrorActionPreference = 'Stop'
# git emits UTF-8; keep non-ASCII repo paths intact.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Flag combination gates ------------------------------------------------
# NOTE: no [ValidateSet] - a PS binding error exits 1, spec requires exit 2.
if ($Source -ne '' -and $Source -ne 'live' -and $Source -ne 'deploy') {
    Write-Output "ERROR:USAGE invalid -Source value: $Source (expected live|deploy)"
    exit 2
}
if (-not $Source) { $Source = 'live' }
if ($Format -ne 'table' -and $Format -ne 'markdown' -and $Format -ne 'json') {
    Write-Output "ERROR:USAGE invalid -Format value: $Format (expected table|markdown|json)"
    exit 2
}
if ($Agent -and ($Role -or $Model)) {
    Write-Output 'ERROR:COMBINATION -Agent cannot be combined with -Role/-Model'
    exit 2
}
if ($Source -ne 'live' -and $AgentsDir) {
    Write-Output 'ERROR:COMBINATION -Source and -AgentsDir are mutually exclusive'
    exit 2
}

# --- Native command helper ----------------------------------------------
# Native stderr combined with $ErrorActionPreference='Stop' throws a
# terminating NativeCommandError before $LASTEXITCODE can be inspected.
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

# --- Frontmatter / table helpers ------------------------------------------
function Get-FmModel([string]$Text) {
    $m = [regex]::Match($Text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $m.Success) { return $null }
    $mm = [regex]::Match($m.Groups[1].Value, '(?m)^model:[ \t]*(.*)$')
    if (-not $mm.Success) { return $null }
    return $mm.Groups[1].Value.Trim()
}

function Split-Tokens([string]$Cell) {
    if (-not $Cell -or -not $Cell.Trim()) { return @() }
    return @($Cell -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Text of a section from a start heading to the next '## ' heading.
# '^## ' (space after ##) does NOT match '###' - subsections stay inside.
function Get-SectionText([string]$Text, [string]$StartPat, [string]$EndPat) {
    $m = [regex]::Match($Text, $StartPat, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $m.Success) { return $null }
    $after = $Text.Substring($m.Index + $m.Length)
    $e = [regex]::Match($after, $EndPat, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($e.Success) { return $after.Substring(0, $e.Index) }
    return $after
}

# Parser of the '## Model Roles' table: agent -> role/tier/archModel + ordered role rows.
function Get-ModelRoleMap([string]$ArchText) {
    $sec = Get-SectionText $ArchText '(?m)^## Model Roles' '(?m)^## '
    if ($null -eq $sec) { return $null }
    $map = @{}; $roles = @()
    foreach ($ln in ($sec -split '\r?\n')) {
        if ($ln -notmatch '^\|') { continue }
        $cells = @($ln.Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 5) { continue }
        $r = $cells[1]; $m = $cells[2]; $t = $cells[3]; $ags = $cells[4]
        if (-not $r -or $r -eq 'Role' -or $r -match '^-+$') { continue }
        if ($t -ne 'top' -and $t -ne 'mid' -and $t -ne 'low') { continue }
        $roles += , @{ Role = $r; Model = $m; Tier = $t }
        foreach ($a in (Split-Tokens $ags)) {
            $map[$a] = @{ Role = $r; Tier = $t; ArchModel = $m }
        }
    }
    if ($roles.Count -eq 0) { return $null }
    return @{ Map = $map; Roles = $roles }
}

# Agent names from a whitelist table (numbered rows under '### <Primary> Whitelist (N agents)').
function Get-WhitelistNames([string]$ArchText, [string]$Primary) {
    $headerPat = '(?m)^### ' + [regex]::Escape($Primary) + ' Whitelist \(\d+ agents\)'
    $hm = [regex]::Match($ArchText, $headerPat)
    if (-not $hm.Success) { return $null }
    $after = $ArchText.Substring($hm.Index + $hm.Length)
    $firstPipe = [regex]::Match($after, '(?m)^\|')
    if (-not $firstPipe.Success) { return @() }
    $rest = $after.Substring($firstPipe.Index)
    $blank = [regex]::Match($rest, '\r?\n[ \t]*\r?\n')
    $tbl = if ($blank.Success) { $rest.Substring(0, $blank.Index) } else { $rest }
    $names = @()
    foreach ($rm in [regex]::Matches($tbl, '(?m)^\|\s*\d+\s*\|\s*([^|]+?)\s*\|')) {
        $names += $rm.Groups[1].Value.Trim()
    }
    return $names
}

# Allow-key names from opencode.json agent.<primary>.permission.task.
function Get-TaskAllowNames($CfgObj, [string]$Primary) {
    try {
        $node = $CfgObj.agent.$Primary.permission.task
        if (-not $node) { return $null }
        return @($node.PSObject.Properties |
            Where-Object { $_.Name -ne '*' -and [string]$_.Value -eq 'allow' } |
            ForEach-Object { $_.Name })
    } catch { return $null }
}

# Mini-YAML: flatten the frontmatter 'permission:' block to dot-path pairs.
function Get-FmPermissionFlat([string]$Text) {
    $fm = [regex]::Match($Text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $fm.Success) { return @() }
    $out = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.List[object]  # @{Indent;Key}
    $inPerm = $false
    foreach ($ln in [regex]::Split($fm.Groups[1].Value, '\r?\n')) {
        $t = $ln.Trim()
        if (-not $t) { continue }
        $indent = $ln.Length - $ln.TrimStart().Length
        if (-not $inPerm) {
            if ($indent -eq 0 -and $t -match '^permission:\s*$') { $inPerm = $true }
            continue
        }
        if ($indent -eq 0) { break }   # next top-level key ends the block
        if ($t -notmatch '^("[^"]+"|[^:]+):\s*(.*)$') { continue }
        $key = $Matches[1].Trim('"')
        $val = $Matches[2].Trim().Trim('"')
        while ($stack.Count -gt 0 -and $stack[$stack.Count - 1].Indent -ge $indent) {
            $stack.RemoveAt($stack.Count - 1)
        }
        $path = ((@($stack | ForEach-Object { $_.Key })) + $key) -join '.'
        if ($val) { $out.Add("$path=$val") }
        else { $stack.Add(@{ Indent = $indent; Key = $key }) }
    }
    return @($out)
}

# Aligned ASCII table: +---+ borders, left-aligned cells.
function Format-AgentTable($Rows) {
    $cols = @('AGENT', 'MODEL', 'ROLE', 'TIER', 'MODE', 'ROUTE', 'PERMISSIONS')
    $w = @{}
    foreach ($c in $cols) { $w[$c] = $c.Length }
    foreach ($r in $Rows) { foreach ($c in $cols) {
        $l = ("$($r.$c)").Length; if ($l -gt $w[$c]) { $w[$c] = $l } } }
    $sep = '+' + (($cols | ForEach-Object { '-' * ($w[$_] + 2) }) -join '+') + '+'
    $lines = @($sep)
    $lines += '| ' + (($cols | ForEach-Object { $_.PadRight($w[$_]) }) -join ' | ') + ' |'
    $lines += $sep
    foreach ($r in $Rows) {
        $lines += '| ' + (($cols | ForEach-Object { ("$($r.$_)").PadRight($w[$_]) }) -join ' | ') + ' |'
    }
    $lines += $sep
    return $lines
}

# --- Paths ------------------------------------------------------------------
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy-package"))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}
$liveDir = Join-Path $env:USERPROFILE '.config\opencode'

if ($AgentsDir) {
    $agentsDir = $AgentsDir
    if (-not [System.IO.Path]::IsPathRooted($agentsDir)) { $agentsDir = Join-Path $repoRoot $agentsDir }
} elseif ($Source -eq 'deploy') {
    $agentsDir = Join-Path $repoRoot 'deploy-package\agents'
} else {
    $agentsDir = Join-Path $liveDir 'agents'
}
if (-not (Test-Path -LiteralPath $agentsDir -PathType Container)) {
    Write-Output "ERROR:ENV agents dir not found: $agentsDir"
    exit 2
}

$archPath = if ($Arch) { $Arch } else { Join-Path $repoRoot 'ARCHITECTURE.md' }
if (-not (Test-Path -LiteralPath $archPath -PathType Leaf)) {
    Write-Output "ERROR:ENV ARCHITECTURE.md not found: $archPath"
    exit 2
}
$archName = if ($Arch) { $Arch } else { 'ARCHITECTURE.md' }
$archText = (Read-RawText $archPath).Text

$roleInfo = Get-ModelRoleMap $archText
if (-not $roleInfo) {
    Write-Output 'ERROR:ANCHOR model_roles (## Model Roles table not parsed)'
    exit 2
}
$orchNames = Get-WhitelistNames $archText 'orchestrator'
if ($null -eq $orchNames) {
    Write-Output 'ERROR:ANCHOR whitelist_orchestrator (### orchestrator Whitelist header not found)'
    exit 2
}
$planNames = Get-WhitelistNames $archText 'plankestrator'
if ($null -eq $planNames) {
    Write-Output 'ERROR:ANCHOR whitelist_plankestrator (### plankestrator Whitelist header not found)'
    exit 2
}

# --- Routing cross-check (opencode.json vs ARCHITECTURE whitelists) ---------
$cfgPath = if ($Config) { $Config } else { Join-Path $liveDir 'opencode.json' }
$cfg = $null
if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
    try { $cfg = ((Read-RawText $cfgPath).Text | ConvertFrom-Json) } catch { $cfg = $null }
}
$routingWarns = @()
if ($cfg) {
    foreach ($prim in @('orchestrator', 'plankestrator')) {
        $archSet = if ($prim -eq 'orchestrator') { @($orchNames) } else { @($planNames) }
        # Get-TaskAllowNames returns $null when the node is absent; without the
        # filter @($null) is a 1-element array -> spurious WARN:ROUTING_MISMATCH
        # (PY mirror maps None -> [] explicitly).
        $jsonSet = @(Get-TaskAllowNames $cfg $prim | Where-Object { $null -ne $_ })
        $archOnly = @($archSet | Where-Object { $jsonSet -notcontains $_ })
        $jsonOnly = @($jsonSet | Where-Object { $archSet -notcontains $_ })
        if ($archOnly.Count -gt 0 -or $jsonOnly.Count -gt 0) {
            $routingWarns += ("WARN:ROUTING_MISMATCH primary={0} arch_only=[{1}] json_only=[{2}]" -f $prim, ($archOnly -join ','), ($jsonOnly -join ','))
        }
    }
} else {
    $routingWarns += 'WARN:CROSSCHECK_SKIPPED reason=opencode.json missing/unparsable'
}

# --- Scan agents ------------------------------------------------------------
# Ordinal (code-point) name order - matches the Python mirror and avoids
# culture-aware PowerShell sorting (which ignores hyphens).
$files = @(Get-ChildItem -LiteralPath $agentsDir -Filter '*.md' -File)
if ($files.Count -eq 0) {
    Write-Output "ERROR:ENV agents dir empty: $agentsDir"
    exit 2
}
$fileByName = @{}
foreach ($f in $files) { $fileByName[$f.BaseName] = $f }
$sortedNames = @($fileByName.Keys)
[Array]::Sort($sortedNames, [System.StringComparer]::Ordinal)

$warnings = @()
$allRows = @()
$modelsUsed = @{}
$routingOrch = @(); $routingPlan = @(); $routingBoth = @(); $routingNone = @()
foreach ($n in $sortedNames) {
    $f = $fileByName[$n]
    $name = $n
    $text = (Read-RawText $f.FullName).Text
    # NOTE: PS variables are case-insensitive - do NOT name locals
    # $model/$role (they would clobber the -Model/-Role parameters).
    $fmModel = Get-FmModel $text
    if (-not $fmModel) {
        $warnings += "WARN:FM_NO_MODEL agent=$name"
        $fmModel = '<missing>'
    } else {
        $modelsUsed[$fmModel] = $true
    }
    $mode = 'subagent'
    $fm = [regex]::Match($text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if ($fm.Success) {
        $mm = [regex]::Match($fm.Groups[1].Value, '(?m)^mode:[ \t]*(.*)$')
        if ($mm.Success -and $mm.Groups[1].Value.Trim()) { $mode = $mm.Groups[1].Value.Trim() }
    }
    $perms = @(Get-FmPermissionFlat $text)
    $fmRole = '<unmapped>'; $tier = '?'
    if ($roleInfo.Map.ContainsKey($name)) {
        $ri = $roleInfo.Map[$name]
        $fmRole = $ri.Role; $tier = $ri.Tier
        if ($fmModel -ne '<missing>' -and $ri.ArchModel -cne $fmModel) {
            $warnings += ("WARN:ROLE_MODEL_DRIFT agent={0} arch={1} frontmatter={2}" -f $name, $ri.ArchModel, $fmModel)
        }
    } else {
        $warnings += "WARN:ROLE_UNMAPPED agent=$name (not in Model Roles table)"
    }
    $inO = $orchNames -ccontains $name
    $inP = $planNames -ccontains $name
    if ($inO -and $inP) { $route = 'both'; $routingBoth += $name }
    elseif ($inO) { $route = 'orch'; $routingOrch += $name }
    elseif ($inP) { $route = 'plan'; $routingPlan += $name }
    else { $route = '-'; $routingNone += $name }
    $allRows += [pscustomobject]@{
        AGENT = $name; MODEL = $fmModel; ROLE = $fmRole; TIER = $tier
        MODE = $mode; ROUTE = $route; PERMLIST = $perms
    }
}
$warnings += $routingWarns

# --- Distributions (FULL fleet, computed before filters) ---------------------
$mdGroups = @{}
foreach ($r in $allRows) {
    if ($r.MODEL -eq '<missing>') { continue }
    if (-not $mdGroups.ContainsKey($r.MODEL)) { $mdGroups[$r.MODEL] = @() }
    $mdGroups[$r.MODEL] += $r.AGENT
}
$modelKeys = @($mdGroups.Keys)
[Array]::Sort($modelKeys, [System.StringComparer]::Ordinal)
# count desc, then model asc (ordinal) - deterministic, matches the PY mirror
$byCount = @{}
foreach ($k in $modelKeys) { $byCount[$mdGroups[$k].Count] += , @{ Model = $k; Count = $mdGroups[$k].Count; Agents = @($mdGroups[$k]) } }
$cntKeys = @($byCount.Keys)
[Array]::Sort($cntKeys)
[Array]::Reverse($cntKeys)
$modelDist = @()
foreach ($ck in $cntKeys) { foreach ($d in $byCount[$ck]) { $modelDist += , $d } }

$roleDist = @()
foreach ($rr in $roleInfo.Roles) {
    $members = @($allRows | Where-Object { $_.ROLE -eq $rr.Role } | ForEach-Object { $_.AGENT })
    $roleDist += , @{ Role = $rr.Role; Tier = $rr.Tier; Count = $members.Count; Agents = $members }
}

# --- Filters (body only; distributions above are already full-fleet) ----------
$shownRows = $allRows
if ($Agent) {
    $shownRows = @($shownRows | Where-Object { $_.AGENT -ceq $Agent })
    if ($shownRows.Count -eq 0) {
        Write-Output "ERROR:AGENT_NOT_FOUND name=$Agent (token-exact match failed)"
        exit 2
    }
}
if ($Role) { $shownRows = @($shownRows | Where-Object { $_.ROLE -ceq $Role }) }
if ($Model) { $shownRows = @($shownRows | Where-Object { $_.MODEL.IndexOf($Model, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }) }

$unmapped = @($allRows | Where-Object { $_.ROLE -eq '<unmapped>' }).Count

# --- Render ------------------------------------------------------------------
$genUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

if ($Format -eq 'json') {
    $agentsJson = @()
    foreach ($r in $allRows) {
        $permObj = [ordered]@{}
        foreach ($p in $r.PERMLIST) {
            $eq = $p.IndexOf('=')
            if ($eq -gt 0) { $permObj[$p.Substring(0, $eq)] = $p.Substring($eq + 1) }
        }
        $agentsJson += , [ordered]@{
            name = $r.AGENT; model = $r.MODEL; role = $r.ROLE; tier = $r.TIER
            mode = $r.MODE; routing = $r.ROUTE; permissions = $permObj
        }
    }
    $doc = [ordered]@{
        generated_utc = $genUtc
        source        = $Source
        agents_dir    = $agentsDir
        agents        = $agentsJson
        model_dist    = @($modelDist | ForEach-Object { [ordered]@{ model = $_.Model; count = $_.Count; agents = $_.Agents } })
        role_dist     = @($roleDist | ForEach-Object { [ordered]@{ role = $_.Role; tier = $_.Tier; count = $_.Count; agents = $_.Agents } })
        routing       = [ordered]@{ orchestrator = $routingOrch; plankestrator = $routingPlan; both = $routingBoth; none = $routingNone }
        warnings      = $warnings
        summary       = [ordered]@{
            agents = $allRows.Count; shown = $shownRows.Count; models = $modelDist.Count
            roles = $roleInfo.Roles.Count; orch = $routingOrch.Count; plan = $routingPlan.Count
            both = $routingBoth.Count; none = $routingNone.Count
            unmapped = $unmapped; warn = $warnings.Count
        }
    }
    $doc | ConvertTo-Json -Depth 6
    exit 0
}

Write-Output ("STATUS:REPORT_START source={0} agents={1} arch={2}" -f $Source, $allRows.Count, $archName)
foreach ($w in $warnings) { Write-Output $w }

if ($Format -eq 'table') {
    $tableRows = @()
    foreach ($r in $shownRows) {
        $pairs = $r.PERMLIST
        $permStr = ($pairs -join '; ')
        if ($pairs.Count -gt 6) {
            $permStr = (($pairs | Select-Object -First 6) -join '; ') + ("+{0}" -f ($pairs.Count - 6))
        }
        $tableRows += [pscustomobject]@{
            AGENT = $r.AGENT; MODEL = $r.MODEL; ROLE = $r.ROLE; TIER = $r.TIER
            MODE = $r.MODE; ROUTE = $r.ROUTE; PERMISSIONS = $permStr
        }
    }
    foreach ($l in (Format-AgentTable $tableRows)) { Write-Output $l }
    Write-Output '== MODEL DISTRIBUTION =='
    foreach ($d in $modelDist) {
        Write-Output ("MODEL_DIST:{0} count={1} agents={2}" -f $d.Model, $d.Count, ($d.Agents -join ','))
    }
    Write-Output '== ROLE DISTRIBUTION =='
    foreach ($d in $roleDist) {
        Write-Output ("ROLE_DIST:{0} tier={1} count={2} agents={3}" -f $d.Role, $d.Tier, $d.Count, ($d.Agents -join ','))
    }
} else {
    # markdown
    Write-Output '## Agents'
    Write-Output ''
    Write-Output '| AGENT | MODEL | ROLE | TIER | MODE | ROUTE | PERMISSIONS |'
    Write-Output '|---|---|---|---|---|---|---|'
    foreach ($r in $shownRows) {
        Write-Output ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $r.AGENT, $r.MODEL, $r.ROLE, $r.TIER, $r.MODE, $r.ROUTE, ($r.PERMLIST -join '; '))
    }
    Write-Output ''
    Write-Output '## Model distribution'
    Write-Output ''
    Write-Output '| MODEL | COUNT | AGENTS |'
    Write-Output '|---|---|---|'
    foreach ($d in $modelDist) {
        Write-Output ("| {0} | {1} | {2} |" -f $d.Model, $d.Count, ($d.Agents -join ', '))
    }
    Write-Output ''
    Write-Output '## Role distribution'
    Write-Output ''
    Write-Output '| ROLE | TIER | COUNT | AGENTS |'
    Write-Output '|---|---|---|---|'
    foreach ($d in $roleDist) {
        Write-Output ("| {0} | {1} | {2} | {3} |" -f $d.Role, $d.Tier, $d.Count, ($d.Agents -join ', '))
    }
    Write-Output ''
    foreach ($d in $modelDist) {
        Write-Output ("MODEL_DIST:{0} count={1} agents={2}" -f $d.Model, $d.Count, ($d.Agents -join ','))
    }
    foreach ($d in $roleDist) {
        Write-Output ("ROLE_DIST:{0} tier={1} count={2} agents={3}" -f $d.Role, $d.Tier, $d.Count, ($d.Agents -join ','))
    }
}

Write-Output ("SUMMARY:agents={0} shown={1} models={2} roles={3} orch={4} plan={5} both={6} none={7} unmapped={8} warn={9}" -f `
    $allRows.Count, $shownRows.Count, $modelDist.Count, $roleInfo.Roles.Count, `
    $routingOrch.Count, $routingPlan.Count, $routingBoth.Count, $routingNone.Count, `
    $unmapped, $warnings.Count)
Write-Output 'STATUS:SUCCESS'
exit 0
