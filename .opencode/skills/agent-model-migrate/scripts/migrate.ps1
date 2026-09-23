<#
.SYNOPSIS
    Migrate ONE agent to a new model across all 7 synchronized places.

.DESCRIPTION
    Updates live+deploy frontmatter, ARCHITECTURE.md x3 (Subagent Models row +
    Model Roles agent move) and MCP_SETUP.md x2 (Models Distribution + Subagents
    Full Table Model cell + Summary Models row) in one all-or-nothing operation.
    Validates the model key against opencode.json provider models, SHA256-verifies
    all mirrors before and after, optional conventional commit + push.
    Two-phase write: any failed gate/anchor -> zero files written.

.PARAMETER Agent
    Agent name (file stem), e.g. utility.

.PARAMETER Model
    Full model key: provider/model-key, e.g. bifrost-litellm/MiniMax-M3
    (model-key itself may contain slashes).

.PARAMETER PlanOnly
    Dry-run: compute and print all edits, write nothing (default).

.PARAMETER Apply
    Apply the edits (mutually exclusive with -PlanOnly).

.PARAMETER Commit
    After apply: conventional commit of the 6 repo files (live files are outside git).

.PARAMETER Push
    After commit: push to origin (requires -Commit).

.PARAMETER Role
    Role row disambiguation (new model maps to >1 rows) or new role name
    (with -Tier when the new model has no role row).

.PARAMETER Tier
    Tier for a NEW role row: top|mid|low (only together with -Role).

.OUTPUTS
    STATUS:/PLAN:/WARN:/BLOCK:/EDITED:/VERIFY:/COMMITTED:/PUSHED:/ERROR: lines

.NOTES
    Exit codes: 0 success/plan-only/no changes, 2 usage/environment error,
    3 gate block (zero writes). Byte-safe: preserves BOM state and CRLF/LF.

.EXAMPLE
    .\migrate.ps1 -Agent utility -Model bifrost-litellm/qwen3.8-max -PlanOnly
    .\migrate.ps1 -Agent utility -Model bifrost-litellm/qwen3.8-max -Apply
    .\migrate.ps1 -Agent bugfix -Model bifrost-litellm/QWEN3.7-plus -Apply -Role review-lite
#>

param(
    [string]$Agent = '',
    [string]$Model = '',
    [switch]$PlanOnly,
    [switch]$Apply,
    [switch]$Commit,
    [switch]$Push,
    [string]$Role = '',
    [string]$Tier = ''
)

$ErrorActionPreference = 'Stop'
# git emits UTF-8; keep non-ASCII repo paths intact.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if (-not $Agent -or -not $Model) {
    Write-Output 'USAGE: migrate.ps1 -Agent <name> -Model <provider/model-key> [-PlanOnly | -Apply] [-Role <role>] [-Tier <top|mid|low>] [-Commit] [-Push]'
    Write-Output 'EXAMPLE: migrate.ps1 -Agent utility -Model bifrost-litellm/qwen3.8-max -PlanOnly'
    if (-not $Agent) { Write-Output 'ERROR:missing required parameter: -Agent' }
    if (-not $Model) { Write-Output 'ERROR:missing required parameter: -Model' }
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

function Write-RawText([string]$Path, [string]$Text, [bool]$Bom) {
    $enc = New-Object System.Text.UTF8Encoding($Bom)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# --- Model key helpers ----------------------------------------------------
function Split-ModelKey([string]$Full) {
    if (-not $Full) { return $null }
    $idx = $Full.IndexOf('/')
    if ($idx -lt 1 -or $idx -ge ($Full.Length - 1)) { return $null }
    return @{ Provider = $Full.Substring(0, $idx); Key = $Full.Substring($idx + 1) }
}

# --- Frontmatter helpers (first --- block only) ---------------------------
function Get-FmModel([string]$Text) {
    $m = [regex]::Match($Text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $m.Success) { return $null }
    $mm = [regex]::Match($m.Groups[1].Value, '(?m)^model:[ \t]*(.*)$')
    if (-not $mm.Success) { return $null }
    return $mm.Groups[1].Value.Trim()
}

function Set-FmModel([string]$Text, [string]$New) {
    $m = [regex]::Match($Text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $m.Success) { return $null }
    $block = $m.Groups[1].Value
    $rx = New-Object System.Text.RegularExpressions.Regex('(?m)^(model:.*?)(\r?)$')
    $eval = [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) 'model: ' + $New + $mm.Groups[2].Value }
    $block2 = $rx.Replace($block, $eval, 1)
    $idx = $m.Groups[1].Index
    return $Text.Substring(0, $idx) + $block2 + $Text.Substring($idx + $block.Length)
}

# --- Line-preserving table editing ----------------------------------------
# Split into [content, eol, content, eol, ...] keeping every EOL byte-exact.
function Split-LinesKeepEol([string]$Text) {
    return [regex]::Split($Text, '(\r\n|\r|\n)')
}

# Content lines live at EVEN indices of the split (odd = EOL separators).
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

function Split-Tokens([string]$Cell) {
    if (-not $Cell -or -not $Cell.Trim()) { return @() }
    return @($Cell -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-Eol($List, [int]$ContentIdx) {
    if ($ContentIdx + 1 -lt $List.Count) { return $List[$ContentIdx + 1] }
    return ''
}

# --- ARCHITECTURE.md: ## Subagent Models row -------------------------------
# Returns @{ Text; Old; Error; Warns } — Old = model found in the row.
function Edit-SubagentModelsRow([string]$Text, [string]$AgentName, [string]$NewModel) {
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $span = Find-SectionSpan $lines '^## Subagent Models' '^## '
    if (-not $span) { return @{ Text = $null; Old = $null; Error = 'anchor: ## Subagent Models section not found'; Warns = @() } }
    $pat = '^\| ' + [regex]::Escape($AgentName) + ' \| (.+?) \|$'
    $hits = @()
    for ($i = $span.Start; $i -lt $span.End; $i += 2) {
        $m = [regex]::Match($lines[$i], $pat)
        if ($m.Success) { $hits += @{ Idx = $i; Old = $m.Groups[1].Value.Trim() } }
    }
    if ($hits.Count -ne 1) { return @{ Text = $null; Old = $null; Error = "anchor: Subagent Models row for '$AgentName' found $($hits.Count) times (expected 1)"; Warns = @() } }
    $old = $hits[0].Old
    $warns = @()
    if ($old -ne $script:OldModel) { $warns += "WARN:subagent-models row drift (row=$old frontmatter=$($script:OldModel))" }
    $lines[$hits[0].Idx] = "| $AgentName | $NewModel |"
    return @{ Text = ($lines -join ''); Old = $old; Error = $null; Warns = $warns }
}

# --- ARCHITECTURE.md: Model Roles agent move -------------------------------
# Returns @{ Text; Error; Warns; OldRole; NewRole; TierMap }
function Edit-ModelRoles([string]$Text, [string]$AgentName, [string]$NewModel, [string]$Role, [string]$Tier) {
    $warns = @()
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    # End anchor: the "Kontrol summy:" line (Cyrillic) — unicode-escaped to keep this script ASCII.
    $span = Find-SectionSpan $lines '^## Model Roles' '^\u041A\u043E\u043D\u0442\u0440\u043E\u043B\u044C \u0441\u0443\u043C\u043C\u044B:'
    if (-not $span) { return @{ Text = $null; Error = 'anchor: ## Model Roles section not found'; Warns = $warns; OldRole = $null; NewRole = $null; TierMap = $null } }
    $rowPat = '^\| (.+?) \| (.+?) \| (.+?) \| (.*?) \|$'
    $rows = @()
    for ($i = $span.Start; $i -lt $span.End; $i += 2) {
        $m = [regex]::Match($lines[$i], $rowPat)
        if ($m.Success -and $m.Groups[1].Value.Trim() -ne 'Role') {
            $rows += @{ Idx = $i; Role = $m.Groups[1].Value.Trim(); Model = $m.Groups[2].Value.Trim(); Tier = $m.Groups[3].Value.Trim(); Agents = $m.Groups[4].Value.Trim() }
        }
    }
    if ($rows.Count -eq 0) { return @{ Text = $null; Error = 'anchor: Model Roles data rows not found'; Warns = $warns; OldRole = $null; NewRole = $null; TierMap = $null } }

    # REMOVE the agent from its current row (token-exact match).
    $hit = @($rows | Where-Object { (Split-Tokens $_.Agents) -contains $AgentName })
    if ($hit.Count -eq 0) { return @{ Text = $null; Error = "agent '$AgentName' not found in any Model Roles row"; Warns = $warns; OldRole = $null; NewRole = $null; TierMap = $null } }
    if ($hit.Count -gt 1) { return @{ Text = $null; Error = "agent '$AgentName' duplicated across $($hit.Count) Model Roles rows"; Warns = $warns; OldRole = $null; NewRole = $null; TierMap = $null } }
    $oldRow = $hit[0]
    $oldRole = $oldRow.Role
    $rest = @(Split-Tokens $oldRow.Agents | Where-Object { $_ -ne $AgentName })
    $agentsCell = $rest -join ', '
    if ($rest.Count -eq 0) { $warns += "WARN:role '$oldRole' now has 0 agents" }
    $lines[$oldRow.Idx] = "| $($oldRow.Role) | $($oldRow.Model) | $($oldRow.Tier) | $agentsCell |"

    # ADD the agent to the row with the new model (or create a new row).
    $cands = @($rows | Where-Object { $_.Model -eq $NewModel })
    $newRole = $null
    if ($cands.Count -eq 1) {
        if ($Role -and $Role -ne $cands[0].Role) {
            return @{ Text = $null; Error = "-Role '$Role' does not match the single role row '$($cands[0].Role)'"; Warns = $warns; OldRole = $oldRole; NewRole = $null; TierMap = $null }
        }
        $newRole = $cands[0]
        $toks = @(Split-Tokens $newRole.Agents)
        if ($toks -notcontains $AgentName) { $toks += $AgentName }
        $lines[$newRole.Idx] = "| $($newRole.Role) | $($newRole.Model) | $($newRole.Tier) | $($toks -join ', ') |"
        $newRoleName = $newRole.Role
    } elseif ($cands.Count -gt 1) {
        if (-not $Role) {
            return @{ Text = $null; Error = 'ambiguous role rows: ' + (($cands | ForEach-Object { $_.Role }) -join ', '); Warns = $warns; OldRole = $oldRole; NewRole = $null; TierMap = $null }
        }
        $m2 = @($cands | Where-Object { $_.Role -eq $Role })
        if ($m2.Count -ne 1) {
            return @{ Text = $null; Error = "-Role '$Role' not found among candidate rows: " + (($cands | ForEach-Object { $_.Role }) -join ', '); Warns = $warns; OldRole = $oldRole; NewRole = $null; TierMap = $null }
        }
        $newRole = $m2[0]
        $toks = @(Split-Tokens $newRole.Agents)
        if ($toks -notcontains $AgentName) { $toks += $AgentName }
        $lines[$newRole.Idx] = "| $($newRole.Role) | $($newRole.Model) | $($newRole.Tier) | $($toks -join ', ') |"
        $newRoleName = $newRole.Role
    } else {
        if (-not $Role -or -not $Tier) {
            return @{ Text = $null; Error = 'model has no role row; -Role and -Tier required. Available roles: ' + (($rows | ForEach-Object { $_.Role }) -join ', '); Warns = $warns; OldRole = $oldRole; NewRole = $null; TierMap = $null }
        }
        $warns += "WARN:new role '$Role' requires CHANGELOG justification"
        $last = $rows[$rows.Count - 1]
        $eol = Get-Eol $lines $last.Idx
        if (-not $eol) { $eol = "`r`n" }
        $insertAt = $last.Idx + 2
        $lines.Insert($insertAt, "| $Role | $NewModel | $Tier | $AgentName |")
        $lines.Insert($insertAt + 1, $eol)
        $newRoleName = $Role
    }

    # Rebuild the agent->tier map from the edited section (for prewalk warnings).
    # Bound +2: an inserted row shifts the section end down — extra lines never match rowPat.
    $tierMap = @{}
    $bound = [Math]::Min($span.End + 2, $lines.Count)
    for ($i = $span.Start; $i -lt $bound; $i += 2) {
        $m = [regex]::Match($lines[$i], $rowPat)
        if ($m.Success -and $m.Groups[1].Value.Trim() -ne 'Role') {
            foreach ($t in (Split-Tokens $m.Groups[4].Value)) { $tierMap[$t] = $m.Groups[3].Value.Trim() }
        }
    }
    return @{ Text = ($lines -join ''); Error = $null; Warns = $warns; OldRole = $oldRole; NewRole = $newRoleName; TierMap = $tierMap }
}

# --- MCP_SETUP.md: Models Distribution --------------------------------------
# Returns @{ Text; Error; Warns; Shorts; OldCount; NewCount; OldShort; NewShort; RowDeleted }
function Edit-Distribution([string]$Text, [string]$AgentName, [string]$OldShort, [string]$NewShort) {
    $warns = @()
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $span = Find-SectionSpan $lines '^### Models Distribution' '^### '
    if (-not $span) { return @{ Text = $null; Error = 'anchor: ### Models Distribution section not found'; Warns = $warns } }
    $rowPat = '^\| `(.+?)` \| (.+?) \| (\d+) \| (.*?) \|$'
    $rows = @()
    for ($i = $span.Start; $i -lt $span.End; $i += 2) {
        $m = [regex]::Match($lines[$i], $rowPat)
        if ($m.Success -and $m.Groups[1].Value.Trim() -ne 'Model') {
            $rows += @{ Idx = $i; Short = $m.Groups[1].Value.Trim(); Provider = $m.Groups[2].Value.Trim(); Count = [int]$m.Groups[3].Value; Agents = $m.Groups[4].Value.Trim() }
        }
    }
    if ($rows.Count -eq 0) { return @{ Text = $null; Error = 'anchor: Models Distribution data rows not found'; Warns = $warns } }

    # OLD row: remove the agent token; count -> new token count; 0 -> row deleted.
    $oldRows = @($rows | Where-Object { $_.Short -eq $OldShort })
    if ($oldRows.Count -ne 1) { return @{ Text = $null; Error = "anchor: Distribution row for '$OldShort' found $($oldRows.Count) times (expected 1)"; Warns = $warns } }
    $oldRow = $oldRows[0]
    $oldToks = @(Split-Tokens $oldRow.Agents)
    if ($oldToks -notcontains $AgentName) { $warns += "WARN:distribution drift (agent '$AgentName' not in row '$OldShort')" }
    $rest = @($oldToks | Where-Object { $_ -ne $AgentName })
    $rowDeleted = $false
    if ($rest.Count -eq 0) {
        # delete the whole line (content + EOL element)
        if ($oldRow.Idx + 1 -lt $lines.Count) { $lines.RemoveAt($oldRow.Idx + 1) }
        $lines.RemoveAt($oldRow.Idx)
        $rowDeleted = $true
        # indices above shifted by 2 — re-parse (bound +2: harmless, header lines never match)
        $rows = @()
        $bound = [Math]::Min($span.End + 2, $lines.Count)
        for ($i = $span.Start; $i -lt $bound; $i += 2) {
            $m = [regex]::Match($lines[$i], $rowPat)
            if ($m.Success -and $m.Groups[1].Value.Trim() -ne 'Model') {
                $rows += @{ Idx = $i; Short = $m.Groups[1].Value.Trim(); Provider = $m.Groups[2].Value.Trim(); Count = [int]$m.Groups[3].Value; Agents = $m.Groups[4].Value.Trim() }
            }
        }
    } else {
        $lines[$oldRow.Idx] = "| ``$($oldRow.Short)`` | $($oldRow.Provider) | $($rest.Count) | $($rest -join ', ') |"
    }
    $oldCountAfter = $rest.Count
    if ($rows.Count -eq 0) { return @{ Text = $null; Error = 'anchor: Models Distribution has no remaining rows after edit'; Warns = $warns } }

    # NEW row: append token / create the row.
    $newRows = @($rows | Where-Object { $_.Short -eq $NewShort })
    if ($newRows.Count -eq 1) {
        $nr = $newRows[0]
        $toks = @(Split-Tokens $nr.Agents)
        if ($toks -notcontains $AgentName) { $toks += $AgentName }
        $lines[$nr.Idx] = "| ``$($nr.Short)`` | $($nr.Provider) | $($toks.Count) | $($toks -join ', ') |"
        $newCountAfter = $toks.Count
    } elseif ($newRows.Count -eq 0) {
        $last = $rows[$rows.Count - 1]
        $eol = Get-Eol $lines $last.Idx
        if (-not $eol) { $eol = "`r`n" }
        $insertAt = $last.Idx + 2
        $lines.Insert($insertAt, "| ``$NewShort`` | bifrost-litellm | 1 | $AgentName |")
        $lines.Insert($insertAt + 1, $eol)
        $newCountAfter = 1
    } else {
        return @{ Text = $null; Error = "anchor: Distribution row for '$NewShort' found $($newRows.Count) times (expected 1)"; Warns = $warns }
    }

    # Final ordered short list (from the edited lines; bound +2 covers an inserted row).
    $shorts = @()
    $bound = [Math]::Min($span.End + 2, $lines.Count)
    for ($i = $span.Start; $i -lt $bound; $i += 2) {
        $m = [regex]::Match($lines[$i], $rowPat)
        if ($m.Success -and $m.Groups[1].Value.Trim() -ne 'Model') { $shorts += $m.Groups[1].Value.Trim() }
    }
    return @{ Text = ($lines -join ''); Error = $null; Warns = $warns; Shorts = $shorts; OldCount = $oldCountAfter; NewCount = $newCountAfter; RowDeleted = $rowDeleted }
}

# --- MCP_SETUP.md: Subagents Full Table Model cell ---------------------------
function Edit-FullTableRow([string]$Text, [string]$AgentName, [string]$OldModel, [string]$NewModel) {
    $warns = @()
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $pat = '^\| \*\*' + [regex]::Escape($AgentName) + '\*\* \|'
    $hits = @()
    for ($i = 0; $i -lt $lines.Count; $i += 2) {
        if ($lines[$i] -match $pat) { $hits += $i }
    }
    if ($hits.Count -ne 1) { return @{ Text = $null; Error = "anchor: Full Table row for '$AgentName' found $($hits.Count) times (expected 1)"; Warns = $warns } }
    $idx = $hits[0]
    $content = $lines[$idx]
    $cells = $content -split '\|'
    if ($cells.Count -lt 5) { return @{ Text = $null; Error = "anchor: Full Table row for '$AgentName' has too few cells"; Warns = $warns } }
    $cur = $cells[3].Trim()
    if ($cur -ne $OldModel) { $warns += "WARN:full-table model drift (cell=$cur expected=$OldModel)" }
    $cells[3] = " $NewModel "
    $lines[$idx] = ($cells -join '|')
    return @{ Text = ($lines -join ''); Error = $null; Warns = $warns }
}

# --- MCP_SETUP.md: Summary Models row ----------------------------------------
function Edit-SummaryModelsRow([string]$Text, [string[]]$Shorts) {
    $lines = [System.Collections.Generic.List[string]](Split-LinesKeepEol $Text)
    $pat = '^\| Models \| \d+ \| bifrost-litellm \(.*\) \|$'
    $hits = @()
    for ($i = 0; $i -lt $lines.Count; $i += 2) {
        if ($lines[$i] -match $pat) { $hits += $i }
    }
    if ($hits.Count -ne 1) { return @{ Text = $null; Error = "anchor: Summary Models row found $($hits.Count) times (expected 1)" } }
    $idx = $hits[0]
    $newLine = "| Models | $($Shorts.Count) | bifrost-litellm ($($Shorts -join ', ')) |"
    $lines[$idx] = $newLine
    return @{ Text = ($lines -join ''); Error = $null }
}

# ============================================================================
# Main flow
# ============================================================================

# 1. Flag validation
if ($PlanOnly -and $Apply) {
    Write-Output 'ERROR:-PlanOnly and -Apply are mutually exclusive'
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
if (-not $PlanOnly -and -not $Apply) { $PlanOnly = $true }
if ($Push -and -not $Commit) {
    Write-Output 'ERROR:-Push requires -Commit'
    exit 2
}

# 2. Paths
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy-package"))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}
$liveDir = Join-Path $env:USERPROFILE '.config\opencode'
$liveFm = Join-Path $liveDir "agents\$Agent.md"
$deployFm = Join-Path $repoRoot "deploy-package\agents\$Agent.md"
$archPaths = @(
    (Join-Path $repoRoot 'ARCHITECTURE.md'),
    (Join-Path $repoRoot 'opencode-config\ARCHITECTURE.md'),
    (Join-Path $repoRoot 'deploy-package\project-files\ARCHITECTURE.md')
)
$mcpPaths = @(
    (Join-Path $repoRoot 'MCP_SETUP.md'),
    (Join-Path $repoRoot 'deploy-package\project-files\MCP_SETUP.md')
)
$allTargets = @($liveFm, $deployFm) + $archPaths + $mcpPaths
foreach ($t in $allTargets) {
    if (-not (Test-Path -LiteralPath $t -PathType Leaf)) {
        Write-Output "ERROR:agent target file not found: $t"
        exit 2
    }
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

# 3. Primary agents are manual doc operations
if ($Agent -in @('orchestrator', 'plankestrator')) {
    Write-Output 'BLOCK:primary agent migration is manual (orchestrator/plankestrator — see ARCHITECTURE Model Roles / Identity Lock)'
    exit 3
}

# 4. Model key format
$keyParts = Split-ModelKey $Model
if (-not $keyParts) {
    Write-Output "ERROR:model key must be provider/model-key (got '$Model')"
    exit 2
}
$Provider = $keyParts.Provider
$Key = $keyParts.Key
if ($Provider -ne 'bifrost-litellm') {
    Write-Output "BLOCK:provider '$Provider' is not bifrost-litellm"
    exit 3
}

# 5. Validate the key against live opencode.json provider models
$liveCfgPath = Join-Path $liveDir 'opencode.json'
if (-not (Test-Path -LiteralPath $liveCfgPath -PathType Leaf)) {
    Write-Output "ERROR:live opencode.json not found: $liveCfgPath"
    exit 2
}
try {
    $cfg = ((Read-RawText $liveCfgPath).Text) | ConvertFrom-Json
} catch {
    Write-Output "BLOCK:live opencode.json is not valid JSON: $_"
    exit 3
}
$provProp = $cfg.provider.PSObject.Properties[$Provider]
$modelExists = $false
if ($provProp -and $provProp.Value.models) {
    $modelExists = @($provProp.Value.models.PSObject.Properties.Name) -contains $Key
}
if (-not $modelExists) {
    Write-Output "BLOCK:model not found in provider models: $Model"
    exit 3
}

# 6. Read all 7 files; OLD model from live frontmatter
$liveFmRaw = Read-RawText $liveFm
$deployFmRaw = Read-RawText $deployFm
$archRaws = @($archPaths | ForEach-Object { Read-RawText $_ })
$mcpRaws = @($mcpPaths | ForEach-Object { Read-RawText $_ })
$oldModel = Get-FmModel $liveFmRaw.Text
if (-not $oldModel) {
    Write-Output 'BLOCK:frontmatter without model: line'
    exit 3
}
if ($oldModel -eq $Model) {
    Write-Output 'STATUS:NO_CHANGES'
    exit 0
}
$script:OldModel = $oldModel
$oldParts = Split-ModelKey $oldModel
if (-not $oldParts) {
    Write-Output "BLOCK:existing frontmatter model key malformed: '$oldModel'"
    exit 3
}
$oldShort = $oldParts.Key
$newShort = $Key

Write-Output "STATUS:MIGRATE_START agent=$Agent old=$oldModel new=$Model"

# 7. Pre-gate: target FM pair + ARCHITECTURE x3 + MCP_SETUP x2 must be in sync
$drifts = @()
if ((Get-Sha256 $liveFm) -ne (Get-Sha256 $deployFm)) { $drifts += 'frontmatter pair (live vs deploy)' }
$archHashes = @($archPaths | ForEach-Object { Get-Sha256 $_ })
if (@($archHashes | Select-Object -Unique).Count -gt 1) { $drifts += 'ARCHITECTURE.md x3' }
$mcpHashes = @($mcpPaths | ForEach-Object { Get-Sha256 $_ })
if (@($mcpHashes | Select-Object -Unique).Count -gt 1) { $drifts += 'MCP_SETUP.md x2' }
if ($drifts.Count -gt 0) {
    if ($Apply) {
        Write-Output "BLOCK:mirrors drifted — run config-sync first ($($drifts -join '; '))"
        exit 3
    } else {
        foreach ($d in $drifts) { Write-Output "WARN:mirror drift ($d) — run config-sync before apply" }
    }
}

# 8. Compute ALL edits in memory (two-phase: zero writes on any error)
$pending = [ordered]@{}
$warns = @()
$planLines = @()

# 8a. Frontmatter (live + deploy)
$newLiveFm = Set-FmModel $liveFmRaw.Text $Model
if (-not $newLiveFm) { Write-Output 'BLOCK:anchor: frontmatter model: line not found (live)'; exit 3 }
$pending[$liveFm] = @{ Text = $newLiveFm; Bom = $liveFmRaw.Bom; Rel = (Get-RelPath $liveFm) }
$planLines += "PLAN:$(Get-RelPath $liveFm) old=$oldModel new=$Model"
$newDeployFm = Set-FmModel $deployFmRaw.Text $Model
if (-not $newDeployFm) { Write-Output 'BLOCK:anchor: frontmatter model: line not found (deploy)'; exit 3 }
$pending[$deployFm] = @{ Text = $newDeployFm; Bom = $deployFmRaw.Bom; Rel = (Get-RelPath $deployFm) }
$planLines += "PLAN:$(Get-RelPath $deployFm) old=$oldModel new=$Model"

# 8b. ARCHITECTURE.md x3
$archEditInfo = $null
for ($i = 0; $i -lt $archPaths.Count; $i++) {
    $text = $archRaws[$i].Text
    $r1 = Edit-SubagentModelsRow $text $Agent $Model
    if ($r1.Error) { Write-Output "BLOCK:$($r1.Error)"; exit 3 }
    $warns += $r1.Warns
    $r2 = Edit-ModelRoles $r1.Text $Agent $Model $Role $Tier
    if ($r2.Error) { Write-Output "BLOCK:$($r2.Error)"; exit 3 }
    $warns += $r2.Warns
    $pending[$archPaths[$i]] = @{ Text = $r2.Text; Bom = $archRaws[$i].Bom; Rel = (Get-RelPath $archPaths[$i]) }
    $planLines += "PLAN:$(Get-RelPath $archPaths[$i]) subagent_models_row old=$($r1.Old) new=$Model"
    $archEditInfo = $r2
}
if ($archEditInfo) {
    $planLines += "PLAN:role $Agent $($archEditInfo.OldRole) -> $($archEditInfo.NewRole)"
}

# 8c. MCP_SETUP.md x2
$distInfo = $null
for ($i = 0; $i -lt $mcpPaths.Count; $i++) {
    $text = $mcpRaws[$i].Text
    $r1 = Edit-Distribution $text $Agent $oldShort $newShort
    if ($r1.Error) { Write-Output "BLOCK:$($r1.Error)"; exit 3 }
    $warns += $r1.Warns
    $r2 = Edit-FullTableRow $r1.Text $Agent $oldModel $Model
    if ($r2.Error) { Write-Output "BLOCK:$($r2.Error)"; exit 3 }
    $warns += $r2.Warns
    $r3 = Edit-SummaryModelsRow $r2.Text $r1.Shorts
    if ($r3.Error) { Write-Output "BLOCK:$($r3.Error)"; exit 3 }
    $pending[$mcpPaths[$i]] = @{ Text = $r3.Text; Bom = $mcpRaws[$i].Bom; Rel = (Get-RelPath $mcpPaths[$i]) }
    $planLines += "PLAN:$(Get-RelPath $mcpPaths[$i]) distribution/full_table/summary"
    $distInfo = $r1
}
if ($distInfo) {
    $detail = "PLAN:distribution $oldShort count->$($distInfo.OldCount); $newShort count->$($distInfo.NewCount)"
    if ($distInfo.RowDeleted) { $detail += " (row '$oldShort' deleted)" }
    $planLines += $detail
}

# 8d. Prewalk tier-inversion warnings (from the NEW Model Roles state)
if ($archEditInfo -and $archEditInfo.TierMap) {
    $rank = @{ top = 3; mid = 2; low = 1 }
    foreach ($pair in @(@('plan-bug', 'execute-bug'), @('dev-planner', 'dev-professor'), @('docs-planner', 'docs-writer'))) {
        $p = $pair[0]; $e = $pair[1]
        if ($archEditInfo.TierMap.ContainsKey($p) -and $archEditInfo.TierMap.ContainsKey($e)) {
            if ($rank[$archEditInfo.TierMap[$p]] -lt $rank[$archEditInfo.TierMap[$e]]) {
                $warns += "WARN:prewalk inversion ($p tier=$($archEditInfo.TierMap[$p]) < $e tier=$($archEditInfo.TierMap[$e]))"
            }
        }
    }
}

# 9. Print the plan
foreach ($pl in $planLines) { Write-Output $pl }
foreach ($w in $warns) { Write-Output $w }

# 10. PlanOnly stop
if ($PlanOnly) {
    Write-Output 'STATUS:PLAN_ONLY'
    exit 0
}

# 11. Apply: two-phase write
Write-Output 'STATUS:APPLY_START'
foreach ($entry in $pending.GetEnumerator()) {
    Write-RawText -Path $entry.Key -Text $entry.Value.Text -Bom $entry.Value.Bom
    Write-Output "EDITED:$($entry.Value.Rel)"
}

# 12. Verify (re-read from disk)
try { $null = ((Read-RawText $liveCfgPath).Text) | ConvertFrom-Json } catch {
    Write-Output "ERROR:opencode.json no longer parses: $_"
    exit 3
}
$fmOk = ((Get-Sha256 $liveFm) -eq (Get-Sha256 $deployFm))
if ($fmOk) { Write-Output 'VERIFY:frontmatter identical' } else { Write-Output 'ERROR:SHA256 mismatch: frontmatter pair'; exit 3 }
$archHashes2 = @($archPaths | ForEach-Object { Get-Sha256 $_ })
if (@($archHashes2 | Select-Object -Unique).Count -eq 1) { Write-Output 'VERIFY:architecture identical' } else { Write-Output 'ERROR:SHA256 mismatch: ARCHITECTURE.md x3'; exit 3 }
$mcpHashes2 = @($mcpPaths | ForEach-Object { Get-Sha256 $_ })
if (@($mcpHashes2 | Select-Object -Unique).Count -eq 1) { Write-Output 'VERIFY:mcp-setup identical' } else { Write-Output 'ERROR:SHA256 mismatch: MCP_SETUP.md x2'; exit 3 }

# 13. Manual follow-ups
Write-Output 'WARN:restart required (config is read at session start — new model takes effect in a NEW opencode session)'
Write-Output 'WARN:CHANGELOG.md [Unreleased] entry is a manual step'

# 14. Optional conventional commit of the 6 repo files
if ($Commit) {
    $gitName = (Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "config", "user.name") | Select-Object -First 1)
    $gitEmail = (Invoke-Native -FilePath "git" -Arguments @("-C", $repoRoot, "config", "user.email") | Select-Object -First 1)
    if (-not $gitName -or -not $gitEmail) {
        Write-Output "ERROR: git identity missing (user.name='$gitName' user.email='$gitEmail') - set it with: git config user.name \"...\"; git config user.email \"...\""
        exit 3
    }
    $commitMsg = "refactor(models): $Agent $oldModel -> $Model"
    $tempDir = Join-Path $env:TEMP 'opencode'
    if (-not (Test-Path -LiteralPath $tempDir)) { New-Item -ItemType Directory -Force -Path $tempDir | Out-Null }
    $commitMsgFile = Join-Path $tempDir 'commit-msg-models.txt'
    [System.IO.File]::WriteAllText($commitMsgFile, $commitMsg, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output 'STATUS:COMMIT_START'
    $repoRelPaths = @(
        "deploy-package/agents/$Agent.md",
        'ARCHITECTURE.md',
        'opencode-config/ARCHITECTURE.md',
        'deploy-package/project-files/ARCHITECTURE.md',
        'MCP_SETUP.md',
        'deploy-package/project-files/MCP_SETUP.md'
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

# 15. Done
Write-Output 'STATUS:SUCCESS'
exit 0
