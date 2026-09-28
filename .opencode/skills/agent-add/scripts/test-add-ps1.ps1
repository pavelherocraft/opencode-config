$ErrorActionPreference = 'Stop'

$script:Pass = 0
$script:Fail = 0

function Assert([string]$Name, $Condition, [string]$Detail) {
    $ok = $false
    if ($Condition -is [bool]) { $ok = $Condition }
    if ($ok) {
        $script:Pass += 1
        Write-Output "PASS: $Name"
    } else {
        $script:Fail += 1
        Write-Output "FAIL: $Name -- $Detail"
    }
}

# ---- extract functions from add.ps1 (read-only, no side effects) ----
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'add.ps1') -Raw
$fnNames = @(
    'Get-PermPreset',
    'Add-FmTaskExtras',
    'Split-LinesKeepEol',
    'Detect-Eol',
    'Edit-RoutingArray',
    'Count-RoutingPlugin',
    'Get-RoutingTokens'
)
$defs = New-Object System.Collections.Generic.List[string]
foreach ($n in $fnNames) {
    $m = [regex]::Match($src, ('(?sm)^function ' + $n + '\b.*?\r?\n\}'))
    if (-not $m.Success) { throw "function $n not found in add.ps1" }
    $defs.Add($m.Value)
}
$tok = [regex]::Match($src, '(?m)^\$script:TokenRx = .*$')
if (-not $tok.Success) { throw 'TokenRx not found in add.ps1' }
$defs.Add($tok.Value)
Invoke-Expression ($defs -join "`n`n")

# ---- fixture: synthetic ROUTING_TABLES with a realistic prefix so that
#      'const ROUTING_TABLES' is NOT at position 0 of the text (a prefix of
#      ~50 chars is enough to route a wrong insertion into the wrong array) ----
$tsFixture = (@(
    'import type { Plugin } from "@opencode-ai/plugin"',
    '',
    'const ROUTING_TABLES = {',
    '  orchestrator: [',
    '    "orchestrator-identity-probe",',
    '    "dev-reviewer",',
    '    "codebase-analyzer"',
    '  ],',
    '  plankestrator: [',
    '    "plankestrator-identity-probe",',
    '    "view-image"',
    '  ]',
    '}'
) -join "`r`n")

function Try-EditRoutingArray([string]$Text, [string]$Primary, [string]$Name) {
    try { return Edit-RoutingArray $Text $Primary $Name '' }
    catch { return @{ Text = $null; Error = "EXCEPTION: $_" } }
}

function Get-ArraySpan([string]$Text, [string]$ArrayKey) {
    if ([string]::IsNullOrEmpty($Text)) { return @{ Start = -1; Close = -1 } }
    $start = $Text.IndexOf($ArrayKey + ': [')
    if ($start -lt 0) { return @{ Start = -1; Close = -1 } }
    $close = $Text.IndexOf(']', $start)
    if ($close -lt 0) { return @{ Start = $start; Close = $Text.Length + 1 } }
    return @{ Start = $start; Close = $close }
}

# ============================================================================
# TEST 1: Edit-RoutingArray inserts into the CORRECT array (orchestrator)
# ============================================================================
$r = Try-EditRoutingArray $tsFixture 'orchestrator' 'new-agent'
Assert 'T1 no error' (-not $r.Error) "error=$($r.Error)"
Assert 'T1 orchestrator token count 3 -> 4' ((Count-RoutingPlugin $r.Text 'orchestrator') -eq 4) "got $(Count-RoutingPlugin $r.Text 'orchestrator')"
Assert 'T1 plankestrator token count unchanged (2)' ((Count-RoutingPlugin $r.Text 'plankestrator') -eq 2) "got $(Count-RoutingPlugin $r.Text 'plankestrator')"
$toksOrch = @(Get-RoutingTokens $r.Text 'orchestrator')
$toksPlank = @(Get-RoutingTokens $r.Text 'plankestrator')
Assert 'T1 new-agent in orchestrator exactly once' ((@($toksOrch | Where-Object { $_ -eq 'new-agent' }).Count) -eq 1) "orch=$($toksOrch -join ',')"
Assert 'T1 new-agent NOT in plankestrator' ((@($toksPlank | Where-Object { $_ -eq 'new-agent' }).Count) -eq 0) "plank=$($toksPlank -join ',')"
$span = Get-ArraySpan $r.Text '  orchestrator'
$tokPos = if ($r.Text) { $r.Text.IndexOf('"new-agent"') } else { -1 }
Assert 'T1 token position inside orchestrator array bounds' ($tokPos -gt $span.Start -and $tokPos -lt $span.Close) "tokPos=$tokPos span=$($span.Start)..$($span.Close)"
Assert 'T1 existing token "codebase-analyzer" intact' (($r.Text -split '"codebase-analyzer"').Count -eq 2) 'token corrupted'
Assert 'T1 existing token "view-image" intact' (($r.Text -split '"view-image"').Count -eq 2) 'token corrupted'
Assert 'T1 result still parses as two arrays' ((Count-RoutingPlugin $r.Text 'orchestrator') -and (Count-RoutingPlugin $r.Text 'plankestrator'))

# ============================================================================
# TEST 2: Edit-RoutingArray inserts into the CORRECT array (plankestrator)
# ============================================================================
$r = Try-EditRoutingArray $tsFixture 'plankestrator' 'new-agent'
Assert 'T2 no error' (-not $r.Error) "error=$($r.Error)"
Assert 'T2 plankestrator token count 2 -> 3' ((Count-RoutingPlugin $r.Text 'plankestrator') -eq 3) "got $(Count-RoutingPlugin $r.Text 'plankestrator')"
Assert 'T2 orchestrator token count unchanged (3)' ((Count-RoutingPlugin $r.Text 'orchestrator') -eq 3) "got $(Count-RoutingPlugin $r.Text 'orchestrator')"
$toksOrch = @(Get-RoutingTokens $r.Text 'orchestrator')
$toksPlank = @(Get-RoutingTokens $r.Text 'plankestrator')
Assert 'T2 new-agent in plankestrator exactly once' ((@($toksPlank | Where-Object { $_ -eq 'new-agent' }).Count) -eq 1) "plank=$($toksPlank -join ',')"
Assert 'T2 new-agent NOT in orchestrator' ((@($toksOrch | Where-Object { $_ -eq 'new-agent' }).Count) -eq 0) "orch=$($toksOrch -join ',')"
$span = Get-ArraySpan $r.Text '  plankestrator'
$tokPos = if ($r.Text) { $r.Text.IndexOf('"new-agent"') } else { -1 }
Assert 'T2 token position inside plankestrator array bounds' ($tokPos -gt $span.Start -and $tokPos -lt $span.Close) "tokPos=$tokPos span=$($span.Start)..$($span.Close)"

# ============================================================================
# TEST 3: duplicate insert is rejected
# ============================================================================
$r = Try-EditRoutingArray $tsFixture 'orchestrator' 'new-agent'
$r2 = Try-EditRoutingArray $r.Text 'orchestrator' 'new-agent'
Assert 'T3 duplicate rejected' ($null -ne $r2.Error) "expected error, got none; text changed: $($r2.Text -ne $r.Text)"

# ============================================================================
# TEST 4: frontmatter preset path — lines stay separate, task block appended
# ============================================================================
$preset = Get-PermPreset 'standard'
$permL = @(Add-FmTaskExtras $preset.FmYaml @('view-image', 'utility'))
Assert 'T4 line count = 12 preset + task: + "*": deny + 2 extras = 16' ($permL.Count -eq 16) "got $($permL.Count): [$($permL -join ' | ')]"
Assert 'T4 first line is "edit: deny"' ($permL[0] -eq 'edit: deny') "got <$($permL[0])>"
Assert 'T4 contains "task:" line' (@($permL | Where-Object { $_ -eq 'task:' }).Count -eq 1) 'task: line missing'
Assert 'T4 contains view-image allow' (@($permL | Where-Object { $_ -match 'view-image: allow' }).Count -eq 1) 'missing'
Assert 'T4 contains utility allow' (@($permL | Where-Object { $_ -match 'utility: allow' }).Count -eq 1) 'missing'
$merged = @($permL | Where-Object { $_ -match 'deny.*deny' -or $_ -match 'allow.*allow' })
Assert 'T4 no merged multi-permission lines' ($merged.Count -eq 0) "merged: $($merged -join ' || ')"

# ============================================================================
# TEST 5: frontmatter template path — task block from template preserved,
#         extras inserted, lines stay separate
# ============================================================================
$tplText = (@(
    '---',
    'description: T',
    'mode: subagent',
    'model: m',
    'temperature: 0.1',
    'permission:',
    '  edit: deny',
    '  write: deny',
    '  read: allow',
    '  task:',
    '    "*": deny',
    '    "advisor": allow',
    '---',
    '',
    'body'
) -join "`r`n")
$tplLines = Split-LinesKeepEol $tplText
$permStart = -1
for ($i = 0; $i -lt $tplLines.Count; $i += 2) {
    if ($tplLines[$i] -match '^permission:[ \t]*$') { $permStart = $i; break }
}
$fmPermLines = @()
for ($i = $permStart + 2; $i -lt $tplLines.Count; $i += 2) {
    if ($tplLines[$i] -match '^---[ \t]*$') { break }
    $fmPermLines += $tplLines[$i] -replace '^  ', ''
}
Assert 'T5 template perm lines = 6' ($fmPermLines.Count -eq 6) "got $($fmPermLines.Count): [$($fmPermLines -join ' | ')]"
$permL = @(Add-FmTaskExtras $fmPermLines @('extra-agent'))
Assert 'T5 line count = 7' ($permL.Count -eq 7) "got $($permL.Count): [$($permL -join ' | ')]"
Assert 'T5 first line is "edit: deny"' ($permL[0] -eq 'edit: deny') "got <$($permL[0])>"
Assert 'T5 template task entry preserved' (@($permL | Where-Object { $_ -match 'advisor.*allow' }).Count -eq 1) 'template task allow lost'
Assert 'T5 extra inserted' (@($permL | Where-Object { $_ -match 'extra-agent.*allow' }).Count -eq 1) 'extra not inserted'
$merged = @($permL | Where-Object { $_ -match 'deny.*deny' -or $_ -match 'allow.*allow' })
Assert 'T5 no merged multi-permission lines' ($merged.Count -eq 0) "merged: $($merged -join ' || ')"

# ============================================================================
# TEST 6: real live plugin (regression on the actual file, read-only)
# ============================================================================
$livePlugin = Join-Path $env:USERPROFILE '.config\opencode\plugins\workflow-enforcement.ts'
if (Test-Path -LiteralPath $livePlugin) {
    $ts = Get-Content -LiteralPath $livePlugin -Raw
    $orchBefore = Count-RoutingPlugin $ts 'orchestrator'
    $plankBefore = Count-RoutingPlugin $ts 'plankestrator'
    $r = Try-EditRoutingArray $ts 'orchestrator' 'zz-regression-probe'
    Assert 'T6 no error on real plugin' (-not $r.Error) "error=$($r.Error)"
    Assert 'T6 orchestrator count +1' ((Count-RoutingPlugin $r.Text 'orchestrator') -eq ($orchBefore + 1)) "before=$orchBefore after=$(Count-RoutingPlugin $r.Text 'orchestrator')"
    Assert 'T6 plankestrator count unchanged' ((Count-RoutingPlugin $r.Text 'plankestrator') -eq $plankBefore) "before=$plankBefore after=$(Count-RoutingPlugin $r.Text 'plankestrator')"
    $toksPlank = @(Get-RoutingTokens $r.Text 'plankestrator')
    Assert 'T6 probe NOT in plankestrator' ((@($toksPlank | Where-Object { $_ -eq 'zz-regression-probe' }).Count) -eq 0) 'probe leaked'
    Assert 'T6 probe exactly once in orchestrator' ((@(Get-RoutingTokens $r.Text 'orchestrator') | Where-Object { $_ -eq 'zz-regression-probe' }).Count -eq 1) 'probe missing'
    $orchKey = $ts.IndexOf('orchestrator: [')
    $plankKey = '  plankestrator: ['
    Assert 'T6 text before orchestrator array byte-identical' ($ts.Substring(0, $orchKey) -eq $r.Text.Substring(0, $orchKey)) 'prefix changed'
    $tsPlank = $ts.Substring($ts.IndexOf($plankKey))
    $newPlank = $r.Text.Substring($r.Text.IndexOf($plankKey))
    Assert 'T6 plankestrator array byte-identical' ($tsPlank -eq $newPlank) 'plankestrator array changed'
} else {
    Write-Output 'SKIP: live plugin not found'
}

# ============================================================================
Write-Output ''
Write-Output "RESULT: pass=$script:Pass fail=$script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
