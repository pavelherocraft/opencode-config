<#
.SYNOPSIS
    Fast LLM-free validation of every frontmatter model key.

.DESCRIPTION
    Validates the model: key of every agent .md frontmatter against the
    opencode.json provider catalog: format provider/model-key (split on FIRST
    slash), existence in provider models, Did-you-mean suggestions via
    Levenshtein for every invalid key, unused-model report (catalog keys
    referenced by zero agents). -Both additionally validates the deploy
    mirror + live<->deploy SHA256 PAIRs. STRICTLY READ-ONLY.

.PARAMETER Agents
    Agents dir to validate. Default %USERPROFILE%\.config\opencode\agents

.PARAMETER Both
    Also validate deploy-package/agents + PAIR hashes.

.PARAMETER Config
    Path to opencode.json. Default %USERPROFILE%\.config\opencode\opencode.json

.PARAMETER Provider
    Validate only keys of this provider (others -> SKIP, not FAIL).

.PARAMETER Suggest
    Max suggestions per invalid key (default 3, min 1).

.PARAMETER Json
    JSON report instead of token lines.

.OUTPUTS
    STATUS:/KEY:/SUGGEST:/SKIP:/UNUSED:/PAIR:/SUMMARY:/ERROR: lines

.NOTES
    Exit codes: 0 all keys valid (UNUSED/SKIP allowed), 2 usage/environment
    error, 3 one or more invalid keys / PAIR drift / opencode.json unparsable.

.EXAMPLE
    .\validate.ps1
    .\validate.ps1 -Both
    .\validate.ps1 -Provider bifrost-litellm -Suggest 5
#>

param(
    [string]$Agents = '',
    [switch]$Both,
    [string]$Config = '',
    [string]$Provider = '',
    [int]$Suggest = 3,
    [switch]$Json
)

if (-not $Agents) { $Agents = Join-Path $env:USERPROFILE '.config\opencode\agents' }
if (-not $Config) { $Config = Join-Path $env:USERPROFILE '.config\opencode\opencode.json' }
if ($Suggest -lt 1) { Write-Output 'ERROR:-Suggest must be >= 1'; exit 2 }

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

# --- Levenshtein (single-row DP) ------------------------------------------
function Get-Levenshtein([string]$A, [string]$B) {
    $la = $A.Length; $lb = $B.Length
    if ($la -eq 0) { return $lb }
    if ($lb -eq 0) { return $la }
    $prev = 0..$lb
    $curr = New-Object int[] ($lb + 1)
    for ($i = 1; $i -le $la; $i++) {
        $curr[0] = $i
        for ($j = 1; $j -le $lb; $j++) {
            $cost = if ($A[$i-1] -eq $B[$j-1]) { 0 } else { 1 }
            $curr[$j] = [Math]::Min([Math]::Min($curr[$j-1] + 1, $prev[$j] + 1), $prev[$j-1] + $cost)
        }
        $t = $prev; $prev = $curr; $curr = $t
    }
    return $prev[$lb]
}

# --- Did-you-mean suggestions ----------------------------------------------
function Get-Suggestions([string]$BadKey, [string[]]$Catalog, [string[]]$Providers, [int]$N) {
    $slash = $BadKey.IndexOf('/')
    if ($slash -ge 0) {
        $provPart = $BadKey.Substring(0, $slash)
    } else {
        $provPart = $BadKey
    }
    $provLower = $provPart.ToLowerInvariant()
    $knownProviders = @($Providers | ForEach-Object { $_.ToLowerInvariant() })
    $results = @()
    if ($knownProviders -notcontains $provLower) {
        # Unknown provider: score catalog keys by provider-segment distance.
        foreach ($cand in $Catalog) {
            $cSlash = $cand.IndexOf('/')
            $catProv = if ($cSlash -ge 0) { $cand.Substring(0, $cSlash) } else { $cand }
            $dist = Get-Levenshtein $provLower $catProv.ToLowerInvariant()
            $results += @{ Dist = $dist; Cand = $cand }
        }
        $results = @($results | Sort-Object { $_.Dist }, { $_.Cand } | Select-Object -First $N | ForEach-Object { $_.Cand })
        return $results
    }
    # Known provider: score FULL keys, case-insensitive, with prefix bonus.
    $badLower = $BadKey.ToLowerInvariant()
    $threshold = [Math]::Max(3, [Math]::Floor($BadKey.Length / 3))
    $scored = @()
    foreach ($cand in $Catalog) {
        $candLower = $cand.ToLowerInvariant()
        $dist = Get-Levenshtein $badLower $candLower
        if ($candLower.StartsWith($badLower) -or $badLower.StartsWith($candLower)) {
            $dist = [Math]::Max(0, $dist - 2)
        }
        if ($dist -le $threshold) { $scored += @{ Dist = $dist; Cand = $cand } }
    }
    # Script-block sort keys: Sort-Object cannot sort hashtables by -Property.
    $results = @($scored | Sort-Object { $_.Dist }, { $_.Cand } | Select-Object -First $N | ForEach-Object { $_.Cand })
    return $results
}

# --- Paths ----------------------------------------------------------------
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy-package"))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}

# --- Environment ------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Agents -PathType Container)) {
    Write-Output "ERROR:agents dir not found: $Agents"
    exit 2
}
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
    Write-Output "ERROR:opencode.json not found: $Config"
    exit 2
}

# --- Catalog -----------------------------------------------------------------
try {
    $cfg = (Read-RawText $Config).Text | ConvertFrom-Json
} catch {
    Write-Output "ERROR:opencode.json invalid JSON: $_"
    exit 3
}
$catalog = @()
$providers = @()
if ($cfg.provider) {
    foreach ($p in $cfg.provider.PSObject.Properties) {
        $providers += $p.Name
        if ($p.Value.models) {
            foreach ($mName in $p.Value.models.PSObject.Properties.Name) {
                $catalog += "$($p.Name)/$mName"
            }
        }
    }
}
if (-not $Json) {
    Write-Output "STATUS:VALIDATE_START agents_dir=$Agents catalog=$($providers.Count)/$($catalog.Count)"
}

$keysReport = @()
$unusedReport = @()
$pairsReport = @()
$valid = 0; $invalid = 0; $suggestions = 0
$used = @{}

function Test-AgentFile([string]$Path) {
    # Returns @{ Status = PASS|FAIL|SKIP; Reason; Model; Suggestions }
    $text = (Read-RawText $Path).Text
    $m = Get-FmModel $text
    if (-not $m) {
        return @{ Status = 'FAIL'; Reason = 'frontmatter without model line'; Model = '<missing>'; Suggestions = @() }
    }
    if ($Provider -and $m.IndexOf('/') -ge 0 -and $m.Substring(0, $m.IndexOf('/')) -ne $Provider) {
        return @{ Status = 'SKIP'; Reason = 'provider filter'; Model = $m; Suggestions = @() }
    }
    if ($Provider -and $m.IndexOf('/') -lt 0) {
        return @{ Status = 'SKIP'; Reason = 'provider filter'; Model = $m; Suggestions = @() }
    }
    $fmtOk = $m -match '^[A-Za-z0-9._-]+/.+$'
    if (-not $fmtOk) {
        $sug = @(Get-Suggestions -BadKey $m -Catalog $catalog -Providers $providers -N $Suggest)
        return @{ Status = 'FAIL'; Reason = 'malformed'; Model = $m; Suggestions = $sug }
    }
    $slash = $m.IndexOf('/')
    $prov = $m.Substring(0, $slash)
    $key = $m.Substring($slash + 1)
    $exists = $false
    $provProp = $cfg.provider.PSObject.Properties[$prov]
    if ($provProp -and $provProp.Value.models) {
        # -ccontains: case-SENSITIVE — Python dict lookup parity (keys differ by case in the catalog).
        $exists = @($provProp.Value.models.PSObject.Properties.Name) -ccontains $key
    }
    if ($exists) {
        return @{ Status = 'PASS'; Reason = ''; Model = $m; Suggestions = @() }
    }
    $sug = @(Get-Suggestions -BadKey $m -Catalog $catalog -Providers $providers -N $Suggest)
    return @{ Status = 'FAIL'; Reason = 'not found'; Model = $m; Suggestions = $sug }
}

# --- Live agents ---------------------------------------------------------------
$liveFiles = @(Get-ChildItem -LiteralPath $Agents -Filter '*.md' -File | Sort-Object Name)
foreach ($f in $liveFiles) {
    $r = Test-AgentFile -Path $f.FullName
    if ($r.Status -eq 'PASS') {
        $valid++
        $used[$r.Model] = $true
    } elseif ($r.Status -eq 'FAIL') {
        $invalid++
        if ($r.Suggestions.Count -gt 0) { $suggestions++ }
    } elseif ($r.Status -eq 'SKIP') {
        $used[$r.Model] = $true
    }
    $keysReport += @{ agent = $f.BaseName; model = $r.Model; status = $r.Status; reason = $r.Reason; suggestions = $r.Suggestions }
    if (-not $Json) {
        if ($r.Status -eq 'SKIP') {
            Write-Output "SKIP:$($f.BaseName) $($r.Model) ($($r.Reason))"
        } else {
            $reasonPart = if ($r.Reason) { " ($($r.Reason))" } else { '' }
            $modelPart = if ($r.Status -eq 'FAIL' -and $r.Reason -eq 'frontmatter without model line') { "model=<missing>" } else { $r.Model }
            Write-Output "KEY:$($f.BaseName) $modelPart -> $($r.Status)$reasonPart"
        }
        if ($r.Suggestions.Count -gt 0) {
            Write-Output "SUGGEST:$($f.BaseName) did_you_mean=$($r.Suggestions -join ', ')"
        }
    }
}

# --- Deploy mirrors (-Both) ------------------------------------------------------
if ($Both) {
    $deployDir = Join-Path $repoRoot 'deploy-package\agents'
    if (-not (Test-Path -LiteralPath $deployDir -PathType Container)) {
        Write-Output "ERROR:deploy agents dir not found: $deployDir"
        exit 2
    }
    $deployFiles = @(Get-ChildItem -LiteralPath $deployDir -Filter '*.md' -File | Sort-Object Name)
    $liveNames = @($liveFiles | ForEach-Object { $_.BaseName })
    $deployNames = @($deployFiles | ForEach-Object { $_.BaseName })
    $union = @($liveNames + $deployNames | Select-Object -Unique)
    foreach ($n in $union) {
        $dp = Join-Path $deployDir "$n.md"
        if (Test-Path -LiteralPath $dp -PathType Leaf) {
            $r = Test-AgentFile -Path $dp
            if ($r.Status -eq 'PASS') { $valid++ } elseif ($r.Status -eq 'FAIL') { $invalid++; if ($r.Suggestions.Count -gt 0) { $suggestions++ } }
            $keysReport += @{ agent = "deploy/$n"; model = $r.Model; status = $r.Status; reason = $r.Reason; suggestions = $r.Suggestions }
            if (-not $Json) {
                if ($r.Status -eq 'SKIP') {
                    Write-Output "SKIP:deploy/$n $($r.Model) ($($r.Reason))"
                } else {
                    $modelPart = if ($r.Status -eq 'FAIL' -and $r.Reason -eq 'frontmatter without model line') { "model=<missing>" } else { $r.Model }
                    $reasonPart = if ($r.Reason) { " ($($r.Reason))" } else { '' }
                    Write-Output "KEY:deploy/$n $modelPart -> $($r.Status)$reasonPart"
                }
                if ($r.Suggestions.Count -gt 0) {
                    Write-Output "SUGGEST:deploy/$n did_you_mean=$($r.Suggestions -join ', ')"
                }
            }
        }
        # PAIR per agent (live vs deploy SHA256).
        $lp = Join-Path $Agents "$n.md"
        $pairOk = $false; $pairDetail = ''
        if ((Test-Path -LiteralPath $lp) -and (Test-Path -LiteralPath $dp)) {
            $h1 = Get-Sha256 $lp
            $h2 = Get-Sha256 $dp
            if ($h1 -eq $h2) { $pairOk = $true } else { $pairDetail = " live=$($h1.Substring(0,8)) deploy=$($h2.Substring(0,8))" }
        } else {
            $pairDetail = ' side missing'
        }
        if ($pairOk) {
            $pairsReport += @{ agent = $n; status = 'OK'; detail = '' }
            if (-not $Json) { Write-Output "PAIR:$n -> OK" }
        } else {
            $invalid++
            $pairsReport += @{ agent = $n; status = 'FAIL'; detail = $pairDetail.Trim() }
            if (-not $Json) { Write-Output "PAIR:$n -> FAIL$pairDetail" }
        }
    }
}

# --- Unused models -----------------------------------------------------------
foreach ($key in @($catalog | Sort-Object)) {
    if (-not $used.ContainsKey($key)) {
        $unusedReport += $key
        if (-not $Json) { Write-Output "UNUSED:$key agents=0" }
    }
}

# --- Summary -------------------------------------------------------------------
$totalAgents = $liveFiles.Count
if ($Json) {
    $doc = @{
        keys = $keysReport
        unused = $unusedReport
        pairs = $pairsReport
        summary = @{ agents = $totalAgents; valid = $valid; invalid = $invalid; unused = $unusedReport.Count; suggestions = $suggestions }
    }
    $doc | ConvertTo-Json -Depth 5
} else {
    Write-Output "SUMMARY:agents=$totalAgents valid=$valid invalid=$invalid unused=$($unusedReport.Count) suggestions=$suggestions"
    if ($invalid -gt 0) {
        Write-Output "STATUS:FAILURES fail=$invalid"
        exit 3
    }
    Write-Output 'STATUS:ALL_VALID'
}
if ($invalid -gt 0) { exit 3 }
exit 0
