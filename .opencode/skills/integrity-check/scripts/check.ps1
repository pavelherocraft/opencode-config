<#
.SYNOPSIS
    Fast LLM-free integrity check of the agent orchestration config.

.DESCRIPTION
    SHA256 for all 37 agent pairs (live vs deploy), counters (agents, models in
    use, routing tables across opencode.json + ARCHITECTURE.md + live
    workflow-enforcement.ts), every frontmatter model: key validated for format
    (provider/key, split on FIRST slash) and existence in opencode.json provider
    models. PASS/FAIL report. STRICTLY READ-ONLY.

.PARAMETER ExpectedAgents
    Expected number of agent .md files in each mirror. Default 37.

.PARAMETER ExpectedModels
    Expected number of DISTINCT models in use (also MCP_SETUP Distribution rows
    and Summary count). Default 10.

.PARAMETER ExpectedOrch
    Expected orchestrator routing-table size. Default 25.

.PARAMETER ExpectedPlan
    Expected plankestrator routing-table size. Default 10.

.PARAMETER Config
    Path to the live opencode.json. Default %USERPROFILE%\.config\opencode\opencode.json

.PARAMETER Json
    Emit a single JSON document instead of token lines.

.OUTPUTS
    STATUS:/COUNT:/PAIR:/FORMAT:/EXISTS:/JSON:/WARN:/SUMMARY:/ERROR: lines

.NOTES
    Exit codes: 0 all pass (WARNs allowed), 2 usage/environment error,
    3 one or more FAIL findings. Read-only: never writes anything.

.EXAMPLE
    .\check.ps1
    .\check.ps1 -Json
    .\check.ps1 -ExpectedAgents 37 -ExpectedModels 10 -ExpectedOrch 25 -ExpectedPlan 10
#>

param(
    [int]$ExpectedAgents = 37,
    [int]$ExpectedModels = 10,
    [int]$ExpectedOrch = 25,
    [int]$ExpectedPlan = 10,
    [string]$Config = "",
    [switch]$Json
)

if (-not $Config) { $Config = Join-Path $env:USERPROFILE '.config\opencode\opencode.json' }

$ErrorActionPreference = 'Stop'
# git emits UTF-8; keep non-ASCII repo paths intact.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

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

function Get-DistributionRows([string]$Text) {
    $lines = [regex]::Split($Text, '\r\n|\r|\n')
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^### Models Distribution\s*$') { $start = $i; break }
    }
    if ($start -lt 0) { return $null }
    $count = 0
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^### ') { break }
        if ($lines[$i] -match '^\|\s*`') { $count++ }
    }
    return $count
}

function Get-SummaryModelsCount([string]$Text) {
    $m = [regex]::Match($Text, '(?m)^\| Models \| (\d+) \| bifrost-litellm \(')
    if (-not $m.Success) { return $null }
    return [int]$m.Groups[1].Value
}

# --- Paths ----------------------------------------------------------------
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy-package"))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}

$liveDir = Join-Path $env:USERPROFILE '.config\opencode'
$liveAgentsDir = Join-Path $liveDir 'agents'
$deployRoot = Join-Path $repoRoot 'deploy-package'
$deployAgentsDir = Join-Path $deployRoot 'agents'

if (-not (Test-Path -LiteralPath $liveAgentsDir -PathType Container)) {
    Write-Output "ERROR: live agents dir not found: $liveAgentsDir"
    exit 2
}
if (-not (Test-Path -LiteralPath $deployRoot -PathType Container)) {
    Write-Output "ERROR: deploy-package not found: $deployRoot"
    exit 2
}
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
    Write-Output "ERROR: opencode.json not found: $Config"
    exit 2
}

if (-not $Json) { Write-Output 'STATUS:CHECK_START' }

# --- 1. opencode.json validity -------------------------------------------
$cfg = $null
$jsonOk = $true
try {
    $raw = Read-RawText $Config
    $cfg = $raw.Text | ConvertFrom-Json
} catch {
    $jsonOk = $false
}
Add-Check -Id 'JSON' -Target 'opencode.json' -Status $(if ($jsonOk) { 'PASS' } else { 'FAIL' }) -Detail $(if ($jsonOk) { 'parse ok' } else { 'invalid JSON' })

# --- 2. Agent counts + name sets -----------------------------------------
$liveFiles = @(Get-ChildItem -LiteralPath $liveAgentsDir -Filter '*.md' -File)
$deployFiles = @(Get-ChildItem -LiteralPath $deployAgentsDir -Filter '*.md' -File)
$liveNames = @($liveFiles | ForEach-Object { $_.BaseName })
$deployNames = @($deployFiles | ForEach-Object { $_.BaseName })
$extraLive = @($liveNames | Where-Object { $deployNames -notcontains $_ })
$extraDeploy = @($deployNames | Where-Object { $liveNames -notcontains $_ })
$namesEqual = ($extraLive.Count -eq 0 -and $extraDeploy.Count -eq 0)
$countDetail = "agents_live=$($liveFiles.Count) agents_deploy=$($deployFiles.Count) expected=$ExpectedAgents"
if (-not $namesEqual) {
    $countDetail += " live_only=[$($extraLive -join ',')] deploy_only=[$($extraDeploy -join ',')]"
}
$countOk = ($liveFiles.Count -eq $ExpectedAgents -and $deployFiles.Count -eq $ExpectedAgents -and $namesEqual)
Add-Check -Id 'COUNT' -Target '' -Status $(if ($countOk) { 'PASS' } else { 'FAIL' }) -Detail $countDetail

# --- 3. Pairs (37 agents + opencode.json) ---------------------------------
$union = @($liveNames + $deployNames | Select-Object -Unique)
foreach ($n in $union) {
    $lp = Join-Path $liveAgentsDir "$n.md"
    $dp = Join-Path $deployAgentsDir "$n.md"
    if ((Test-Path -LiteralPath $lp) -and (Test-Path -LiteralPath $dp)) {
        $h1 = Get-Sha256 $lp
        $h2 = Get-Sha256 $dp
        if ($h1 -eq $h2) {
            Add-Check -Id 'PAIR' -Target $n -Status 'PASS' -Detail ''
        } else {
            Add-Check -Id 'PAIR' -Target $n -Status 'FAIL' -Detail ("live={0} deploy={1}" -f $h1.Substring(0,8), $h2.Substring(0,8))
        }
    } else {
        Add-Check -Id 'PAIR' -Target $n -Status 'FAIL' -Detail 'side missing'
    }
}
$deployCfgPath = Join-Path $deployRoot 'opencode.json'
if (Test-Path -LiteralPath $deployCfgPath -PathType Leaf) {
    $hc1 = Get-Sha256 $Config
    $hc2 = Get-Sha256 $deployCfgPath
    if ($hc1 -eq $hc2) {
        Add-Check -Id 'PAIR' -Target 'opencode.json' -Status 'PASS' -Detail ''
    } else {
        Add-Check -Id 'PAIR' -Target 'opencode.json' -Status 'FAIL' -Detail ("live={0} deploy={1}" -f $hc1.Substring(0,8), $hc2.Substring(0,8))
    }
} else {
    Add-Check -Id 'PAIR' -Target 'opencode.json' -Status 'FAIL' -Detail 'deploy copy missing'
}

# --- 4. FORMAT / EXISTS per live agent ------------------------------------
$modelsUsed = @{}
foreach ($f in $liveFiles) {
    $name = $f.BaseName
    $text = (Read-RawText $f.FullName).Text
    $m = Get-FmModel $text
    if (-not $m) {
        Add-Check -Id 'FORMAT' -Target $name -Status 'FAIL' -Detail 'model=<missing> frontmatter without model line'
        continue
    }
    $modelsUsed[$m] = $true
    $fmtOk = $m -match '^[A-Za-z0-9._-]+/.+$'
    Add-Check -Id 'FORMAT' -Target $name -Status $(if ($fmtOk) { 'PASS' } else { 'FAIL' }) -Detail "model=$m"
    if ($jsonOk) {
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
if (-not $jsonOk) {
    Add-Check -Id 'EXISTS' -Target '' -Status 'WARN' -Detail 'checks skipped (opencode.json parse failed)'
}

# --- 5. Models-in-use counter ---------------------------------------------
$muOk = ($modelsUsed.Count -eq $ExpectedModels)
Add-Check -Id 'COUNT' -Target '' -Status $(if ($muOk) { 'PASS' } else { 'FAIL' }) -Detail "models_used=$($modelsUsed.Count) expected=$ExpectedModels"

# --- 6. MCP_SETUP.md cross-checks -----------------------------------------
$mcpPath = Join-Path $repoRoot 'MCP_SETUP.md'
if (Test-Path -LiteralPath $mcpPath -PathType Leaf) {
    $mcpText = (Read-RawText $mcpPath).Text
    $distRows = Get-DistributionRows $mcpText
    if ($null -ne $distRows) {
        Add-Check -Id 'COUNT' -Target '' -Status $(if ($distRows -eq $ExpectedModels) { 'PASS' } else { 'FAIL' }) -Detail "mcp_distribution rows=$distRows expected=$ExpectedModels"
    } else {
        Add-Check -Id 'COUNT' -Target '' -Status 'FAIL' -Detail 'mcp_distribution anchor not found (### Models Distribution)'
    }
    $sumCount = Get-SummaryModelsCount $mcpText
    if ($null -ne $sumCount) {
        Add-Check -Id 'COUNT' -Target '' -Status $(if ($sumCount -eq $ExpectedModels) { 'PASS' } else { 'FAIL' }) -Detail "mcp_summary_models count=$sumCount expected=$ExpectedModels"
    } else {
        Add-Check -Id 'COUNT' -Target '' -Status 'FAIL' -Detail 'mcp_summary_models anchor not found (| Models | N | bifrost-litellm ()'
    }
} else {
    Add-Check -Id 'COUNT' -Target '' -Status 'FAIL' -Detail 'MCP_SETUP.md not found'
}

# --- 7. Routing counters (3 sources) --------------------------------------
$archPath = Join-Path $repoRoot 'ARCHITECTURE.md'
$archText = $null
if (Test-Path -LiteralPath $archPath -PathType Leaf) { $archText = (Read-RawText $archPath).Text }

$tsPath = Join-Path $liveDir 'plugins\workflow-enforcement.ts'
$tsText = $null
if (Test-Path -LiteralPath $tsPath -PathType Leaf) { $tsText = (Read-RawText $tsPath).Text }

$routingSpec = @(
    @{ Primary = 'orchestrator'; Expected = $ExpectedOrch },
    @{ Primary = 'plankestrator'; Expected = $ExpectedPlan }
)
foreach ($rs in $routingSpec) {
    $p = $rs.Primary
    $exp = $rs.Expected
    $jsonN = $null
    if ($jsonOk) { $jsonN = Count-TaskAllow $cfg $p }
    $archH = $null; $archR = $null
    if ($null -ne $archText) {
        $wl = Get-WhitelistCount $archText $p
        if ($null -ne $wl) { $archH = $wl.Header; $archR = $wl.Rows }
    }
    $plugN = $null
    if ($null -ne $tsText) { $plugN = Count-RoutingPlugin $tsText $p }
    $ok = ($null -ne $jsonN -and $jsonN -eq $exp -and $null -ne $archH -and $archH -eq $exp -and $null -ne $archR -and $archR -eq $exp)
    if ($null -ne $plugN -and $plugN -ne $exp) { $ok = $false }
    $plugStr = if ($null -ne $plugN) { "$plugN" } else { '-' }
    Add-Check -Id 'COUNT' -Target '' -Status $(if ($ok) { 'PASS' } else { 'FAIL' }) -Detail "routing_$p json=$jsonN arch_header=$archH arch_rows=$archR plugin=$plugStr expected=$exp"
    if ($null -eq $plugN) {
        Add-Check -Id 'WARN' -Target 'routing' -Status 'WARN' -Detail "$p plugin anchor not parsed (skipped plugin source)"
    }
}

# --- 8. Summary ------------------------------------------------------------
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
