<#
.SYNOPSIS
    Fast LLM-free ASCII visualization of all orchestration pipelines.

.DESCRIPTION
    Parses root ARCHITECTURE.md section '## 2. Pipelines' and renders every
    pipeline as an ASCII step-chain diagram; each agent step is annotated with
    its frontmatter model key and Model Roles role/tier. Prewalk pairs
    (planner-role step handing off to an equal-or-cheaper tier) are highlighted
    with '==>', tier drops with '~->', inversions with '!->'. Rework loops and
    parallel waves render as grouped LOOP/WAVE nodes. Notation examples,
    the DEV decision tree and the Auto-DOCS hook section are excluded.
    Formats: ascii (default), markdown, json. STRICTLY READ-ONLY.

.PARAMETER Pipeline
    Render only pipelines whose label contains the substring (case-insensitive).

.PARAMETER Format
    Output format: ascii (default), markdown, json.

.PARAMETER Source
    Agents dir for models: live (default) or deploy-package/agents.

.PARAMETER AgentsDir
    Explicit agents dir (overrides -Source).

.PARAMETER NoModels
    Compact boxes: index+name and tier only.

.PARAMETER Arch
    ARCHITECTURE.md path (default: repo root).

.OUTPUTS
    STATUS:/PIPELINE:/PREWALK:/INFO:/WARN:/ERROR:/SUMMARY: lines or a JSON document

.NOTES
    Exit codes: 0 rendered (WARN/INFO allowed), 2 usage/environment error.
    No exit 3: visualization does not gate. Output is ASCII-only (unicode
    arrows U+2192/U+2225 are INPUT syntax, never printed).

.EXAMPLE
    .\visualize.ps1
    .\visualize.ps1 -Pipeline "DEV COMPLEX"
    .\visualize.ps1 -Format json
#>

param(
    [string]$Pipeline = '',
    [string]$Format = 'ascii',
    [string]$Source = 'live',
    [string]$AgentsDir = '',
    [switch]$NoModels,
    [string]$Arch = ''
)

$ErrorActionPreference = 'Stop'
# git emits UTF-8; keep non-ASCII repo paths intact.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Constants (script top: update together with SKILL.md when section 2 changes) ---
# Unicode arrows WITHOUT literals in the source (PS 5.1 reads BOM-less .ps1 as ANSI).
$Arrow = [string][char]0x2192          # U+2192 input syntax only, never printed
$Par = [string][char]0x2225            # U+2225 (parallel wave separator)
$script:SkipHeadings = @('Pipeline Notation', 'DEV Complexity Classification', 'Auto-DOCS Hook')
$script:ExpectedLabels = @('BUGFIX (SIMPLE)', 'BUGFIX DEEP', 'DEV SIMPLE', 'DEV COMPLEX',
                           'DEV SUPERCOMPLEX', 'DEVOPS', 'DOCS', 'PLAN', 'RESEARCH')
$script:TierRank = @{ 'low' = 1; 'mid' = 2; 'top' = 3 }

# --- Flag combination gate ---------------------------------------------------
# NOTE: no [ValidateSet] - a PS binding error exits 1, spec requires exit 2.
if ($Source -ne '' -and $Source -ne 'live' -and $Source -ne 'deploy') {
    Write-Output "ERROR:USAGE invalid -Source value: $Source (expected live|deploy)"
    exit 2
}
if (-not $Source) { $Source = 'live' }
if ($Format -ne 'ascii' -and $Format -ne 'markdown' -and $Format -ne 'json') {
    Write-Output "ERROR:USAGE invalid -Format value: $Format (expected ascii|markdown|json)"
    exit 2
}
if ($Source -ne 'live' -and $AgentsDir) {
    Write-Output 'ERROR:COMBINATION -Source and -AgentsDir are mutually exclusive'
    exit 2
}

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

function Split-ModelKey([string]$Full) {
    if (-not $Full) { return $null }
    $idx = $Full.IndexOf('/')
    if ($idx -lt 1 -or $idx -ge ($Full.Length - 1)) { return $null }
    return @{ Provider = $Full.Substring(0, $idx); Key = $Full.Substring($idx + 1) }
}

function Split-Tokens([string]$Cell) {
    if (-not $Cell -or -not $Cell.Trim()) { return @() }
    return @($Cell -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-SectionText([string]$Text, [string]$StartPat, [string]$EndPat) {
    $m = [regex]::Match($Text, $StartPat, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $m.Success) { return $null }
    $after = $Text.Substring($m.Index + $m.Length)
    $e = [regex]::Match($after, $EndPat, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($e.Success) { return $after.Substring(0, $e.Index) }
    return $after
}

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

# --- Section 2 chain scanner -------------------------------------------------
# Returns a list of @{Label;Variant;Raw} raw chains. Highlights:
#   - a line STARTING with an arrow continues the previous chain (multi-line fences);
#   - an arrow-free head line directly before an arrow-initial line is glued to it
#     (pending head: the DOCS DEEP fence head carries no arrow of its own);
#   - table rows (leading '|'): first arrow-free cell = variant label, arrow cells = chain
#     (the DEV SIMPLE variant table);
#   - TRIAGE_RESULT lines reset the buffer and are never chain material.
function Get-PipelineChains([string]$SecText) {
    $chains = @()
    $label = ''; $skip = $false
    $buf = $null; $pending = $null
    foreach ($ln in ($SecText -split '\r?\n')) {
        if ($ln -match '^###\s+(.+?)\s*$') {
            if ($buf) { $chains += , $buf; $buf = $null }
            $label = $Matches[1]
            $skip = $false
            foreach ($sh in $script:SkipHeadings) { if ($label.StartsWith($sh)) { $skip = $true } }
            $pending = $null
            continue
        }
        if ($skip) { continue }
        if ($ln -match 'TRIAGE_RESULT') {
            if ($buf) { $chains += , $buf; $buf = $null }
            $pending = $null
            continue
        }
        $t = $ln.Trim()
        if (-not $t) { continue }
        $t = $t -replace '^[-*]\s+', ''
        $t = $t -replace '`', ''
        $t = $t -replace '\*\*', ''
        if (-not $t) { continue }
        if ($t.StartsWith('|')) {
            $cells = @($t.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $arrowCells = @($cells | Where-Object { [regex]::IsMatch($_, '\u2192|->') })
            if ($arrowCells.Count -ge 1) {
                if ($buf) { $chains += , $buf; $buf = $null }
                $headCell = ''
                foreach ($c in $cells) {
                    if (-not [regex]::IsMatch($c, '\u2192|->')) { $headCell = $c; break }
                }
                $buf = @{ Label = $label; Variant = $headCell; Raw = ($arrowCells -join ' ') }
            }
            $pending = $null
            continue
        }
        $isCont = [regex]::IsMatch($t, '^(?:\u2192|->)')
        $hasArrow = [regex]::IsMatch($t, '\u2192|->')
        if ($isCont) {
            if ($buf) { $buf.Raw = $buf.Raw + ' ' + $t; continue }
            if ($pending) {
                $buf = @{ Label = $label; Variant = $pending.Variant; Raw = $pending.Raw + ' ' + $t }
                $pending = $null
                continue
            }
            $buf = @{ Label = $label; Variant = ''; Raw = $t }
            continue
        }
        if ($buf) { $chains += , $buf; $buf = $null }
        $variant = ''; $raw = $t
        $vm = [regex]::Match($t, '^([^\u2192:]{1,60}):\s*(.+)$')
        if ($vm.Success) { $variant = $vm.Groups[1].Value.Trim(); $raw = $vm.Groups[2].Value }
        if ($hasArrow) {
            $buf = @{ Label = $label; Variant = $variant; Raw = $raw }
            $pending = $null
        } else {
            $pending = @{ Variant = $variant; Raw = $raw }
        }
    }
    if ($buf) { $chains += , $buf }
    return $chains
}

# --- Chain -> node list -------------------------------------------------------
# Loops become <<Ln>> placeholders (inner arrows kept INSIDE), waves <<Wn>>;
# parentheticals and junk punctuation are dropped; tokens are split by arrows
# and classified token-exact: agent / wildcard / pseudo / loop / wave.
function Convert-RawToNodes([string]$Raw, [string[]]$AgentNames) {
    $loops = @{}; $waves = @{}
    $i = 0
    while (($idx = $Raw.IndexOf('[rework loop:')) -ge 0) {
        $end = $Raw.IndexOf(']', $idx)
        if ($end -lt 0) { break }
        $inner = $Raw.Substring($idx + 13, $end - $idx - 13)
        $loops["L$i"] = $inner.Trim()
        $Raw = $Raw.Remove($idx, $end - $idx + 1).Insert($idx, "<<L$i>>")
        $i++
    }
    $i = 0
    while ($true) {
        $m = [regex]::Match($Raw, '\[[^\[\]]*\u2225[^\[\]]*\]')
        if (-not $m.Success) { break }
        $waves["W$i"] = $m.Value.Substring(1, $m.Value.Length - 2)
        $Raw = $Raw.Remove($m.Index, $m.Length).Insert($m.Index, "<<W$i>>")
        $i++
    }
    $Raw = [regex]::Replace($Raw, '\([^)]*\)', '')
    $Raw = $Raw -replace '[\[\]"]', ''
    $parts = [regex]::Split($Raw, '\s*(?:\u2192|->)\s*')
    $nodes = @()
    foreach ($p in $parts) {
        $s = $p.Trim().Trim(',').Trim()
        if (-not $s) { continue }
        if ($s -match '^<<L(\d+)>>$') {
            $inner = $loops["L$($Matches[1])"]
            $mm = [regex]::Match($inner, ',?\s*max\s+(\d+)\s*$')
            $maxN = 0; $body = $inner
            if ($mm.Success) { $maxN = [int]$mm.Groups[1].Value; $body = $inner.Substring(0, $mm.Index).Trim() }
            $nodes += , @{ Kind = 'loop'; Text = $body; Max = $maxN }
            continue
        }
        if ($s -match '^<<W(\d+)>>$') {
            $members = @($waves["W$($Matches[1])"] -split '\u2225' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $nodes += , @{ Kind = 'wave'; Members = $members }
            continue
        }
        if ($s -cmatch '^[a-z][a-z0-9-]*$' -and $AgentNames -ccontains $s) {
            $nodes += , @{ Kind = 'agent'; Name = $s }
            continue
        }
        if ($s -match '^([a-z][a-z0-9-]+)-\*$') {
            $prefix = $Matches[1] + '-'
            $hits = @($AgentNames | Where-Object { $_.StartsWith($prefix) })
            if ($hits.Count -ge 1) { $nodes += , @{ Kind = 'wildcard'; Name = $s; Matches = $hits }; continue }
        }
        $nodes += , @{ Kind = 'pseudo'; Name = $s }
    }
    return $nodes
}

# --- Prewalk / inversion / tier-drop detector ---------------------------------
function Get-PrewalkPairs($Nodes, $RoleMap) {
    $pairs = @()
    for ($i = 0; $i -lt $Nodes.Count - 1; $i++) {
        $a = $Nodes[$i]; $b = $Nodes[$i + 1]
        if ($a.Kind -ne 'agent' -or $b.Kind -ne 'agent') { continue }
        if (-not $RoleMap.ContainsKey($a.Name) -or -not $RoleMap.ContainsKey($b.Name)) { continue }
        $ra = $RoleMap[$a.Name]; $rb = $RoleMap[$b.Name]
        if (-not $script:TierRank.ContainsKey($ra.Tier) -or -not $script:TierRank.ContainsKey($rb.Tier)) { continue }
        $ta = $script:TierRank[$ra.Tier]; $tb = $script:TierRank[$rb.Tier]
        $isPlanner = ($ra.Role.StartsWith('plan') -or $ra.Role -eq 'docs-plan')
        if ($isPlanner -and $ta -ge $tb) { $pairs += , @{ Kind = 'prewalk';   I = $i; A = $a.Name; B = $b.Name } }
        elseif ($isPlanner)              { $pairs += , @{ Kind = 'inversion'; I = $i; A = $a.Name; B = $b.Name } }
        elseif ($ta -gt $tb)             { $pairs += , @{ Kind = 'drop';      I = $i; A = $a.Name; B = $b.Name } }
    }
    return $pairs
}

# --- ASCII rendering ------------------------------------------------------------
function Render-NodeBox($Node, $Idx, $Info, [bool]$NoModels) {
    $content = @()
    switch ($Node.Kind) {
        'agent' {
            $content += "$Idx. $($Node.Name)"
            if (-not $NoModels) {
                $mk = '-'
                if ($Info.Model) {
                    $sp = Split-ModelKey $Info.Model
                    if ($sp) { $mk = $sp.Key }
                }
                $content += $mk
            }
            $tier = '?'
            if ($Info.Tier) { $tier = $Info.Tier }
            $content += $tier
        }
        'wildcard' {
            $content += "$Idx. $($Node.Name)"
            $content += "$(@($Node.Matches).Count) agents"
        }
        'pseudo' { $content += "$($Node.Name)" }
        'loop' {
            $txt = [string]$Node.Text
            $txt = $txt.Replace([string][char]0x2192, '->')
            $content += "LOOP max $($Node.Max):"
            $content += $txt
        }
        'wave' {
            $content += 'WAVE (parallel):'
            $content += (@($Node.Members) -join ' | ')
        }
    }
    $inner = 0
    foreach ($c in $content) { if ($c.Length -gt $inner) { $inner = $c.Length } }
    $boxed = @()
    $boxed += '+' + ('-' * ($inner + 2)) + '+'
    foreach ($c in $content) { $boxed += '| ' + $c.PadRight($inner) + ' |' }
    $boxed += '+' + ('-' * ($inner + 2)) + '+'
    return @{ Lines = @($boxed); Height = $boxed.Count }
}

function Join-Boxes([object[]]$Boxes, [string[]]$Conns) {
    $maxH = 0
    foreach ($b in $Boxes) { if ($b.Height -gt $maxH) { $maxH = $b.Height } }
    $mid = [int][Math]::Floor(($maxH - 1) / 2)
    $lines = @()
    for ($h = 0; $h -lt $maxH; $h++) {
        $row = ''
        for ($i = 0; $i -lt $Boxes.Count; $i++) {
            $bl = $Boxes[$i].Lines
            if ($h -lt $bl.Count) { $row += $bl[$h] }
            else { $row += (' ' * $bl[0].Length) }
            if ($i -lt ($Boxes.Count - 1)) {
                if ($h -eq $mid) { $row += $Conns[$i] } else { $row += '     ' }
            }
        }
        $lines += $row
    }
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

$archPath = if ($Arch) { $Arch } else { Join-Path $repoRoot 'ARCHITECTURE.md' }
$archName = if ($Arch) { $Arch } else { 'ARCHITECTURE.md' }
if (-not (Test-Path -LiteralPath $archPath -PathType Leaf)) {
    Write-Output "ERROR:ENV ARCHITECTURE.md not found: $archPath"
    exit 2
}
$archText = (Read-RawText $archPath).Text

$sec2 = Get-SectionText $archText '(?m)^## 2\. Pipelines' '(?m)^## '
if ($null -eq $sec2) {
    Write-Output 'ERROR:ANCHOR pipelines (## 2. Pipelines section not found)'
    exit 2
}
$roleInfo = Get-ModelRoleMap $archText
if (-not $roleInfo) {
    Write-Output 'ERROR:ANCHOR model_roles (## Model Roles table not parsed)'
    exit 2
}

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
$agentFiles = @(Get-ChildItem -LiteralPath $agentsDir -Filter '*.md' -File)
if ($agentFiles.Count -eq 0) {
    Write-Output "ERROR:ENV agents dir empty: $agentsDir"
    exit 2
}
$agentNames = @($agentFiles | ForEach-Object { $_.BaseName })
[Array]::Sort($agentNames, [System.StringComparer]::Ordinal)
$modelByName = @{}
foreach ($af in $agentFiles) { $modelByName[$af.BaseName] = (Get-FmModel (Read-RawText $af.FullName).Text) }

# --- Parse chains -> pipelines --------------------------------------------------
$parsed = @()
$seenSeq = @{}
foreach ($chain in (Get-PipelineChains $sec2)) {
    $nodes = Convert-RawToNodes $chain.Raw $agentNames
    if ($nodes.Count -lt 2) { continue }
    # at least one agent/wildcard-resolved token; a wave counts when any of
    # its members is a real agent name (the RESEARCH fan-out has no bare agents)
    $resolvedCount = 0
    foreach ($nd in $nodes) {
        if ($nd.Kind -eq 'agent' -or $nd.Kind -eq 'wildcard') { $resolvedCount++ }
        elseif ($nd.Kind -eq 'wave') {
            foreach ($mem in @($nd.Members)) { if ($AgentNames -ccontains $mem) { $resolvedCount++; break } }
        }
    }
    if ($resolvedCount -eq 0) { continue }
    # NOTE: inside a PS 'switch' block $_ is the switch VALUE - use $nd explicitly.
    $seqParts = @()
    foreach ($nd in $nodes) {
        switch ($nd.Kind) {
            'agent'    { $seqParts += , ('a:' + $nd.Name) }
            'wildcard' { $seqParts += , ('w:' + $nd.Name) }
            'pseudo'   { $seqParts += , ('p:' + $nd.Name) }
            'loop'     { $seqParts += , ('l:' + $nd.Max + ':' + $nd.Text) }
            'wave'     { $seqParts += , ('W:' + ($nd.Members -join '|')) }
        }
    }
    $seqKey = $seqParts -join ' > '
    if ($seenSeq.ContainsKey($seqKey)) { continue }
    $seenSeq[$seqKey] = $true
    $disp = $chain.Label
    if ($chain.Variant) { $disp = $chain.Variant }
    $parsed += , @{ Label = $disp; Nodes = $nodes }
}

# Duplicate display labels get ' #N' suffixes (appearance order)
$labelCount = @{}
foreach ($pl in $parsed) {
    if (-not $labelCount.ContainsKey($pl.Label)) { $labelCount[$pl.Label] = 0 }
    $labelCount[$pl.Label]++
    if ($labelCount[$pl.Label] -gt 1) { $pl.Label = "$($pl.Label) #$($labelCount[$pl.Label])" }
}

# Expected-label check (case-insensitive substring over parsed labels)
$globalWarns = @()
foreach ($exp in $script:ExpectedLabels) {
    $found = $false
    foreach ($pl in $parsed) {
        if ($pl.Label.ToLowerInvariant().Contains($exp.ToLowerInvariant())) { $found = $true; break }
    }
    if (-not $found) { $globalWarns += "WARN:PIPELINE_NOT_FOUND name=$exp" }
}

# -Pipeline filter
$renderList = $parsed
if ($Pipeline) {
    $renderList = @($parsed | Where-Object { $_.Label.ToLowerInvariant().Contains($Pipeline.ToLowerInvariant()) })
    if ($renderList.Count -eq 0) {
        Write-Output "ERROR:NO_MATCH no pipeline label contains: $Pipeline"
        exit 2
    }
}

$genUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# --- Enrich + collect ------------------------------------------------------------
$blocks = @()
$sumSteps = 0; $sumAgents = 0; $sumPseudo = 0; $sumLoops = 0; $sumWaves = 0
$sumPrewalk = 0; $sumInv = 0; $sumDrops = 0; $sumUnresolved = 0
foreach ($pl in $renderList) {
    $warns = @()
    $boxes = @(); $conns = @()
    $idx = 0
    $jsonSteps = @()
    foreach ($nd in $pl.Nodes) {
        $idx++
        $info = @{ Model = $null; Role = $null; Tier = $null }
        $dispName = ''
        $loopObj = $null; $waveObj = $null
        switch ($nd.Kind) {
            'agent' {
                $dispName = $nd.Name
                if ($modelByName.ContainsKey($nd.Name)) { $info.Model = $modelByName[$nd.Name] }
                if (-not $info.Model) { $warns += "WARN:STEP_NO_MODEL pipeline=$($pl.Label) step=$($nd.Name)" }
                if ($roleInfo.Map.ContainsKey($nd.Name)) {
                    $info.Role = $roleInfo.Map[$nd.Name].Role
                    $info.Tier = $roleInfo.Map[$nd.Name].Tier
                } else {
                    $warns += "WARN:ROLE_UNMAPPED pipeline=$($pl.Label) step=$($nd.Name)"
                }
            }
            'wildcard' {
                $dispName = $nd.Name
                $warns += ("WARN:STEP_UNRESOLVED pipeline={0} step={1} kind=wildcard matches={2}" -f $pl.Label, $nd.Name, @($nd.Matches).Count)
            }
            'pseudo' {
                $dispName = $nd.Name
                $warns += "WARN:STEP_UNRESOLVED pipeline=$($pl.Label) step=$($nd.Name) kind=pseudo"
            }
            'loop' {
                $txt = ([string]$nd.Text).Replace([string][char]0x2192, '->')
                $loopObj = @{ text = $txt; max = $nd.Max }
                $dispName = $txt
            }
            'wave' {
                $waveObj = @($nd.Members)
                $dispName = (@($nd.Members) -join ' | ')
            }
        }
        $dispModel = $null
        if ($info.Model) {
            $sp = Split-ModelKey $info.Model
            if ($sp) { $dispModel = $sp.Key }
        }
        $jsonSteps += , @{ kind = $nd.Kind; name = $dispName; model = $dispModel
                           role = $info.Role; tier = $info.Tier; loop = $loopObj; wave = $waveObj }
        $boxes += , (Render-NodeBox $nd $idx $info ([bool]$NoModels))
    }
    $pairs = Get-PrewalkPairs $pl.Nodes $roleInfo.Map
    for ($i = 0; $i -lt ($boxes.Count - 1); $i++) {
        $conn = ' --> '
        foreach ($pr in $pairs) {
            if ($pr.I -ne $i) { continue }
            if ($pr.Kind -eq 'prewalk') { $conn = ' ==> ' }
            elseif ($pr.Kind -eq 'inversion') { $conn = ' !-> ' }
            elseif ($pr.Kind -eq 'drop') { $conn = ' ~-> ' }
        }
        $conns += $conn
    }
    $diagram = Join-Boxes $boxes $conns

    $nAgents = @($pl.Nodes | Where-Object { $_.Kind -eq 'agent' }).Count
    $nPseudo = @($pl.Nodes | Where-Object { $_.Kind -eq 'pseudo' }).Count
    $nLoops = @($pl.Nodes | Where-Object { $_.Kind -eq 'loop' }).Count
    $nWaves = @($pl.Nodes | Where-Object { $_.Kind -eq 'wave' }).Count
    $nPre = @($pairs | Where-Object { $_.Kind -eq 'prewalk' }).Count
    $nInv = @($pairs | Where-Object { $_.Kind -eq 'inversion' }).Count
    $nDrop = @($pairs | Where-Object { $_.Kind -eq 'drop' }).Count

    $blocks += , @{
        Label = $pl.Label; Diagram = $diagram; Steps = $jsonSteps
        Pairs = $pairs; Warns = $warns
        N = $pl.Nodes.Count; NAgents = $nAgents; NPseudo = $nPseudo
        NLoops = $nLoops; NWaves = $nWaves; NPre = $nPre; NInv = $nInv; NDrop = $nDrop
    }
    $sumSteps += $pl.Nodes.Count; $sumAgents += $nAgents; $sumPseudo += $nPseudo
    $sumLoops += $nLoops; $sumWaves += $nWaves
    $sumPrewalk += $nPre; $sumInv += $nInv; $sumDrops += $nDrop
    $sumUnresolved += @($warns | Where-Object { $_ -like 'WARN:STEP_UNRESOLVED*' }).Count
}
$totalWarn = $globalWarns.Count
foreach ($b in $blocks) { $totalWarn += $b.Warns.Count }

# --- Render ---------------------------------------------------------------------
if ($Format -eq 'json') {
    $plJson = @()
    foreach ($b in $blocks) {
        $preArr = @(); $dropArr = @()
        foreach ($pr in $b.Pairs) {
            $entry = @{ from = $pr.A; to = $pr.B
                        from_tier = $roleInfo.Map[$pr.A].Tier; to_tier = $roleInfo.Map[$pr.B].Tier }
            if ($pr.Kind -eq 'prewalk') { $preArr += , $entry }
            elseif ($pr.Kind -eq 'drop') { $dropArr += , $entry }
        }
        $plJson += , @{ label = $b.Label; steps = $b.Steps; prewalk = $preArr; tier_drops = $dropArr }
    }
    $allWarns = @($globalWarns)
    foreach ($b in $blocks) { $allWarns += $b.Warns }
    $doc = [ordered]@{
        generated_utc = $genUtc
        arch = $archName
        source = $Source
        pipelines = $plJson
        warnings = $allWarns
        summary = [ordered]@{
            pipelines = $blocks.Count; steps = $sumSteps; agents = $sumAgents
            pseudo = $sumPseudo; loops = $sumLoops; waves = $sumWaves
            prewalk = $sumPrewalk; inversions = $sumInv; drops = $sumDrops
            unresolved = $sumUnresolved; warn = $totalWarn
        }
    }
    $doc | ConvertTo-Json -Depth 8
    exit 0
}

Write-Output ("STATUS:VIS_START arch={0} pipelines={1} agents_source={2}" -f $archName, $parsed.Count, $Source)
foreach ($w in $globalWarns) { Write-Output $w }

foreach ($b in $blocks) {
    if ($Format -eq 'markdown') {
        Write-Output "### $($b.Label)"
        Write-Output ''
        Write-Output '```text'
    } else {
        Write-Output "=== $($b.Label) ($($b.N) steps) ==="
    }
    foreach ($l in $b.Diagram) { Write-Output $l }
    if ($Format -eq 'markdown') {
        Write-Output '```'
        Write-Output ''
        Write-Output '| # | Step | Kind | Model | Role | Tier |'
        Write-Output '|---|---|---|---|---|---|'
        $si = 0
        foreach ($st in $b.Steps) {
            $si++
            $m = if ($null -ne $st.model) { $st.model } else { '-' }
            $r = if ($null -ne $st.role) { $st.role } else { '-' }
            $t = if ($null -ne $st.tier) { $st.tier } else { '-' }
            Write-Output ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $si, $st.name, $st.kind, $m, $r, $t)
        }
        Write-Output ''
        $pre = @($b.Pairs | Where-Object { $_.Kind -eq 'prewalk' })
        if ($pre.Count -gt 0) {
            Write-Output '**Prewalk:**'
            foreach ($pr in $pre) {
                Write-Output ("- {0}({1},{2}) ==> {3}({4},{5})" -f $pr.A, $roleInfo.Map[$pr.A].Role, $roleInfo.Map[$pr.A].Tier, $pr.B, $roleInfo.Map[$pr.B].Role, $roleInfo.Map[$pr.B].Tier)
            }
        }
        $dr = @($b.Pairs | Where-Object { $_.Kind -eq 'drop' })
        if ($dr.Count -gt 0) {
            Write-Output '**Tier drops:**'
            foreach ($pr in $dr) {
                Write-Output ("- {0}({1}) -> {2}({3})" -f $pr.A, $roleInfo.Map[$pr.A].Tier, $pr.B, $roleInfo.Map[$pr.B].Tier)
            }
        }
        Write-Output ''
    }
    Write-Output ("PIPELINE:{0} steps={1} agents={2} pseudo={3} loops={4} waves={5} prewalk={6} drops={7}" -f `
        $b.Label, $b.N, $b.NAgents, $b.NPseudo, $b.NLoops, $b.NWaves, $b.NPre, $b.NDrop)
    foreach ($pr in $b.Pairs) {
        if ($pr.Kind -eq 'prewalk') {
            Write-Output ("PREWALK:{0} {1}({2},{3}) ==> {4}({5},{6})" -f $b.Label, $pr.A, $roleInfo.Map[$pr.A].Role, $roleInfo.Map[$pr.A].Tier, $pr.B, $roleInfo.Map[$pr.B].Role, $roleInfo.Map[$pr.B].Tier)
        } elseif ($pr.Kind -eq 'inversion') {
            Write-Output ("WARN:PREWALK_INVERSION:{0} {1}({2},{3}) !-> {4}({5},{6})" -f $b.Label, $pr.A, $roleInfo.Map[$pr.A].Role, $roleInfo.Map[$pr.A].Tier, $pr.B, $roleInfo.Map[$pr.B].Role, $roleInfo.Map[$pr.B].Tier)
        } elseif ($pr.Kind -eq 'drop') {
            Write-Output ("INFO:TIER_DROP:{0} {1}({2}) -> {3}({4})" -f $b.Label, $pr.A, $roleInfo.Map[$pr.A].Tier, $pr.B, $roleInfo.Map[$pr.B].Tier)
        }
    }
    foreach ($w in $b.Warns) { Write-Output $w }
}

Write-Output 'LEGEND: --> seq | ==> prewalk | ~-> tier drop | !-> INVERSION | LOOP/WAVE boxes'
Write-Output ("SUMMARY:pipelines={0} steps={1} agents={2} pseudo={3} loops={4} waves={5} prewalk={6} inversions={7} drops={8} unresolved={9} warn={10}" -f `
    $blocks.Count, $sumSteps, $sumAgents, $sumPseudo, $sumLoops, $sumWaves, $sumPrewalk, $sumInv, $sumDrops, $sumUnresolved, $totalWarn)
Write-Output 'STATUS:SUCCESS'
exit 0
