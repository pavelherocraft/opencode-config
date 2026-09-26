<#
.SYNOPSIS
    Add ONE new subagent end-to-end across all synchronized places.

.DESCRIPTION
    Creates live+deploy agent .md (frontmatter from readonly/standard preset or
    -PermTemplate), inserts the opencode.json agent section + primary task allow
    (live + deploy), appends to ROUTING_TABLES (plugin x3) and
    OPENCODE_ROUTING_TABLE (primary prompt x2), updates whitelist tables and
    every derived counter in ARCHITECTURE.md x3 / AGENTS.md x3 / PLUGIN.md x3 /
    MCP_SETUP.md x2 (whitelist 26->27 or 10->11, subagents 36->37, total 38->39),
    adds Subagent Models + Model Roles + Distribution + Full Table rows,
    SHA256-verifies all mirrors, optional conventional commit + push.
    Two-phase all-or-nothing: any failed gate/anchor -> zero files written.

.PARAMETER Agent
    New agent name (file stem), ^[a-z][a-z0-9-]*$ (REQUIRED).

.PARAMETER Model
    Full model key provider/model-key, validated against opencode.json
    provider models (REQUIRED).

.PARAMETER Description
    One-line description -> frontmatter + Role cells (REQUIRED).

.PARAMETER Primary
    Whitelist to join: orchestrator | plankestrator (REQUIRED).

.PARAMETER Permissions
    Permission preset: readonly | standard (mutually exclusive with -PermTemplate).

.PARAMETER PermTemplate
    Copy permission blocks from an existing agent.

.PARAMETER TaskAllow
    Comma list of extra task allowlist entries for the NEW agent.

.PARAMETER Role
    Model Roles row (required when the model maps to 0 or >1 role rows).

.PARAMETER Tier
    With -Role: create a NEW role row (top|mid|low).

.PARAMETER BodyFile
    Prompt body after frontmatter (default: minimal stub + WARN).

.PARAMETER Temperature
    Default 0.1.

.PARAMETER PlanOnly
    Dry-run: compute and print all edits, write nothing (default).

.PARAMETER Apply
    Apply the edits (mutually exclusive with -PlanOnly).

.PARAMETER Commit
    After apply: conventional commit of the 16 repo files (live files are outside git).

.PARAMETER Push
    After commit: push to origin (requires -Commit).

.OUTPUTS
    STATUS:/PLAN:/WARN:/DIFF:/BLOCK:/CREATED:/EDITED:/VERIFY:/COMMITTED:/PUSHED:/ERROR: lines

.NOTES
    Exit codes: 0 success/plan-only, 2 usage/environment error,
    3 gate block (zero writes). Byte-safe: preserves BOM state and CRLF/LF;
    NEW agent .md files are LF, UTF-8 without BOM.

.EXAMPLE
    .\add.ps1 -Agent code-search -Model bifrost-litellm/MiniMax-M3 -Description "Fast code search" -Primary orchestrator -Permissions standard -PlanOnly
    .\add.ps1 -Agent code-search -Model bifrost-litellm/MiniMax-M3 -Description "Fast code search" -Primary orchestrator -Permissions readonly -Apply -Commit
#>

param(
    [string]$Agent = '',
    [string]$Model = '',
    [string]$Description = '',
    [string]$Primary = '',
    [string]$Permissions = '',
    [string]$PermTemplate = '',
    [string]$TaskAllow = '',
    [string]$Role = '',
    [string]$Tier = '',
    [string]$BodyFile = '',
    [double]$Temperature = 0.1,
    [switch]$PlanOnly,
    [switch]$Apply,
    [switch]$Commit,
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
# git emits UTF-8; keep non-ASCII repo paths intact.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ============================================================================
# Flag validation (usage errors -> exit 2)
# ============================================================================
$usageLine = 'USAGE: add.ps1 -Agent <name> -Model <provider/model-key> -Description <text> -Primary <orchestrator|plankestrator> (-Permissions <readonly|standard> | -PermTemplate <agent>) [-TaskAllow a,b] [-Role R [-Tier top|mid|low]] [-BodyFile <path>] [-Temperature 0.1] [-PlanOnly | -Apply] [-Commit] [-Push]'
$missing = @()
if (-not $Agent) { $missing += '-Agent' }
if (-not $Model) { $missing += '-Model' }
if (-not $Description) { $missing += '-Description' }
if (-not $Primary) { $missing += '-Primary' }
if ($missing.Count -gt 0) {
    Write-Output $usageLine
    foreach ($m in $missing) { Write-Output "ERROR:missing required parameter: $m" }
    exit 2
}
if (-not $Permissions -and -not $PermTemplate) {
    Write-Output $usageLine
    Write-Output 'ERROR:either -Permissions <readonly|standard> or -PermTemplate <agent> is required'
    exit 2
}
if ($Permissions -and $PermTemplate) {
    Write-Output 'ERROR:-Permissions and -PermTemplate are mutually exclusive'
    exit 2
}
if ($Permissions -and $Permissions -notin @('readonly', 'standard')) {
    Write-Output "ERROR:-Permissions must be readonly or standard (got '$Permissions')"
    exit 2
}
if ($PlanOnly -and $Apply) {
    Write-Output 'ERROR:-PlanOnly and -Apply are mutually exclusive'
    exit 2
}
if (-not $PlanOnly -and -not $Apply) { $PlanOnly = $true }
if ($Push -and -not $Commit) {
    Write-Output 'ERROR:-Push requires -Commit'
    exit 2
}
if ($Tier -and -not $Role) {
    Write-Output 'ERROR:-Tier requires -Role'
    exit 2
}
if ($Tier -and $Tier -notin @('top', 'mid', 'low')) {
    Write-Output "ERROR:-Tier must be one of: top, mid, low (got '$Tier')"
    exit 2
}
if ($Primary -notin @('orchestrator', 'plankestrator')) {
    Write-Output "ERROR:-Primary must be orchestrator or plankestrator (got '$Primary')"
    exit 2
}

# ============================================================================
# Helpers
# ============================================================================
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

function Split-ModelKey([string]$Full) {
    if (-not $Full) { return $null }
    $idx = $Full.IndexOf('/')
    if ($idx -lt 1 -or $idx -ge ($Full.Length - 1)) { return $null }
    return @{ Provider = $Full.Substring(0, $idx); Key = $Full.Substring($idx + 1) }
}

function Get-FmModel([string]$Text) {
    $m = [regex]::Match($Text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $m.Success) { return $null }
    $mm = [regex]::Match($m.Groups[1].Value, '(?m)^model:[ \t]*(.*)$')
    if (-not $mm.Success) { return $null }
    return $mm.Groups[1].Value.Trim()
}

# --- Line-preserving table editing ----------------------------------------
function Split-LinesKeepEol([string]$Text) {
    return [regex]::Split($Text, '(\r\n|\r|\n)')
}

function Find-SectionSpan($Lines, [string]$StartPat, [string]$EndPat) {
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i += 2) {
        if ($Lines[$i] -match $StartPat) { $start = $i; break }
    }
    if ($start -lt 0) { return $null }
    for ($j = $start + 2; $j -lt $Lines.Count; $j += 2) {
        if ($Lines[$j] -match $EndPat) { return @{ Start = $start; End = $j } }
    }
    return $null
}

function Find-UniqueLine($Lines, [string]$Pattern) {
    $hits = @()
    for ($i = 0; $i -lt $Lines.Count; $i += 2) {
        if ($Lines[$i] -match $Pattern) { $hits += $i }
    }
    if ($hits.Count -ne 1) {
        return @{ Index = -1; Error = "anchor found $($hits.Count) times (expected 1): $Pattern" }
    }
    return @{ Index = $hits[0]; Error = $null }
}

function Split-Tokens([string]$Cell) {
    if (-not $Cell -or -not $Cell.Trim()) { return @() }
    return @($Cell -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-Eol($List, [int]$ContentIdx) {
    if ($ContentIdx + 1 -lt $List.Count) { return $List[$ContentIdx + 1] }
    return ''
}

function Detect-Eol([string]$Text) {
    $crlf = [regex]::Matches($Text, "`r`n").Count
    $lf = [regex]::Matches($Text, "`n").Count
    if ($crlf -ge ($lf - $crlf)) { return "`r`n" }
    return "`n"
}

# Quoted-token regex for TS/JSON arrays — matches both "..." and '...' styles.
$script:TokenRx = '["' + [char]0x27 + '"][^"' + [char]0x27 + '"]+["' + [char]0x27 + '"]'

# --- String-aware brace scanner for opencode.json ---------------------------
function Find-JsonSpan([string]$Text, [string]$StartPattern) {
    $m = [regex]::Match($Text, $StartPattern)
    if (-not $m.Success) { return $null }
    $open = $Text.IndexOf('{', $m.Index + $m.Length - 1)
    if ($open -lt 0) { return $null }
    $depth = 0; $inStr = $false; $esc = $false
    for ($i = $open; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($c -eq '\') { $esc = $true }
            elseif ($c -eq '"') { $inStr = $false }
            continue
        }
        switch ($c) {
            '"' { $inStr = $true }
            '{' { $depth++ }
            '}' {
                $depth--
                if ($depth -eq 0) { return @{ Open = $open; Close = $i } }
            }
        }
    }
    return $null
}

# --- Routing counters (cross-check parsers) ----------------------------------
function Count-TaskAllow($CfgObj, [string]$PrimaryName) {
    try {
        $node = $CfgObj.agent.$PrimaryName.permission.task
        if (-not $node) { return $null }
        return @($node.PSObject.Properties | Where-Object { $_.Name -ne '*' -and [string]$_.Value -eq 'allow' }).Count
    } catch { return $null }
}

function Count-RoutingPlugin([string]$TsText, [string]$PrimaryName) {
    $outer = [regex]::Match($TsText, '(?s)const ROUTING_TABLES = \{(.*?)\r?\n\}')
    if (-not $outer.Success) { return $null }
    $inner = [regex]::Match($outer.Groups[1].Value, ('(?s)' + [regex]::Escape($PrimaryName) + '\s*:\s*\[(.*?)\]'))
    if (-not $inner.Success) { return $null }
    return [regex]::Matches($inner.Groups[1].Value, $script:TokenRx).Count
}

function Get-RoutingTokens([string]$TsText, [string]$PrimaryName) {
    $outer = [regex]::Match($TsText, '(?s)const ROUTING_TABLES = \{(.*?)\r?\n\}')
    if (-not $outer.Success) { return $null }
    $inner = [regex]::Match($outer.Groups[1].Value, ('(?s)' + [regex]::Escape($PrimaryName) + '\s*:\s*\[(.*?)\]'))
    if (-not $inner.Success) { return $null }
    return @([regex]::Matches($inner.Groups[1].Value, $script:TokenRx) | ForEach-Object { $_.Value.Trim('"', [char]0x27) })
}

function Count-RoutingLine([string]$MdText) {
    $m = [regex]::Match($MdText, '(?m)^OPENCODE_ROUTING_TABLE = \[(.*)\]\r?$')
    if (-not $m.Success) { return $null }
    $q = [string][char]0x27
    return @((Split-Tokens $m.Groups[1].Value) | ForEach-Object { $_.Trim('"', $q) } | Where-Object { $_ }).Count
}

function Get-WhitelistCount([string]$ArchText, [string]$PrimaryName) {
    $headerPat = '^### ' + [regex]::Escape($PrimaryName) + ' Whitelist \((\d+) agents\)'
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

function Get-WhitelistCountUnnumbered([string]$Text, [string]$PrimaryName) {
    $headerPat = '^### ' + [regex]::Escape($PrimaryName) + ' Whitelist \((\d+) agents\)'
    $hm = [regex]::Match($Text, $headerPat, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $hm.Success) { return $null }
    $after = $Text.Substring($hm.Index + $hm.Length)
    $firstPipe = [regex]::Match($after, '(?m)^\|')
    if (-not $firstPipe.Success) { return @{ Header = [int]$hm.Groups[1].Value; Rows = -1 } }
    $rest = $after.Substring($firstPipe.Index)
    $blank = [regex]::Match($rest, '\r?\n[ \t]*\r?\n')
    $tbl = if ($blank.Success) { $rest.Substring(0, $blank.Index) } else { $rest }
    # data rows = pipe rows that are neither the header nor the |---| separator
    $rows = [regex]::Matches($tbl, '(?m)^\| [^-|]').Count - 1
    return @{ Header = [int]$hm.Groups[1].Value; Rows = $rows }
}

# ============================================================================
# Paths
# ============================================================================
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy-package"))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}
$liveDir = Join-Path $env:USERPROFILE '.config\opencode'
if (-not (Test-Path -LiteralPath $liveDir -PathType Container)) {
    Write-Output "ERROR:live config dir not found: $liveDir"
    exit 2
}

$liveAgentMd = Join-Path $liveDir "agents\$Agent.md"
$deployAgentMd = Join-Path $repoRoot "deploy-package\agents\$Agent.md"
$liveCfgPath = Join-Path $liveDir 'opencode.json'
$deployCfgPath = Join-Path $repoRoot 'deploy-package\opencode.json'
$pluginPaths = @(
    (Join-Path $liveDir 'plugins\workflow-enforcement.ts'),
    (Join-Path $repoRoot 'plugins\workflow-enforcement.ts'),
    (Join-Path $repoRoot 'deploy-package\plugins\workflow-enforcement.ts')
)
$primaryLiveMd = Join-Path $liveDir "agents\$Primary.md"
$primaryDeployMd = Join-Path $repoRoot "deploy-package\agents\$Primary.md"
$archPaths = @(
    (Join-Path $repoRoot 'ARCHITECTURE.md'),
    (Join-Path $repoRoot 'opencode-config\ARCHITECTURE.md'),
    (Join-Path $repoRoot 'deploy-package\project-files\ARCHITECTURE.md')
)
$agentsMdPaths = @(
    (Join-Path $repoRoot 'AGENTS.md'),
    (Join-Path $repoRoot 'opencode-config\AGENTS.md'),
    (Join-Path $repoRoot 'deploy-package\project-files\AGENTS.md')
)
$pluginMdPaths = @(
    (Join-Path $repoRoot 'PLUGIN.md'),
    (Join-Path $repoRoot 'opencode-config\PLUGIN.md'),
    (Join-Path $repoRoot 'deploy-package\project-files\PLUGIN.md')
)
$mcpPaths = @(
    (Join-Path $repoRoot 'MCP_SETUP.md'),
    (Join-Path $repoRoot 'deploy-package\project-files\MCP_SETUP.md')
)

# New agent files must NOT exist; all 17 edit targets must exist.
if ((Test-Path -LiteralPath $liveAgentMd) -or (Test-Path -LiteralPath $deployAgentMd)) {
    Write-Output "BLOCK:agent already exists: $Agent (live/deploy .md file present)"
    exit 3
}
$editTargets = @($liveCfgPath, $deployCfgPath) + $pluginPaths + @($primaryLiveMd, $primaryDeployMd) + $archPaths + $agentsMdPaths + $pluginMdPaths + $mcpPaths
foreach ($t in $editTargets) {
    if (-not (Test-Path -LiteralPath $t -PathType Leaf)) {
        Write-Output "ERROR:target file not found: $t"
        exit 2
    }
}
if ($BodyFile -and -not (Test-Path -LiteralPath $BodyFile -PathType Leaf)) {
    Write-Output "ERROR:-BodyFile not found: $BodyFile"
    exit 2
}

function Get-RelPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($liveDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $full.Substring($liveDir.Length).TrimStart('\', '/') -replace '\\', '/'
        return "live:$rel"
    }
    $rel = $full.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    return $rel
}

# ============================================================================
# Name validation
# ============================================================================
if ($Agent -notmatch '^[a-z][a-z0-9-]*$') {
    Write-Output "ERROR:name malformed (expected ^[a-z][a-z0-9-]*$): '$Agent'"
    exit 2
}
if ($Agent -in @('orchestrator', 'plankestrator')) {
    Write-Output 'BLOCK:primary agent creation is manual (orchestrator/plankestrator)'
    exit 3
}

# ============================================================================
# Model validation
# ============================================================================
$keyParts = Split-ModelKey $Model
if (-not $keyParts) {
    Write-Output "ERROR:model key must be provider/model-key (got '$Model')"
    exit 2
}
$ModelProvider = $keyParts.Provider
$ModelKey = $keyParts.Key
if ($ModelProvider -ne 'bifrost-litellm') {
    Write-Output "BLOCK:provider '$ModelProvider' is not bifrost-litellm"
    exit 3
}
try {
    $cfg = ((Read-RawText $liveCfgPath).Text) | ConvertFrom-Json
} catch {
    Write-Output "BLOCK:live opencode.json is not valid JSON: $_"
    exit 3
}
$provProp = $cfg.provider.PSObject.Properties[$ModelProvider]
$modelExists = $false
if ($provProp -and $provProp.Value.models) {
    $modelExists = @($provProp.Value.models.PSObject.Properties.Name) -ccontains $ModelKey
}
if (-not $modelExists) {
    Write-Output "BLOCK:model not found in provider models: $Model"
    exit 3
}

# ============================================================================
# Existence check: no routing table / json section may mention the name yet
# ============================================================================
$liveCfgText = (Read-RawText $liveCfgPath).Text
if ([regex]::IsMatch($liveCfgText, ('(?m)^    "' + [regex]::Escape($Agent) + '": \{'))) {
    Write-Output "BLOCK:agent already exists: opencode.json agent section '$Agent'"
    exit 3
}
foreach ($pp in $pluginPaths) {
    $tsText = (Read-RawText $pp).Text
    foreach ($p in @('orchestrator', 'plankestrator')) {
        $tokens = Get-RoutingTokens $tsText $p
        if ($null -ne $tokens) {
            if ($tokens -ccontains $Agent) {
                Write-Output "BLOCK:agent already exists in routing table (plugin $p): $Agent"
                exit 3
            }
        }
    }
}
foreach ($pm in @($primaryLiveMd, (Join-Path $liveDir "agents\$(if ($Primary -eq 'orchestrator') { 'plankestrator' } else { 'orchestrator' }).md"))) {
    $pmText = (Read-RawText $pm).Text
    $mLine = [regex]::Match($pmText, '(?m)^OPENCODE_ROUTING_TABLE = \[(.*)\]\r?$')
    if ($mLine.Success) {
        $q = [string][char]0x27
        $toks = @((Split-Tokens $mLine.Groups[1].Value) | ForEach-Object { $_.Trim('"', $q) })
        if ($toks -ccontains $Agent) {
            Write-Output "BLOCK:agent already exists in OPENCODE_ROUTING_TABLE ($([System.IO.Path]::GetFileName($pm))): $Agent"
            exit 3
        }
    }
}
foreach ($p in @('orchestrator', 'plankestrator')) {
    $ta = Count-TaskAllow $cfg $p
    if ($null -ne $ta) {
        $node = $cfg.agent.$p.permission.task
        if ($node.PSObject.Properties[$Agent]) {
            Write-Output "BLOCK:agent already exists in opencode.json task allow of $p`: $Agent"
            exit 3
        }
    }
}

Write-Output "STATUS:ADD_START agent=$Agent model=$Model primary=$Primary"

# ============================================================================
# Permission resolution (preset or template)
# ============================================================================
$taskAllowList = @(Split-Tokens $TaskAllow)
$warns = @()

function Get-PermPreset([string]$Name) {
    if ($Name -eq 'readonly') {
        return @{
            FmYaml = @('edit: deny', 'write: deny', 'bash: deny', 'webfetch: deny', 'patch: deny', 'todowrite: deny', 'question: deny', 'read: allow', 'grep: allow', 'glob: allow', 'serena_find_symbol: allow', 'serena_find_referencing_symbols: allow', 'serena_get_symbols_overview: allow', 'serena_search_for_pattern: allow')
            JsonPerm = @('"edit": "deny"', '"write": "deny"', '"bash": "deny"', '"webfetch": "deny"', '"patch": "deny"', '"todowrite": "deny"', '"question": "deny"', '"read": "allow"', '"grep": "allow"', '"glob": "allow"', '"serena_find_symbol": "allow"', '"serena_find_referencing_symbols": "allow"', '"serena_get_symbols_overview": "allow"', '"serena_search_for_pattern": "allow"')
            DefaultTask = @()
            FullTable = @{ edit = 'deny'; write = 'deny'; read = 'allow'; bash = 'deny' }
        }
    }
    return @{
        FmYaml = @('edit: deny', 'write: deny', 'read: allow', 'bash: deny', 'unity-mcp.*: allow', 'serena_find_symbol: allow', 'serena_find_referencing_symbols: allow', 'serena_get_symbols_overview: allow', 'serena_rename_symbol: allow', 'serena_safe_delete_symbol: allow', 'serena_replace_symbol_body: allow', 'serena_insert_after_symbol: allow')
        JsonPerm = @('"edit": "deny"', '"write": "deny"', '"read": "allow"', '"bash": "deny"', '"unity-mcp.*": "allow"', '"serena_find_symbol": "allow"', '"serena_find_referencing_symbols": "allow"', '"serena_get_symbols_overview": "allow"', '"serena_rename_symbol": "allow"', '"serena_safe_delete_symbol": "allow"', '"serena_replace_symbol_body": "allow"', '"serena_insert_after_symbol": "allow"')
        DefaultTask = @('view-image')
        FullTable = @{ edit = 'deny'; write = 'deny'; read = 'allow'; bash = 'deny' }
    }
}

$fmPermLines = @()       # frontmatter permission lines (2-space base, without 'permission:')
$jsonPermLines = @()     # JSON permission entries (8-space base, quoted)
$taskEntries = @()       # task allowlist tokens (besides '*')
$fullCells = $null       # @{ edit; write; read; bash } for the Full Table row

if ($PermTemplate) {
    $tplLiveMd = Join-Path $liveDir "agents\$PermTemplate.md"
    if (-not (Test-Path -LiteralPath $tplLiveMd -PathType Leaf)) {
        Write-Output "ERROR:-PermTemplate agent .md not found: $tplLiveMd"
        exit 2
    }
    if (-not [regex]::IsMatch($liveCfgText, ('(?m)^    "' + [regex]::Escape($PermTemplate) + '": \{'))) {
        Write-Output "ERROR:-PermTemplate agent section not found in opencode.json: $PermTemplate"
        exit 2
    }
    # (1) JSON permission block from live opencode.json (verbatim, same depth):
    #     the whole section INCLUDING the '    "<tpl>": {' line, ending at '}'.
    $tplAnchor = '(?m)^    "' + [regex]::Escape($PermTemplate) + '": \{$'
    $span = Find-JsonSpan $liveCfgText $tplAnchor
    if (-not $span) {
        Write-Output "BLOCK:-PermTemplate section span not resolved: $PermTemplate"
        exit 3
    }
    $tplAnchorMatch = [regex]::Match($liveCfgText, $tplAnchor)
    $tplSection = $liveCfgText.Substring($tplAnchorMatch.Index, $span.Close - $tplAnchorMatch.Index + 1)
    # (2) frontmatter permission block from the live template .md.
    $tplMdText = (Read-RawText $tplLiveMd).Text
    $tplLines = Split-LinesKeepEol $tplMdText
    $permStart = -1
    for ($i = 0; $i -lt $tplLines.Count; $i += 2) {
        if ($tplLines[$i] -match '^permission:[ \t]*$') { $permStart = $i; break }
    }
    if ($permStart -lt 0) {
        Write-Output "BLOCK:-PermTemplate frontmatter has no permission block: $PermTemplate"
        exit 3
    }
    $fmPermLines = @()
    for ($i = $permStart + 2; $i -lt $tplLines.Count; $i += 2) {
        if ($tplLines[$i] -match '^---[ \t]*$') { break }
        $fmPermLines += $tplLines[$i] -replace '^  ', ''
    }
    # (3) Full Table cells from MCP_SETUP (fallback: derive deny/allow lines).
    $mcpRootText = (Read-RawText $mcpPaths[0]).Text
    $ftRow = [regex]::Match($mcpRootText, ('(?m)^\| \*\*' + [regex]::Escape($PermTemplate) + '\*\* \| subagent \| .+?\| .+?\| (.+?) \| (.+?) \| (.+?) \| (.+?) \|'))
    if ($ftRow.Success) {
        $fullCells = @{ edit = $ftRow.Groups[1].Value.Trim(); write = $ftRow.Groups[2].Value.Trim(); read = $ftRow.Groups[3].Value.Trim(); bash = $ftRow.Groups[4].Value.Trim() }
    } else {
        $warns += "WARN:perm-template full-table row not found for '$PermTemplate' — deriving cells from JSON block"
        $fullCells = @{
            edit = $(if ($tplSection -match '"edit":\s*"allow"') { 'allow' } else { 'deny' })
            write = $(if ($tplSection -match '"write":\s*"allow"') { 'allow' } else { 'deny' })
            read = $(if ($tplSection -match '"read":\s*"allow"') { 'allow' } else { 'deny' })
            bash = $(if ($tplSection -match '"bash":\s*"allow"') { '**allow**' } else { 'deny' })
        }
    }
    # Task entries: copy allow tokens from the template task block + -TaskAllow extras.
    $tplTask = $null
    try { $tplTask = $cfg.agent.$PermTemplate.permission.task } catch {}
    if ($tplTask) {
        $taskEntries = @($tplTask.PSObject.Properties | Where-Object { $_.Name -ne '*' -and [string]$_.Value -eq 'allow' } | ForEach-Object { $_.Name })
    } else {
        $taskEntries = @()
    }
    foreach ($t in $taskAllowList) { if ($taskEntries -notcontains $t) { $taskEntries += $t } }
    $script:TplJsonSection = $tplSection
} else {
    $preset = Get-PermPreset $Permissions
    $fmPermLines = $preset.FmYaml
    $jsonPermLines = $preset.JsonPerm
    $taskEntries = @($preset.DefaultTask)
    foreach ($t in $taskAllowList) { if ($taskEntries -notcontains $t) { $taskEntries += $t } }
    $fullCells = $preset.FullTable
    $script:TplJsonSection = $null
}

# ============================================================================
# Read all targets
# ============================================================================
$liveCfgRaw = Read-RawText $liveCfgPath
$deployCfgRaw = Read-RawText $deployCfgPath
$pluginRaws = @($pluginPaths | ForEach-Object { Read-RawText $_ })
$primaryRaws = @((Read-RawText $primaryLiveMd), (Read-RawText $primaryDeployMd))
$archRaws = @($archPaths | ForEach-Object { Read-RawText $_ })
$agentsMdRaws = @($agentsMdPaths | ForEach-Object { Read-RawText $_ })
$pluginMdRaws = @($pluginMdPaths | ForEach-Object { Read-RawText $_ })
$mcpRaws = @($mcpPaths | ForEach-Object { Read-RawText $_ })

# ============================================================================
# Mirror pre-gates
# ============================================================================
$drifts = @()
if ((Get-Sha256 $liveCfgPath) -ne (Get-Sha256 $deployCfgPath)) { $drifts += 'opencode.json pair' }
$pluginHashes = @($pluginPaths | ForEach-Object { Get-Sha256 $_ })
if (@($pluginHashes | Select-Object -Unique).Count -gt 1) { $drifts += 'plugin x3' }
if ((Get-Sha256 $primaryLiveMd) -ne (Get-Sha256 $primaryDeployMd)) { $drifts += 'primary pair' }
$archHashes = @($archPaths | ForEach-Object { Get-Sha256 $_ })
if (@($archHashes | Select-Object -Unique).Count -gt 1) { $drifts += 'ARCHITECTURE.md x3' }
$agentsMdHashes = @($agentsMdPaths | ForEach-Object { Get-Sha256 $_ })
if (@($agentsMdHashes | Select-Object -Unique).Count -gt 1) { $drifts += 'AGENTS.md x3' }
$mcpHashes = @($mcpPaths | ForEach-Object { Get-Sha256 $_ })
if (@($mcpHashes | Select-Object -Unique).Count -gt 1) { $drifts += 'MCP_SETUP.md x2' }
if ($drifts.Count -gt 0) {
    if ($Apply) {
        Write-Output "BLOCK:mirrors drifted — run config-sync first ($($drifts -join '; '))"
        exit 3
    } else {
        foreach ($d in $drifts) { $warns += "WARN:mirror drift ($d) — run config-sync before apply" }
    }
}

# ============================================================================
# Counter cross-check (fail-closed)
# ============================================================================
$script:DiffLines = @()
function Add-Diff([string]$Source, [string]$Id, [object]$Value, [object]$Expected) {
    $script:DiffLines += "DIFF:$Source $Id value=$Value expected=$Expected"
}

# --- whitelist count of -Primary from 10 source groups
$wlValues = @()
foreach ($i in 0..2) {
    $v = Count-RoutingPlugin $pluginRaws[$i].Text $Primary
    if ($null -eq $v) { Add-Diff "plugins[$i]" 'routing_plugin' 'null' 'number'; continue }
    $wlValues += @{ Src = "plugin$($i + 1)"; Val = $v }
}
foreach ($i in 0..1) {
    $v = Count-RoutingLine $primaryRaws[$i].Text
    if ($null -eq $v) { Add-Diff "primary_md[$i]" 'opencode_routing_table' 'null' 'number'; continue }
    $wlValues += @{ Src = "primary_md$($i + 1)"; Val = $v }
}
$ta = Count-TaskAllow $cfg $Primary
if ($null -eq $ta) { Add-Diff 'opencode.json' 'task_allow' 'null' 'number' } else { $wlValues += @{ Src = 'json_task'; Val = $ta } }
foreach ($i in 0..2) {
    $wl = Get-WhitelistCount $archRaws[$i].Text $Primary
    if ($null -eq $wl) { Add-Diff "arch[$i]" 'whitelist_header' 'null' 'number'; continue }
    if ($wl.Header -ne $wl.Rows) { Add-Diff "arch[$i]" 'whitelist_rows' $wl.Rows $wl.Header }
    $wlValues += @{ Src = "arch$($i + 1)"; Val = $wl.Header }
}
foreach ($i in 0..2) {
    $wl = Get-WhitelistCountUnnumbered $agentsMdRaws[$i].Text $Primary
    if ($null -eq $wl) { Add-Diff "agents_md[$i]" 'whitelist_header' 'null' 'number'; continue }
    if ($wl.Header -ne $wl.Rows) { Add-Diff "agents_md[$i]" 'whitelist_rows' $wl.Rows $wl.Header }
    $wlValues += @{ Src = "agents_md$($i + 1)"; Val = $wl.Header }
}
foreach ($i in 0..2) {
    $wl = Get-WhitelistCountUnnumbered $pluginMdRaws[$i].Text $Primary
    if ($null -eq $wl) { Add-Diff "plugin_md[$i]" 'whitelist_header' 'null' 'number'; continue }
    if ($wl.Header -ne $wl.Rows) { Add-Diff "plugin_md[$i]" 'whitelist_rows' $wl.Rows $wl.Header }
    $wlValues += @{ Src = "plugin_md$($i + 1)"; Val = $wl.Header }
}
foreach ($i in 0..1) {
    $wl = Get-WhitelistCountUnnumbered $mcpRaws[$i].Text $Primary
    if ($null -eq $wl) { Add-Diff "mcp[$i]" 'whitelist_s6_header' 'null' 'number'; continue }
    if ($wl.Header -ne $wl.Rows) { Add-Diff "mcp[$i]" 'whitelist_s6_rows' $wl.Rows $wl.Header }
    $wlValues += @{ Src = "mcp_s6_$($i + 1)"; Val = $wl.Header }
    # Task Whitelist header + comma list
    $twHeaders = [regex]::Matches($mcpRaws[$i].Text, '(?m)^\*\*Task Whitelist \((\d+) agents\):\*\*\r?$')
    $found = $null
    foreach ($h in $twHeaders) {
        $before = $mcpRaws[$i].Text.Substring(0, $h.Index)
        $lastH4 = [regex]::Matches($before, '(?m)^#### (orchestrator|plankestrator)\r?$')
        if ($lastH4.Count -gt 0 -and $lastH4[$lastH4.Count - 1].Groups[1].Value -eq $Primary) { $found = $h }
    }
    if ($null -eq $found) { Add-Diff "mcp[$i]" 'task_whitelist_header' 'missing' $Primary }
    else {
        $afterLine = [regex]::Match($mcpRaws[$i].Text.Substring($found.Index + $found.Length), '(?m)^(\S[^\r\n]*)\r?$')
        if ($afterLine.Success) {
            $nComma = (Split-Tokens $afterLine.Groups[1].Value).Count
            $wlValues += @{ Src = "mcp_taskwl_$($i + 1)"; Val = [int]$found.Groups[1].Value }
            if ($nComma -ne [int]$found.Groups[1].Value) { Add-Diff "mcp[$i]" 'task_whitelist_list' $nComma $found.Groups[1].Value }
        } else { Add-Diff "mcp[$i]" 'task_whitelist_list' 'missing' 'number' }
    }
    $sumRow = [regex]::Match($mcpRaws[$i].Text, '(?m)^\| Routing tables \| 2 \| orchestrator \((\d+)\), plankestrator \((\d+)\) \|\r?$')
    if ($sumRow.Success) {
        $g = $(if ($Primary -eq 'orchestrator') { 1 } else { 2 })
        $wlValues += @{ Src = "mcp_summary_routing_$($i + 1)"; Val = [int]$sumRow.Groups[$g].Value }
    } else { Add-Diff "mcp[$i]" 'summary_routing_row' 'missing' 'number' }
}
foreach ($i in 0..2) {
    $acs = [regex]::Match($archRaws[$i].Text, ('(?m)^\| ' + [regex]::Escape($Primary) + ' \| (\d+) \|'))
    if ($acs.Success) { $wlValues += @{ Src = "arch_agent_count_$($i + 1)"; Val = [int]$acs.Groups[1].Value } }
    else { Add-Diff "arch[$i]" 'agent_count_summary' 'missing' 'number' }
}

# --- global counters
$g1Values = @()   # unique subagents (35)
$g2Values = @()   # total agents (38)
foreach ($i in 0..2) {
    $gt = [regex]::Match($archRaws[$i].Text, '(?m)^\| \*\*Grand Total\*\* \| \*\*(\d+)\*\* \| \*\*(\d+)\*\* \|\r?$')
    if ($gt.Success) {
        $g1Values += @{ Src = "arch_grand_total_$($i + 1)"; Val = [int]$gt.Groups[1].Value }
        $g2Values += @{ Src = "arch_grand_total_$($i + 1)"; Val = [int]$gt.Groups[2].Value }
    } else { Add-Diff "arch[$i]" 'grand_total' 'missing' 'number' }
    $note = [regex]::Match($archRaws[$i].Text, '(?m)^Note: (\d+) whitelist entries[^\r\n]*?= (\d+) unique whitelisted subagents[^\r\n]*?(\d+) unique subagents \+ 2 primary agents = (\d+) unique agents total\.')
    if ($note.Success) {
        $g1Values += @{ Src = "arch_note_$($i + 1)"; Val = [int]$note.Groups[3].Value }
        $g2Values += @{ Src = "arch_note_$($i + 1)"; Val = [int]$note.Groups[4].Value }
    } else { Add-Diff "arch[$i]" 'note_counters' 'missing' 'number' }
    $kontrol = [regex]::Match($archRaws[$i].Text, '(?m)^\u041A\u043E\u043D\u0442\u0440\u043E\u043B\u044C \u0441\u0443\u043C\u043C\u044B: 2 primary \+ (\d+) subagents = (\d+) \u0430\u0433\u0435\u043D\u0442\u043E\u0432;')
    if ($kontrol.Success) {
        $g1Values += @{ Src = "arch_kontrol_$($i + 1)"; Val = [int]$kontrol.Groups[1].Value }
        $g2Values += @{ Src = "arch_kontrol_$($i + 1)"; Val = [int]$kontrol.Groups[2].Value }
    } else { Add-Diff "arch[$i]" 'kontrol_summy' 'missing' 'number' }
    $intro = [regex]::Match($archRaws[$i].Text, '(?m)\u043C\u043E\u0434\u0435\u043B\u0435\u0439 (\d+) \u0430\u0433\u0435\u043D\u0442\u0430\u043C')
    if ($intro.Success) { $g2Values += @{ Src = "arch_intro_$($i + 1)"; Val = [int]$intro.Groups[1].Value } }
    else { Add-Diff "arch[$i]" 'model_roles_intro' 'missing' 'number' }
}
foreach ($i in 0..2) {
    $prose = [regex]::Match($agentsMdRaws[$i].Text, '(?m)\u0432\u0441\u0435\u043C (\d+) \u0430\u0433\u0435\u043D\u0442\u0430\u043C')
    if ($prose.Success) { $g2Values += @{ Src = "agents_md_prose_$($i + 1)"; Val = [int]$prose.Groups[1].Value } }
    else { Add-Diff "agents_md[$i]" 'model_roles_prose' 'missing' 'number' }
}
foreach ($i in 0..1) {
    $ac = [regex]::Match($mcpRaws[$i].Text, '(?m)^\| Subagents \| (\d+) \|\r?$')
    if ($ac.Success) { $g1Values += @{ Src = "mcp_agent_count_$($i + 1)"; Val = [int]$ac.Groups[1].Value } }
    else { Add-Diff "mcp[$i]" 'agent_count_subagents' 'missing' 'number' }
    $tu = [regex]::Match($mcpRaws[$i].Text, '(?m)^\| \*\*Total unique agents\*\* \| \*\*(\d+)\*\* \|\r?$')
    if ($tu.Success) { $g2Values += @{ Src = "mcp_total_unique_$($i + 1)"; Val = [int]$tu.Groups[1].Value } }
    else { Add-Diff "mcp[$i]" 'total_unique_agents' 'missing' 'number' }
    $allSub = [regex]::Match($mcpRaws[$i].Text, '(?m)\u0432\u0441\u0435 (\d+) subagents')
    if ($allSub.Success) { $g1Values += @{ Src = "mcp_prose_$($i + 1)"; Val = [int]$allSub.Groups[1].Value } }
    else { Add-Diff "mcp[$i]" 'vse_subagents_prose' 'missing' 'number' }
    $subHdr = [regex]::Match($mcpRaws[$i].Text, '(?m)^\*\*Subagents \((\d+)\):\*\*\r?$')
    if ($subHdr.Success) { $g1Values += @{ Src = "mcp_subagents_hdr_$($i + 1)"; Val = [int]$subHdr.Groups[1].Value } }
    else { Add-Diff "mcp[$i]" 'subagents_bold_header' 'missing' 'number' }
    $af = [regex]::Match($mcpRaws[$i].Text, '(?m)^### Agent Files \((\d+) total\)\r?$')
    if ($af.Success) { $g2Values += @{ Src = "mcp_agent_files_$($i + 1)"; Val = [int]$af.Groups[1].Value } }
    else { Add-Diff "mcp[$i]" 'agent_files_total' 'missing' 'number' }
    $sumSub = [regex]::Match($mcpRaws[$i].Text, '(?m)^\| Subagents \| (\d+) \| \S')
    if ($sumSub.Success) { $g1Values += @{ Src = "mcp_summary_subagents_$($i + 1)"; Val = [int]$sumSub.Groups[1].Value } }
    else { Add-Diff "mcp[$i]" 'summary_subagents' 'missing' 'number' }
    # alphabetical '- *.md' list length under **Subagents (N):**
    if ($subHdr.Success) {
        $after = $mcpRaws[$i].Text.Substring($subHdr.Index + $subHdr.Length)
        $dash = [regex]::Matches($after, '(?m)^- [^\r\n]+\.md\r?$')
        $stop = [regex]::Match($after, '(?m)^(?!- )\S')
        $cnt = 0
        foreach ($d in $dash) { if ($stop.Success -and $d.Index -gt $stop.Index) { break }; $cnt++ }
        $g1Values += @{ Src = "mcp_alpha_list_$($i + 1)"; Val = $cnt }
    }
    # tree list length — informational only (known docs-planner drift)
    $treeHdr = [regex]::Match($mcpRaws[$i].Text, '(?m)^### Agent Files List \((\d+) files\)\r?$')
    if ($treeHdr.Success) {
        $after2 = $mcpRaws[$i].Text.Substring($treeHdr.Index + $treeHdr.Length)
        if ($after2 -notmatch 'docs-planner\.md') { $warns += 'WARN:mcp tree list pre-existing drift (docs-planner.md missing) — informational' }
    }
}

function Assert-Group([object[]]$Values, [string]$GroupId) {
    if ($Values.Count -eq 0) { return $null }
    $ref = $Values[0].Val
    foreach ($v in $Values) {
        if ($v.Val -ne $ref) { Add-Diff $v.Src $GroupId $v.Val $ref }
    }
    return $ref
}
$wlN = Assert-Group $wlValues 'whitelist'
$g1 = Assert-Group $g1Values 'subagents_total'
$g2 = Assert-Group $g2Values 'agents_total'
if ($script:DiffLines.Count -gt 0) {
    foreach ($d in $script:DiffLines) { Write-Output $d }
    Write-Output 'BLOCK:counter cross-check failed — sources disagree (run integrity-check / config-sync)'
    exit 3
}
if ($null -eq $wlN -or $null -eq $g1 -or $null -eq $g2) {
    Write-Output 'BLOCK:counter cross-check failed — could not parse all counters'
    exit 3
}

# ============================================================================
# Anchor edit functions (each returns @{ Text; Error; ... } — zero writes on error)
# ============================================================================

# H5: universal +1 substitution of numbered capture groups in a UNIQUE match.
function Edit-NumberedCounter([string]$Text, [string]$Pattern, [int[]]$GroupIndices) {
    $res = @{ Text = $null; Old = @(); New = @(); Error = $null }
    $rx = New-Object System.Text.RegularExpressions.Regex($Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $ms = $rx.Matches($Text)
    if ($ms.Count -ne 1) { $res.Error = "anchor found $($ms.Count) times (expected 1): $Pattern"; return $res }
    $m = $ms[0]
    $spans = @()
    foreach ($gi in $GroupIndices) {
        $g = $m.Groups[$gi]
        if (-not $g.Success) { $res.Error = "capture group $gi did not participate: $Pattern"; return $res }
        $spans += @{ Index = $g.Index; Length = $g.Length; NewVal = ([string]([int]$g.Value + 1)) }
        $res.Old += [int]$g.Value
    }
    $spans = @($spans | Sort-Object { $_.Index })
    $newText = $Text
    for ($i = $spans.Count - 1; $i -ge 0; $i--) {
        $s = $spans[$i]
        $newText = $newText.Substring(0, $s.Index) + $s.NewVal + $newText.Substring($s.Index + $s.Length)
        $res.New = @([int]$s.NewVal) + $res.New
    }
    $res.Text = $newText
    return $res
}

# H4: append a token to ROUTING_TABLES.<primary> (TS code blocks; '...' and "..." styles).
function Edit-RoutingArray([string]$Text, [string]$PrimaryName, [string]$NewName, [string]$SectionHeading) {
    $res = @{ Text = $null; OldCount = 0; Error = $null }
    $base = 0
    if ($SectionHeading) {
        $h = [regex]::Match($Text, $SectionHeading, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if (-not $h.Success) { $res.Error = "anchor: section not found: $SectionHeading"; return $res }
        $base = $h.Index
    }
    $sub = $Text.Substring($base)
    $outer = [regex]::Match($sub, '(?s)const ROUTING_TABLES = \{(.*?)\r?\n\}')
    if (-not $outer.Success) { $res.Error = 'anchor: const ROUTING_TABLES not found'; return $res }
    $inner = [regex]::Match($outer.Groups[1].Value, ('(?s)' + [regex]::Escape($PrimaryName) + '\s*:\s*\[(.*?)\]'))
    if (-not $inner.Success) { $res.Error = "anchor: ROUTING_TABLES.$PrimaryName array not found"; return $res }
    $innerText = $inner.Groups[1].Value
    $tokens = [regex]::Matches($innerText, $script:TokenRx)
    if ($tokens.Count -eq 0) { $res.Error = "anchor: ROUTING_TABLES.$PrimaryName has no tokens"; return $res }
    foreach ($t in $tokens) {
        if ($t.Value.Trim('"', [char]0x27) -eq $NewName) { $res.Error = "token already present in ROUTING_TABLES.$PrimaryName`: $NewName"; return $res }
    }
    $res.OldCount = $tokens.Count
    $last = $tokens[$tokens.Count - 1]
    $absBase = $base + $outer.Index + $outer.Groups[1].Index + $inner.Groups[1].Index
    $insertPos = $absBase + $last.Index + $last.Length
    $lineStart = $Text.LastIndexOf("`n", $insertPos) + 1
    $lead = $Text.Substring($lineStart, $insertPos - $lineStart)
    $indent = ''
    if ($lead.Length -gt 0) { $indent = $lead.Substring(0, $lead.Length - $lead.TrimStart(' ', "`t").Length) }
    $eolM = [regex]::Match($Text.Substring($insertPos), '\r\n|\r|\n')
    $eol = $(if ($eolM.Success) { $eolM.Value } else { '' })
    if (-not $eol) { $eol = Detect-Eol $Text }
    $quote = $last.Value[0]
    $insertText = ',' + $eol + $indent + $quote + $NewName + $quote
    $res.Text = $Text.Substring(0, $insertPos) + $insertText + $Text.Substring($insertPos)
    return $res
}

# Whitelist table: header +1, append row (numbered for ARCH, plain elsewhere).
function Edit-WhitelistTable([string]$Text, [string]$PrimaryName, [string]$NewRowContent) {
    $res = @{ Text = $null; OldCount = 0; Error = $null }
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $span = Find-SectionSpan $lines ('^### ' + [regex]::Escape($PrimaryName) + ' Whitelist \((\d+) agents\)') '^#{2,3} '
    if (-not $span) { $res.Error = "anchor: whitelist section not found for '$PrimaryName'"; return $res }
    $hm = [regex]::Match($lines[$span.Start], '\((\d+) agents\)')
    if (-not $hm.Success) { $res.Error = 'anchor: whitelist header count not parsed'; return $res }
    $old = [int]$hm.Groups[1].Value
    $res.OldCount = $old
    $lines[$span.Start] = [regex]::Replace($lines[$span.Start], '\(\d+ agents\)', ('(' + ($old + 1) + ' agents)'), 1)
    $lastRow = -1
    for ($i = $span.Start + 2; $i -lt $span.End; $i += 2) {
        if ($lines[$i] -match '^\|') { $lastRow = $i }
    }
    if ($lastRow -lt 0) { $res.Error = "anchor: whitelist table rows not found for '$PrimaryName'"; return $res }
    $eol = Get-Eol $lines $lastRow
    if (-not $eol) { $eol = Detect-Eol $Text; if (-not $eol) { $eol = "`r`n" } }
    $lines.Insert($lastRow + 2, $NewRowContent)
    $lines.Insert($lastRow + 3, $eol)
    $res.Text = ($lines -join '')
    return $res
}

# ARCH: ## Subagent Models — append '| <name> | <model> |' after the last data row.
function Edit-SubagentModelsAppend([string]$Text, [string]$NewRowContent) {
    $res = @{ Text = $null; Error = $null }
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $span = Find-SectionSpan $lines '^## Subagent Models' '^## '
    if (-not $span) { $res.Error = 'anchor: ## Subagent Models section not found'; return $res }
    $lastRow = -1
    for ($i = $span.Start + 2; $i -lt $span.End; $i += 2) {
        if ($lines[$i] -match '^\| .+? \| .+? \|$') { $lastRow = $i }
    }
    if ($lastRow -lt 0) { $res.Error = 'anchor: Subagent Models data rows not found'; return $res }
    $eol = Get-Eol $lines $lastRow
    if (-not $eol) { $eol = Detect-Eol $Text; if (-not $eol) { $eol = "`r`n" } }
    $lines.Insert($lastRow + 2, $NewRowContent)
    $lines.Insert($lastRow + 3, $eol)
    $res.Text = ($lines -join '')
    return $res
}

# ARCH: Model Roles — ADD branch (port of migrate.ps1 Edit-ModelRoles).
function Edit-ModelRolesAdd([string]$Text, [string]$AgentName, [string]$NewModel, [string]$RoleName, [string]$TierName) {
    $res = @{ Text = $null; Error = $null; Warns = @(); NewRole = $null }
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $span = Find-SectionSpan $lines '^## Model Roles' '^\u041A\u043E\u043D\u0442\u0440\u043E\u043B\u044C \u0441\u0443\u043C\u043C\u044B:'
    if (-not $span) { $res.Error = 'anchor: ## Model Roles section not found'; return $res }
    $rowPat = '^\| (.+?) \| (.+?) \| (.+?) \| (.*?) \|$'
    $rows = @()
    for ($i = $span.Start; $i -lt $span.End; $i += 2) {
        $m = [regex]::Match($lines[$i], $rowPat)
        if ($m.Success -and $m.Groups[1].Value.Trim() -ne 'Role') {
            $rows += @{ Idx = $i; Role = $m.Groups[1].Value.Trim(); Model = $m.Groups[2].Value.Trim(); Tier = $m.Groups[3].Value.Trim(); Agents = $m.Groups[4].Value.Trim() }
        }
    }
    if ($rows.Count -eq 0) { $res.Error = 'anchor: Model Roles data rows not found'; return $res }
    $cands = @($rows | Where-Object { $_.Model -eq $NewModel })
    if ($cands.Count -eq 1) {
        if ($RoleName -and $RoleName -ne $cands[0].Role) {
            $res.Error = "-Role '$RoleName' does not match the single role row '$($cands[0].Role)'"; return $res
        }
        $nr = $cands[0]
        $toks = @(Split-Tokens $nr.Agents)
        if ($toks -notcontains $AgentName) { $toks += $AgentName }
        $lines[$nr.Idx] = "| $($nr.Role) | $($nr.Model) | $($nr.Tier) | $($toks -join ', ') |"
        $res.NewRole = $nr.Role
    } elseif ($cands.Count -gt 1) {
        if (-not $RoleName) {
            $res.Error = 'model maps to >1 role rows; -Role required. Candidates: ' + (($cands | ForEach-Object { $_.Role }) -join ', '); return $res
        }
        $m2 = @($cands | Where-Object { $_.Role -eq $RoleName })
        if ($m2.Count -ne 1) {
            $res.Error = "-Role '$RoleName' not found among candidate rows: " + (($cands | ForEach-Object { $_.Role }) -join ', '); return $res
        }
        $nr = $m2[0]
        $toks = @(Split-Tokens $nr.Agents)
        if ($toks -notcontains $AgentName) { $toks += $AgentName }
        $lines[$nr.Idx] = "| $($nr.Role) | $($nr.Model) | $($nr.Tier) | $($toks -join ', ') |"
        $res.NewRole = $nr.Role
    } else {
        if (-not $RoleName -or -not $TierName) {
            $res.Error = 'model has no role row; -Role and -Tier required. Available roles: ' + (($rows | ForEach-Object { $_.Role }) -join ', '); return $res
        }
        $res.Warns += "WARN:new role '$RoleName' requires CHANGELOG justification"
        $last = $rows[$rows.Count - 1]
        $eol = Get-Eol $lines $last.Idx
        if (-not $eol) { $eol = "`r`n" }
        $insertAt = $last.Idx + 2
        $lines.Insert($insertAt, "| $RoleName | $NewModel | $TierName | $AgentName |")
        $lines.Insert($insertAt + 1, $eol)
        $res.NewRole = $RoleName
    }
    $res.Text = ($lines -join '')
    return $res
}

# MCP: **Task Whitelist (N agents):** of -Primary — header +1, comma list append.
function Edit-TaskWhitelist([string]$Text, [string]$PrimaryName, [string]$NewName) {
    $res = @{ Text = $null; OldCount = 0; Error = $null }
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $hitIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i += 2) {
        if ($lines[$i] -match '^\*\*Task Whitelist \((\d+) agents\):\*\*$') {
            $owner = $null
            for ($j = $i - 2; $j -ge 0; $j -= 2) {
                $hm = [regex]::Match($lines[$j], '^#### (orchestrator|plankestrator)$')
                if ($hm.Success) { $owner = $hm.Groups[1].Value; break }
            }
            if ($owner -eq $PrimaryName) {
                if ($hitIdx -ge 0) { $res.Error = "anchor: Task Whitelist for '$PrimaryName' found more than once"; return $res }
                $hitIdx = $i
            }
        }
    }
    if ($hitIdx -lt 0) { $res.Error = "anchor: Task Whitelist header not found for '$PrimaryName'"; return $res }
    $hm = [regex]::Match($lines[$hitIdx], '\((\d+) agents\)')
    $res.OldCount = [int]$hm.Groups[1].Value
    $lines[$hitIdx] = [regex]::Replace($lines[$hitIdx], '\(\d+ agents\)', ('(' + ($res.OldCount + 1) + ' agents)'), 1)
    $listIdx = -1
    for ($i = $hitIdx + 2; $i -lt $lines.Count; $i += 2) {
        if ($lines[$i].Trim()) { $listIdx = $i; break }
    }
    if ($listIdx -lt 0) { $res.Error = 'anchor: Task Whitelist comma list not found'; return $res }
    $toks = @(Split-Tokens $lines[$listIdx])
    if ($toks -contains $NewName) { $res.Error = "token already present in Task Whitelist: $NewName"; return $res }
    $lines[$listIdx] = $lines[$listIdx].TrimEnd() + ', ' + $NewName
    $res.Text = ($lines -join '')
    return $res
}

# MCP: Models Distribution — ADD branch (port of migrate.ps1 Edit-Distribution).
function Edit-DistributionAdd([string]$Text, [string]$AgentName, [string]$NewShort) {
    $res = @{ Text = $null; Error = $null; Warns = @(); Shorts = @(); RowCreated = $false; NewCount = 0 }
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $span = Find-SectionSpan $lines '^### Models Distribution' '^### '
    if (-not $span) { $res.Error = 'anchor: ### Models Distribution section not found'; return $res }
    $rowPat = '^\| `(.+?)` \| (.+?) \| (\d+) \| (.*?) \|$'
    $rows = @()
    for ($i = $span.Start; $i -lt $span.End; $i += 2) {
        $m = [regex]::Match($lines[$i], $rowPat)
        if ($m.Success -and $m.Groups[1].Value.Trim() -ne 'Model') {
            $rows += @{ Idx = $i; Short = $m.Groups[1].Value.Trim(); Provider = $m.Groups[2].Value.Trim(); Count = [int]$m.Groups[3].Value; Agents = $m.Groups[4].Value.Trim() }
        }
    }
    if ($rows.Count -eq 0) { $res.Error = 'anchor: Models Distribution data rows not found'; return $res }
    $newRows = @($rows | Where-Object { $_.Short -eq $NewShort })
    if ($newRows.Count -eq 1) {
        $nr = $newRows[0]
        $toks = @(Split-Tokens $nr.Agents)
        if ($toks -notcontains $AgentName) { $toks += $AgentName }
        $lines[$nr.Idx] = "| ``$($nr.Short)`` | $($nr.Provider) | $($toks.Count) | $($toks -join ', ') |"
        $res.NewCount = $toks.Count
    } elseif ($newRows.Count -eq 0) {
        $last = $rows[$rows.Count - 1]
        $eol = Get-Eol $lines $last.Idx
        if (-not $eol) { $eol = "`r`n" }
        $insertAt = $last.Idx + 2
        $lines.Insert($insertAt, "| ``$NewShort`` | bifrost-litellm | 1 | $AgentName |")
        $lines.Insert($insertAt + 1, $eol)
        $res.RowCreated = $true
        $res.NewCount = 1
    } else {
        $res.Error = "anchor: Distribution row for '$NewShort' found $($newRows.Count) times (expected 1)"; return $res
    }
    $bound = [Math]::Min($span.End + 2, $lines.Count)
    for ($i = $span.Start; $i -lt $bound; $i += 2) {
        $m = [regex]::Match($lines[$i], $rowPat)
        if ($m.Success -and $m.Groups[1].Value.Trim() -ne 'Model') { $res.Shorts += $m.Groups[1].Value.Trim() }
    }
    $res.Text = ($lines -join '')
    return $res
}

# MCP: Summary Models row (regenerate from distribution shorts).
function Edit-SummaryModelsRow([string]$Text, [string[]]$Shorts) {
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $pat = '^\| Models \| \d+ \| bifrost-litellm \(.*\) \|$'
    $hits = @()
    for ($i = 0; $i -lt $lines.Count; $i += 2) {
        if ($lines[$i] -match $pat) { $hits += $i }
    }
    if ($hits.Count -ne 1) { return @{ Text = $null; Error = "anchor: Summary Models row found $($hits.Count) times (expected 1)" } }
    $lines[$hits[0]] = "| Models | $($Shorts.Count) | bifrost-litellm ($($Shorts -join ', ')) |"
    return @{ Text = ($lines -join ''); Error = $null }
}

# MCP: Subagents Full Table — append row after the last **agent** row.
function Edit-FullTableAppend([string]$Text, [string]$NewRowContent) {
    $res = @{ Text = $null; Error = $null }
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $span = Find-SectionSpan $lines '^### Subagents \u2014 Full Table' '^### '
    if (-not $span) { $res.Error = 'anchor: ### Subagents Full Table section not found'; return $res }
    $lastRow = -1
    for ($i = $span.Start + 2; $i -lt $span.End; $i += 2) {
        if ($lines[$i] -match '^\| \*\*') { $lastRow = $i }
    }
    if ($lastRow -lt 0) { $res.Error = 'anchor: Full Table data rows not found'; return $res }
    $eol = Get-Eol $lines $lastRow
    if (-not $eol) { $eol = Detect-Eol $Text; if (-not $eol) { $eol = "`r`n" } }
    $lines.Insert($lastRow + 2, $NewRowContent)
    $lines.Insert($lastRow + 3, $eol)
    $res.Text = ($lines -join '')
    return $res
}

# MCP: **Subagents (N):** alpha insert of '- <name>.md'.
function Edit-AlphaInsert([string]$Text, [string]$FileName) {
    $res = @{ Text = $null; Error = $null }
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $anchor = Find-UniqueLine $lines '^\*\*Subagents \(\d+\):\*\*$'
    if ($anchor.Error) { $res.Error = $anchor.Error; return $res }
    $start = $anchor.Index
    $end = $start
    for ($i = $start + 2; $i -lt $lines.Count; $i += 2) {
        if ($lines[$i] -match '^- [^\r\n]+\.md$') { $end = $i } else { break }
    }
    if ($end -eq $start) { $res.Error = 'anchor: Subagents file list not found'; return $res }
    $insertAt = -1
    for ($i = $start + 2; $i -le $end; $i += 2) {
        $cur = $lines[$i] -replace '^- ', ''
        if ([string]::CompareOrdinal($cur, $FileName) -gt 0) { $insertAt = $i; break }
    }
    $eol = Get-Eol $lines $end
    if (-not $eol) { $eol = Detect-Eol $Text; if (-not $eol) { $eol = "`r`n" } }
    $newContent = '- ' + $FileName
    if ($insertAt -lt 0) {
        $lines.Insert($end + 2, $newContent)
        $lines.Insert($end + 3, $eol)
    } else {
        $lines.Insert($insertAt, $newContent)
        $lines.Insert($insertAt + 1, $eol)
    }
    $res.Text = ($lines -join '')
    return $res
}

# MCP: Agent Files List tree — insert 'branch <name>.md' before the last corner line.
function Edit-TreeInsert([string]$Text, [string]$FileName) {
    $res = @{ Text = $null; Error = $null }
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $anchor = Find-UniqueLine $lines '^### Agent Files List \(\d+ files\)$'
    if ($anchor.Error) { $res.Error = $anchor.Error; return $res }
    $lastCorner = -1
    $treeStart = -1
    for ($i = $anchor.Index + 2; $i -lt $lines.Count; $i += 2) {
        if ($lines[$i] -match '^\u251C\u2500\u2500 ') { if ($treeStart -lt 0) { $treeStart = $i } }
        if ($lines[$i] -match '^\u2514\u2500\u2500 ') { $lastCorner = $i; break }
    }
    if ($lastCorner -lt 0) { $res.Error = 'anchor: Agent Files List tree not found'; return $res }
    $eol = Get-Eol $lines $lastCorner
    if (-not $eol) { $eol = Detect-Eol $Text; if (-not $eol) { $eol = "`r`n" } }
    $branch = [string][char]0x251C + [string][char]0x2500 + [string][char]0x2500
    $lines.Insert($lastCorner, $branch + ' ' + $FileName)
    $lines.Insert($lastCorner + 1, $eol)
    $res.Text = ($lines -join '')
    return $res
}

# Primary .md: append '["<name>"]' to the OPENCODE_ROUTING_TABLE line.
function Edit-RoutingLine([string]$Text, [string]$NewName) {
    $res = @{ Text = $null; OldCount = 0; Error = $null }
    $m = [regex]::Match($Text, '(?m)^OPENCODE_ROUTING_TABLE = \[(.*)\]\r?$')
    if (-not $m.Success) { $res.Error = 'anchor: OPENCODE_ROUTING_TABLE line not found'; return $res }
    $toks = @((Split-Tokens $m.Groups[1].Value) | ForEach-Object { $_.Trim('"', [char]0x27) })
    if ($toks -contains $NewName) { $res.Error = "token already present in OPENCODE_ROUTING_TABLE: $NewName"; return $res }
    $res.OldCount = $toks.Count
    $newInner = $m.Groups[1].Value.TrimEnd() + ', "' + $NewName + '"'
    $res.Text = $Text.Substring(0, $m.Groups[1].Index) + $newInner + $Text.Substring($m.Groups[1].Index + $m.Groups[1].Length)
    return $res
}

# opencode.json: insert the new agent section right after '  "agent": {'.
function Edit-JsonAgentSection([string]$Text, [string]$SectionText) {
    $res = @{ Text = $null; Error = $null }
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $anchor = Find-UniqueLine $lines '^  "agent": \{$'
    if ($anchor.Error) { $res.Error = $anchor.Error; return $res }
    $eol = Get-Eol $lines $anchor.Index
    if (-not $eol) { $eol = Detect-Eol $Text; if (-not $eol) { $eol = "`r`n" } }
    $lines.Insert($anchor.Index + 2, $SectionText)
    $lines.Insert($anchor.Index + 3, $eol)
    $res.Text = ($lines -join '')
    return $res
}

# opencode.json: add '"<name>": "allow"' to the primary task block.
function Edit-PrimaryTaskAllow([string]$Text, [string]$PrimaryName, [string]$NewName) {
    $res = @{ Text = $null; Error = $null }
    $anchorPat = '(?m)^    "' + [regex]::Escape($PrimaryName) + '": \{$'
    $am = [regex]::Match($Text, $anchorPat)
    if (-not $am.Success) { $res.Error = "anchor: agent section for '$PrimaryName' not found in opencode.json"; return $res }
    $secSpan = Find-JsonSpan $Text $anchorPat
    if (-not $secSpan) { $res.Error = "anchor: agent section span not resolved for '$PrimaryName'"; return $res }
    $secText = $Text.Substring($secSpan.Open, $secSpan.Close - $secSpan.Open + 1)
    $tm = [regex]::Match($secText, '"task":\s*\{')
    if (-not $tm.Success) { $res.Error = "anchor: task block not found for '$PrimaryName'"; return $res }
    $taskSpan = Find-JsonSpan $secText '"task":\s*\{'
    if (-not $taskSpan) { $res.Error = "anchor: task span not resolved for '$PrimaryName'"; return $res }
    $taskText = $secText.Substring($taskSpan.Open, $taskSpan.Close - $taskSpan.Open + 1)
    if ([regex]::IsMatch($taskText, ('"' + [regex]::Escape($NewName) + '"'))) {
        $res.Error = "token already present in task block of $PrimaryName`: $NewName"; return $res
    }
    # Insert after the LAST non-whitespace char of the task block (end of the last
    # entry line): ',' + EOL + 10-space indent + the new allow entry; the existing
    # '\n        }' tail then follows naturally.
    $absClose = $secSpan.Open + $taskSpan.Close
    $insertPos = $absClose
    while ($insertPos -gt 0 -and [char]::IsWhiteSpace($Text[$insertPos - 1])) { $insertPos-- }
    $eol = Detect-Eol $Text
    $insertText = ',' + $eol + '          "' + $NewName + '": "allow"'
    $res.Text = $Text.Substring(0, $insertPos) + $insertText + $Text.Substring($insertPos)
    return $res
}

# ============================================================================
# Generated content
# ============================================================================
# Decimal separator must be a DOT in JSON/frontmatter regardless of the OS
# culture (ru-RU uses ','). [string] cast + comma normalization is bulletproof
# on PS 5.1 where ToString(IFormatProvider) proved unreliable in this setup.
$tempStr = ([string]$Temperature) -replace ',', '.'
$descFm = $Description
if ($Description -match ': ') {
    $descFm = [char]0x27 + ($Description -replace [string][char]0x27, ([string][char]0x27 + [string][char]0x27)) + [char]0x27
    $warns += 'WARN:description contains ": " — auto-wrapped in single quotes in frontmatter (YAML silent-drop guard)'
}
if ($Description -match '\|') {
    $warns += 'WARN:description contains "|" — markdown table cells may render broken'
}

# Frontmatter permission lines: preset or template; ensure task extras are present.
# Mirrors add.py add_fm_task_extras: extras already present as allow entries
# (template block embeds its own task tokens) are skipped.
function Add-FmTaskExtras([string[]]$PermLines, [string[]]$Extras) {
    if ($Extras.Count -eq 0) { return ,$PermLines }
    $taskIdx = -1
    for ($i = 0; $i -lt $PermLines.Count; $i++) { if ($PermLines[$i] -match '^task:\s*$') { $taskIdx = $i; break } }
    if ($taskIdx -lt 0) {
        $out = New-Object System.Collections.Generic.List[string]
        foreach ($l in $PermLines) { $out.Add($l) }
        $out.Add('task:')
        $out.Add('    "*": deny')
        foreach ($t in $Extras) { $out.Add('    ' + $t + ': allow') }
        return ,$out
    }
    $existing = @{}
    for ($i = $taskIdx + 1; $i -lt $PermLines.Count; $i++) {
        $m = [regex]::Match($PermLines[$i], "^\s*`"?([^:`"']+)`"?:\s*allow\s*$")
        if ($m.Success) { $existing[$m.Groups[1].Value.Trim()] = $true }
    }
    $extras2 = @($Extras | Where-Object { -not $existing.ContainsKey($_) })
    $starIdx = -1
    for ($i = $taskIdx + 1; $i -lt $PermLines.Count; $i++) {
        if ($PermLines[$i] -match '^\s*"\*": deny\s*$') { $starIdx = $i }
    }
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $PermLines.Count; $i++) {
        $out.Add($PermLines[$i])
        if ($i -eq $starIdx) {
            foreach ($t in $extras2) { $out.Add('    ' + $t + ': allow') }
        }
    }
    if ($starIdx -lt 0) {
        foreach ($t in $extras2) { $out.Add('    ' + $t + ': allow') }
    }
    return ,$out
}

$fmBody = $null
if ($BodyFile) {
    $fmBody = (Read-RawText $BodyFile).Text
} else {
    $warns += 'WARN:body is a stub (-BodyFile not given)'
    $fmBody = "You are the $Agent agent.`n`nTODO: prompt body (generated stub - author the real prompt).`n"
}

$fmLines = New-Object System.Collections.Generic.List[string]
$fmLines.Add('---')
$fmLines.Add('description: ' + $descFm)
$fmLines.Add('mode: subagent')
$fmLines.Add('model: ' + $Model)
$fmLines.Add('temperature: ' + $tempStr)
$fmLines.Add('permission:')
$fmExtras = $(if ($PermTemplate) { $taskAllowList } else { $taskEntries })
$permL = @(Add-FmTaskExtras $fmPermLines $fmExtras)
foreach ($l in $permL) { $fmLines.Add('  ' + $l) }
$fmLines.Add('---')
$fmLines.Add('')
$agentFileText = ($fmLines -join "`n") + $fmBody
if (-not $agentFileText.EndsWith("`n")) { $agentFileText += "`n" }

# JSON agent section (preset-built or template-copied).
if ($script:TplJsonSection) {
    $eolJ = Detect-Eol $liveCfgText
    $sec = $script:TplJsonSection -replace ('^(\s*")' + [regex]::Escape($PermTemplate) + '("\s*:\s*\{)'), ('$1' + $Agent + '$2')
    if ($taskAllowList.Count -gt 0) {
        $tspan = Find-JsonSpan $sec '"task":\s*\{'
        if ($tspan) {
            $taskText = $sec.Substring($tspan.Open, $tspan.Close - $tspan.Open + 1)
            $extraLines = @($taskAllowList | ForEach-Object { '          "' + $_ + '": "allow"' })
            $insert = ',' + $eolJ + ($extraLines -join (',' + $eolJ))
            $sec = $sec.Substring(0, $tspan.Close) + $insert + $sec.Substring($tspan.Close)
        } else {
            $warns += "WARN:perm-template has no JSON task block — -TaskAllow extras not added to opencode.json"
        }
    }
    $jsonSection = $sec + ','
} else {
    $eolJ = Detect-Eol $liveCfgText
    $secLines = New-Object System.Collections.Generic.List[string]
    $secLines.Add('    "' + $Agent + '": {')
    $secLines.Add('      "mode": "subagent",')
    $secLines.Add('      "temperature": ' + $tempStr + ',')
    $secLines.Add('      "permission": {')
    foreach ($l in $jsonPermLines) { $secLines.Add('        ' + $l + ',') }
    $secLines.Add('        "task": {')
    $secLines.Add('          "*": "deny"')
    foreach ($t in $taskEntries) {
        $secLines[$secLines.Count - 1] = $secLines[$secLines.Count - 1] + ','
        $secLines.Add('          "' + $t + '": "allow"')
    }
    $secLines.Add('        }')
    $secLines.Add('      },')
    $secLines.Add('      "options": {}')
    $secLines.Add('    },')
    $jsonSection = ($secLines -join $eolJ)
}

$enDash = [string][char]0x2013
$extrasCell = ($taskEntries -join ', ')
if (-not $extrasCell) { $extrasCell = $enDash }
$bashCell = $fullCells.bash
if ($bashCell -eq 'allow') { $bashCell = '**allow**' }
$fullTableRow = '| **' + $Agent + '** | subagent | ' + $Model + ' | ' + $tempStr + ' | ' + $fullCells.edit + ' | ' + $fullCells.write + ' | ' + $fullCells.read + ' | ' + $bashCell + ' | ' + $extrasCell + ' |'
$descCell = $Description

# ============================================================================
# Compute ALL edits in memory (two-phase: zero writes on any error)
# ============================================================================
$pending = [ordered]@{}
$planLines = @()

function Block([string]$Msg) {
    Write-Output "BLOCK:$Msg"
    Write-Output 'WARN:zero files written (two-phase all-or-nothing)'
    exit 3
}

# --- groups 3-4: opencode.json live + deploy
$newLiveCfgText = $liveCfgRaw.Text
$r = Edit-JsonAgentSection $newLiveCfgText $jsonSection
if ($r.Error) { Block $r.Error }
$newLiveCfgText = $r.Text
$r = Edit-PrimaryTaskAllow $newLiveCfgText $Primary $Agent
if ($r.Error) { Block $r.Error }
$newLiveCfgText = $r.Text
try { $null = $newLiveCfgText | ConvertFrom-Json } catch { Block "new live opencode.json does not parse: $_" }
$pending[$liveCfgPath] = @{ Text = $newLiveCfgText; Bom = $liveCfgRaw.Bom; Rel = (Get-RelPath $liveCfgPath) }
$planLines += "PLAN:$(Get-RelPath $liveCfgPath) agent_section+task_allow"

$newDeployCfgText = $deployCfgRaw.Text
$r = Edit-JsonAgentSection $newDeployCfgText $jsonSection
if ($r.Error) { Block $r.Error }
$newDeployCfgText = $r.Text
$r = Edit-PrimaryTaskAllow $newDeployCfgText $Primary $Agent
if ($r.Error) { Block $r.Error }
$newDeployCfgText = $r.Text
try { $null = $newDeployCfgText | ConvertFrom-Json } catch { Block "new deploy opencode.json does not parse: $_" }
$pending[$deployCfgPath] = @{ Text = $newDeployCfgText; Bom = $deployCfgRaw.Bom; Rel = (Get-RelPath $deployCfgPath) }
$planLines += "PLAN:$(Get-RelPath $deployCfgPath) agent_section+task_allow"

# --- group 5: plugin x3
for ($i = 0; $i -lt 3; $i++) {
    $r = Edit-RoutingArray $pluginRaws[$i].Text $Primary $Agent ''
    if ($r.Error) { Block $r.Error }
    $pending[$pluginPaths[$i]] = @{ Text = $r.Text; Bom = $pluginRaws[$i].Bom; Rel = (Get-RelPath $pluginPaths[$i]) }
    $planLines += "PLAN:$(Get-RelPath $pluginPaths[$i]) routing_array[$Primary] old=$($r.OldCount) new=$($r.OldCount + 1)"
}

# --- group 6: primary .md x2
for ($i = 0; $i -lt 2; $i++) {
    $path = $(if ($i -eq 0) { $primaryLiveMd } else { $primaryDeployMd })
    $r = Edit-RoutingLine $primaryRaws[$i].Text $Agent
    if ($r.Error) { Block $r.Error }
    $pending[$path] = @{ Text = $r.Text; Bom = $primaryRaws[$i].Bom; Rel = (Get-RelPath $path) }
    $planLines += "PLAN:$(Get-RelPath $path) opencode_routing_table old=$($r.OldCount) new=$($r.OldCount + 1)"
}

# --- group 7: ARCHITECTURE.md x3
$numberedRow = '| ' + ($wlN + 1) + ' | ' + $Agent + ' | ' + $descCell + ' |'
$plainRow = '| ' + $Agent + ' | ' + $descCell + ' |'
for ($i = 0; $i -lt 3; $i++) {
    $t = $archRaws[$i].Text
    $r = Edit-WhitelistTable $t $Primary $numberedRow
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $archPaths[$i]) whitelist header+row old=$($r.OldCount) new=$($r.OldCount + 1)"
    $r = Edit-NumberedCounter $t ('(?m)^\| ' + [regex]::Escape($Primary) + ' \| (\d+) \| (\d+) \(' + [regex]::Escape($Primary) + ' \+ (\d+) subagents\) \|\r?$') @(1, 2, 3)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $archPaths[$i]) agent_count_summary old=$($r.Old -join '/') new=$($r.New -join '/')"
    $r = Edit-NumberedCounter $t '(?m)^\| \*\*Grand Total\*\* \| \*\*(\d+)\*\* \| \*\*(\d+)\*\* \|\r?$' @(1, 2)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $archPaths[$i]) grand_total old=$($r.Old -join '/') new=$($r.New -join '/')"
    $r = Edit-NumberedCounter $t '(?m)^Note: (\d+) whitelist entries[^\r\n]*?= (\d+) unique whitelisted subagents[^\r\n]*?(\d+) unique subagents \+ 2 primary agents = (\d+) unique agents total\.' @(1, 2, 3, 4)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $archPaths[$i]) note_counters old=$($r.Old -join '/') new=$($r.New -join '/')"
    $r = Edit-SubagentModelsAppend $t ('| ' + $Agent + ' | ' + $Model + ' |')
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $archPaths[$i]) subagent_models_row model=$Model"
    $r = Edit-NumberedCounter $t '(?m)\u043C\u043E\u0434\u0435\u043B\u0435\u0439 (\d+) \u0430\u0433\u0435\u043D\u0442\u0430\u043C' @(1)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $archPaths[$i]) model_roles_intro old=$($r.Old[0]) new=$($r.New[0])"
    $r = Edit-ModelRolesAdd $t $Agent $Model $Role $Tier
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $warns += $r.Warns
    $planLines += "PLAN:$(Get-RelPath $archPaths[$i]) model_roles_agents role=$($r.NewRole)"
    $r = Edit-NumberedCounter $t '(?m)^\u041A\u043E\u043D\u0442\u0440\u043E\u043B\u044C \u0441\u0443\u043C\u043C\u044B: 2 primary \+ (\d+) subagents = (\d+) \u0430\u0433\u0435\u043D\u0442\u043E\u0432;' @(1, 2)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $archPaths[$i]) kontrol_summy old=$($r.Old -join '/') new=$($r.New -join '/')"
    $pending[$archPaths[$i]] = @{ Text = $t; Bom = $archRaws[$i].Bom; Rel = (Get-RelPath $archPaths[$i]) }
}

# --- group 8: AGENTS.md x3
for ($i = 0; $i -lt 3; $i++) {
    $t = $agentsMdRaws[$i].Text
    $r = Edit-WhitelistTable $t $Primary $plainRow
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $agentsMdPaths[$i]) whitelist header+row old=$($r.OldCount) new=$($r.OldCount + 1)"
    $r = Edit-NumberedCounter $t '(?m)\u0432\u0441\u0435\u043C (\d+) \u0430\u0433\u0435\u043D\u0442\u0430\u043C' @(1)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $agentsMdPaths[$i]) model_roles_prose old=$($r.Old[0]) new=$($r.New[0])"
    $pending[$agentsMdPaths[$i]] = @{ Text = $t; Bom = $agentsMdRaws[$i].Bom; Rel = (Get-RelPath $agentsMdPaths[$i]) }
}

# --- group 9: PLUGIN.md x3
for ($i = 0; $i -lt 3; $i++) {
    $t = $pluginMdRaws[$i].Text
    $r = Edit-WhitelistTable $t $Primary $plainRow
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $pluginMdPaths[$i]) whitelist header+row old=$($r.OldCount) new=$($r.OldCount + 1)"
    $r = Edit-RoutingArray $t $Primary $Agent '^### Routing Table Implementation'
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $pluginMdPaths[$i]) routing_code_block[$Primary] old=$($r.OldCount) new=$($r.OldCount + 1)"
    $pending[$pluginMdPaths[$i]] = @{ Text = $t; Bom = $pluginMdRaws[$i].Bom; Rel = (Get-RelPath $pluginMdPaths[$i]) }
}

# --- group 10: MCP_SETUP.md x2
$newShort = $ModelKey
for ($i = 0; $i -lt 2; $i++) {
    $t = $mcpRaws[$i].Text
    $r = Edit-NumberedCounter $t '(?m)^\| Subagents \| (\d+) \|\r?$' @(1)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $r = Edit-NumberedCounter $t '(?m)^\| \*\*Total unique agents\*\* \| \*\*(\d+)\*\* \|\r?$' @(1)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $r = Edit-NumberedCounter $t '(?m)\u0432\u0441\u0435 (\d+) subagents' @(1)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $r = Edit-TaskWhitelist $t $Primary $Agent
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $mcpPaths[$i]) task_whitelist old=$($r.OldCount) new=$($r.OldCount + 1)"
    $r = Edit-WhitelistTable $t $Primary $plainRow
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $mcpPaths[$i]) whitelist_s6 header+row old=$($r.OldCount) new=$($r.OldCount + 1)"
    $r = Edit-RoutingArray $t $Primary $Agent '^### Routing Tables in Plugin'
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $mcpPaths[$i]) routing_plugin_block[$Primary] old=$($r.OldCount) new=$($r.OldCount + 1)"
    $distInfo = $null
    $r = Edit-DistributionAdd $t $Agent $newShort
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $warns += $r.Warns
    $distInfo = $r
    if ($distInfo.RowCreated) {
        $r2 = Edit-SummaryModelsRow $t $distInfo.Shorts
        if ($r2.Error) { Block $r2.Error }
        $t = $r2.Text
    }
    $planLines += "PLAN:$(Get-RelPath $mcpPaths[$i]) distribution short=$newShort count=$($distInfo.NewCount) row_created=$($distInfo.RowCreated)"
    $r = Edit-FullTableAppend $t $fullTableRow
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $planLines += "PLAN:$(Get-RelPath $mcpPaths[$i]) full_table_row"
    $r = Edit-NumberedCounter $t '(?m)^### Agent Files \((\d+) total\)\r?$' @(1)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $r = Edit-NumberedCounter $t '(?m)^\*\*Subagents \((\d+)\):\*\*\r?$' @(1)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $r = Edit-AlphaInsert $t ($Agent + '.md')
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $r = Edit-NumberedCounter $t '(?m)^### Agent Files List \((\d+) files\)\r?$' @(1)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $r = Edit-TreeInsert $t ($Agent + '.md')
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $r = Edit-NumberedCounter $t '(?m)^\| Subagents \| (\d+) \| \S' @(1)
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $routingGroups = $(if ($Primary -eq 'orchestrator') { @(1) } else { @(2) })
    $r = Edit-NumberedCounter $t '(?m)^\| Routing tables \| 2 \| orchestrator \((\d+)\), plankestrator \((\d+)\) \|\r?$' $routingGroups
    if ($r.Error) { Block $r.Error }
    $t = $r.Text
    $pending[$mcpPaths[$i]] = @{ Text = $t; Bom = $mcpRaws[$i].Bom; Rel = (Get-RelPath $mcpPaths[$i]) }
    $planLines += "PLAN:$(Get-RelPath $mcpPaths[$i]) agent_files/list/tree/summary counters"
}

# ============================================================================
# Plan output
# ============================================================================
foreach ($pl in $planLines) { Write-Output $pl }
foreach ($w in ($warns | Select-Object -Unique)) { Write-Output $w }

if ($PlanOnly) {
    Write-Output 'STATUS:PLAN_ONLY'
    exit 0
}

# ============================================================================
# Apply (two-phase write)
# ============================================================================
Write-Output 'STATUS:APPLY_START'
Write-RawText -Path $liveAgentMd -Text $agentFileText -Bom $false
Write-Output "CREATED:$(Get-RelPath $liveAgentMd)"
Write-RawText -Path $deployAgentMd -Text $agentFileText -Bom $false
Write-Output "CREATED:$(Get-RelPath $deployAgentMd)"
foreach ($entry in $pending.GetEnumerator()) {
    Write-RawText -Path $entry.Key -Text $entry.Value.Text -Bom $entry.Value.Bom
    Write-Output "EDITED:$($entry.Value.Rel)"
}

# ============================================================================
# Verify (re-read from disk)
# ============================================================================
try { $null = ((Read-RawText $liveCfgPath).Text) | ConvertFrom-Json } catch {
    Write-Output "ERROR:live opencode.json no longer parses: $_"
    Write-Output 'WARN:partial state — restore from backup-snapshot / config-sync'
    exit 3
}
try { $null = ((Read-RawText $deployCfgPath).Text) | ConvertFrom-Json } catch {
    Write-Output "ERROR:deploy opencode.json no longer parses: $_"
    Write-Output 'WARN:partial state — restore from backup-snapshot / config-sync'
    exit 3
}
$verifyGroups = @(
    @{ Name = 'agent pair'; Paths = @($liveAgentMd, $deployAgentMd) },
    @{ Name = 'json pair'; Paths = @($liveCfgPath, $deployCfgPath) },
    @{ Name = 'plugin x3'; Paths = $pluginPaths },
    @{ Name = 'primary pair'; Paths = @($primaryLiveMd, $primaryDeployMd) },
    @{ Name = 'architecture x3'; Paths = $archPaths },
    @{ Name = 'agents-md x3'; Paths = $agentsMdPaths },
    @{ Name = 'mcp-setup x2'; Paths = $mcpPaths }
)
foreach ($g in $verifyGroups) {
    $hashes = @($g.Paths | ForEach-Object { Get-Sha256 $_ })
    if (@($hashes | Select-Object -Unique).Count -eq 1) {
        Write-Output "VERIFY:$($g.Name) identical"
    } else {
        Write-Output "ERROR:SHA256 mismatch: $($g.Name)"
        Write-Output 'WARN:partial state — restore from backup-snapshot / config-sync'
        exit 3
    }
}
# Counter re-parse: all whitelist sources == old+1, globals == old+1.
$cfg2 = ((Read-RawText $liveCfgPath).Text) | ConvertFrom-Json
$ta2 = Count-TaskAllow $cfg2 $Primary
if ($ta2 -ne ($wlN + 1)) { Write-Output "ERROR:post-apply counter check failed: json task allow = $ta2 expected $($wlN + 1)"; exit 3 }
$tsLive2 = (Read-RawText $pluginPaths[0]).Text
$plug2 = Count-RoutingPlugin $tsLive2 $Primary
if ($plug2 -ne ($wlN + 1)) { Write-Output "ERROR:post-apply counter check failed: plugin routing = $plug2 expected $($wlN + 1)"; exit 3 }
$pm2 = (Read-RawText $primaryLiveMd).Text
$rl2 = Count-RoutingLine $pm2
if ($rl2 -ne ($wlN + 1)) { Write-Output "ERROR:post-apply counter check failed: OPENCODE_ROUTING_TABLE = $rl2 expected $($wlN + 1)"; exit 3 }
$arch2 = (Read-RawText $archPaths[0]).Text
$wl2 = Get-WhitelistCount $arch2 $Primary
if ($null -eq $wl2 -or $wl2.Header -ne ($wlN + 1)) { Write-Output "ERROR:post-apply counter check failed: ARCH whitelist header"; exit 3 }
$mcp2 = (Read-RawText $mcpPaths[0]).Text
$ac2 = [regex]::Match($mcp2, '(?m)^\| Subagents \| (\d+) \|\r?$')
if (-not $ac2.Success -or [int]$ac2.Groups[1].Value -ne ($g1 + 1)) { Write-Output "ERROR:post-apply counter check failed: MCP Agent Count Subagents"; exit 3 }
$tu2 = [regex]::Match($mcp2, '(?m)^\| \*\*Total unique agents\*\* \| \*\*(\d+)\*\* \|\r?$')
if (-not $tu2.Success -or [int]$tu2.Groups[1].Value -ne ($g2 + 1)) { Write-Output "ERROR:post-apply counter check failed: MCP Total unique agents"; exit 3 }
Write-Output 'VERIFY:counters re-parsed old+1'
# Routing arrays contain the new name exactly once (token-exact).
foreach ($pp in $pluginPaths) {
    $ts3 = (Read-RawText $pp).Text
    $outer3 = [regex]::Match($ts3, '(?s)const ROUTING_TABLES = \{(.*?)\r?\n\}')
    $inner3 = [regex]::Match($outer3.Groups[1].Value, ('(?s)' + [regex]::Escape($Primary) + '\s*:\s*\[(.*?)\]'))
    $tokCount = @([regex]::Matches($inner3.Groups[1].Value, $script:TokenRx) | Where-Object { $_.Value.Trim('"', [char]0x27) -eq $Agent }).Count
    if ($tokCount -ne 1) { Write-Output "ERROR:post-apply routing token count != 1 in $pp"; exit 3 }
}
Write-Output 'VERIFY:routing token-exact once'

# ============================================================================
# Manual follow-ups (always)
# ============================================================================
Write-Output 'WARN:restart required (config is read at session start — the new agent is visible in a NEW opencode session)'
Write-Output 'WARN:CHANGELOG.md [Unreleased] entry is a manual step'
Write-Output 'WARN:consistency-checker.md counts (26/10/38 in the prompt) — manual edit live+deploy'
Write-Output 'WARN:verify.ps1 requiredAgents — manual update'
Write-Output 'WARN:deploy README.md/DEPLOYMENT_GUIDE.md counts — manual update'
Write-Output 'WARN:integrity-check defaults (38/26/10) in check.ps1+check.py+SKILL.md — manual update'
Write-Output 'WARN:live AGENTS.md — run config-sync -Apply -Group agents-md'
Write-Output 'WARN:SEVERITY_AGENTS/CONTEXT_FILE_AGENTS — manual update (only if the new agent is a reviewer)'
Write-Output 'WARN:MCP_SETUP unity-note prose — manual update (only if unity-mcp is not allowed for the new agent)'

# ============================================================================
# Optional conventional commit of the 16 repo files
# ============================================================================
if ($Commit) {
    $gitName = (Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "config", "user.name") | Select-Object -First 1)
    $gitEmail = (Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "config", "user.email") | Select-Object -First 1)
    if (-not $gitName -or -not $gitEmail) {
        Write-Output "ERROR: git identity missing (user.name='$gitName' user.email='$gitEmail') - set it with: git config user.name \"...\"; git config user.email \"...\""
        exit 3
    }
    $commitMsg = "feat(agents): add $Agent ($Model, $Primary whitelist)"
    $tempDir = Join-Path $env:TEMP 'opencode'
    if (-not (Test-Path -LiteralPath $tempDir)) { New-Item -ItemType Directory -Force -Path $tempDir | Out-Null }
    $commitMsgFile = Join-Path $tempDir 'commit-msg-agents.txt'
    [System.IO.File]::WriteAllText($commitMsgFile, $commitMsg, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output 'STATUS:COMMIT_START'
    $repoRelPaths = @(
        "deploy-package/agents/$Agent.md",
        'deploy-package/opencode.json',
        'plugins/workflow-enforcement.ts',
        'deploy-package/plugins/workflow-enforcement.ts',
        'ARCHITECTURE.md',
        'opencode-config/ARCHITECTURE.md',
        'deploy-package/project-files/ARCHITECTURE.md',
        'AGENTS.md',
        'opencode-config/AGENTS.md',
        'deploy-package/project-files/AGENTS.md',
        'PLUGIN.md',
        'opencode-config/PLUGIN.md',
        'deploy-package/project-files/PLUGIN.md',
        'MCP_SETUP.md',
        'deploy-package/project-files/MCP_SETUP.md',
        "deploy-package/agents/$Primary.md"
    )
    Invoke-Native -FilePath "git" -Arguments (@('-C', $repoRoot, 'add') + $repoRelPaths) | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Output 'ERROR:git add failed'; exit 3 }
    Invoke-Native -FilePath "git" -Arguments @('-C', $repoRoot, 'commit', '-F', $commitMsgFile) | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Output 'ERROR:git commit failed'; exit 3 }
    $commitHash = (Invoke-Native -FilePath "git" -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') | Select-Object -First 1)
    if ($commitHash) { $commitHash = $commitHash.Trim() }
    Write-Output "COMMITTED:hash=$commitHash msg=$commitMsg"
    if ($Push) {
        Write-Output 'STATUS:PUSH_START'
        $branch = ((Invoke-Native -FilePath "git" -Arguments @('-C', $repoRoot, 'branch', '--show-current')) | Select-Object -First 1)
        if ($branch) { $branch = $branch.Trim() }
        if (-not $branch) { Write-Output 'ERROR: could not determine current branch'; exit 3 }
        Invoke-Native -FilePath "git" -Arguments @('-C', $repoRoot, 'push', 'origin', $branch) | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Output 'ERROR:git push failed'; exit 3 }
        Write-Output "PUSHED:branch=$branch"
    }
}

Write-Output "STATUS:SUCCESS agent=$Agent primary=$Primary whitelist=$wlN->$($wlN + 1) total=$g2->$($g2 + 1)"
exit 0
