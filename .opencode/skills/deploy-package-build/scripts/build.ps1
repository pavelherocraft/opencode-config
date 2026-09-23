<#
.SYNOPSIS
    Deterministic rebuild of deploy-package/ from live sources.

.DESCRIPTION
    Byte-copies live agents (expected 37), live opencode.json, live
    plugins/workflow-enforcement.ts and the 4 root docs (ARCHITECTURE/AGENTS/
    MCP_SETUP/PLUGIN) into deploy-package/, SHA256-verifies every copy,
    regenerates HASHES.txt (LF, sorted, two-space format) and gates on counters
    (agents 37, distinct models 10, routing 25/10 across opencode.json +
    ARCHITECTURE.md + live workflow-enforcement.ts) plus a literal-secrets scan
    of opencode.json. -Plan (default) reports without writing; -Apply performs
    the build; -Archive additionally rebuilds deploy-package.7z via 7-Zip.
    NEVER deletes files, NEVER runs git, NEVER touches live files.

.PARAMETER Plan
    Report-only, zero writes (default when neither -Plan nor -Apply given).

.PARAMETER Apply
    Perform the build (copy + verify + HASHES.txt).

.PARAMETER Archive
    With -Apply: rebuild deploy-package.7z (requires 7-Zip).

.PARAMETER Strict
    STALE findings become exit 3.

.PARAMETER ExpectedAgents
    Gate default 37.

.PARAMETER ExpectedModels
    Gate default 10.

.PARAMETER ExpectedOrch
    Gate default 25.

.PARAMETER ExpectedPlan
    Gate default 10.

.PARAMETER Json
    JSON report instead of token lines (exit codes unchanged).

.OUTPUTS
    STATUS:/GATE:/COUNT:/SAME:/CHANGED:/NEW:/COPIED:/VERIFY:/WARN:/ERROR:/
    PLAN:/EDITED:/ARCHIVED:/SUMMARY: lines or a JSON document

.NOTES
    Exit codes: 0 plan clean / apply success, 2 usage/environment error,
    3 gate block, copy/verify failure, HASHES write failure, -Strict with STALE.

.EXAMPLE
    .\build.ps1 -Plan
    .\build.ps1 -Apply
    .\build.ps1 -Apply -Archive
#>

param(
    [switch]$Plan,
    [switch]$Apply,
    [switch]$Archive,
    [switch]$Strict,
    [int]$ExpectedAgents = 37,
    [int]$ExpectedModels = 10,
    [int]$ExpectedOrch = 25,
    [int]$ExpectedPlan = 10,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
# git emits UTF-8; keep non-ASCII repo paths intact.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Flag gates ---------------------------------------------------------------
if ($Plan -and $Apply) {
    Write-Output 'ERROR:FLAGS -Plan and -Apply are mutually exclusive'
    exit 2
}
if ($Archive -and -not $Apply) {
    Write-Output 'ERROR:FLAGS -Archive requires -Apply'
    exit 2
}
$mode = if ($Apply) { 'apply' } else { 'plan' }   # -Plan is the default

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

# --- Routing counter parsers (verbatim copies of the integrity-check helpers) ---
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

# --- Build helpers -----------------------------------------------------------
function Build-FileMap([string]$LiveDir, [string]$RepoRoot, [string]$Pkg) {
    $map = @()
    $agentsLive = Join-Path $LiveDir 'agents'
    $agentFiles = @(Get-ChildItem -LiteralPath $agentsLive -Filter '*.md' -File)
    $agentByName = @{}
    foreach ($f in $agentFiles) { $agentByName[$f.Name] = $f }
    $sortedNames = @($agentByName.Keys)
    [Array]::Sort($sortedNames, [System.StringComparer]::Ordinal)  # PY parity
    foreach ($n in $sortedNames) {
        $f = $agentByName[$n]
        $map += , @{ Src = $f.FullName; Dst = (Join-Path $Pkg ('agents\' + $f.Name)); Rel = ('agents/' + $f.Name) }
    }
    $map += , @{ Src = (Join-Path $LiveDir 'opencode.json'); Dst = (Join-Path $Pkg 'opencode.json'); Rel = 'opencode.json' }
    $map += , @{ Src = (Join-Path $LiveDir 'plugins\workflow-enforcement.ts'); Dst = (Join-Path $Pkg 'plugins\workflow-enforcement.ts'); Rel = 'plugins/workflow-enforcement.ts' }
    foreach ($d in @('ARCHITECTURE.md', 'AGENTS.md', 'MCP_SETUP.md', 'PLUGIN.md')) {
        $map += , @{ Src = (Join-Path $RepoRoot $d); Dst = (Join-Path $Pkg ('project-files\' + $d)); Rel = ('project-files/' + $d) }
    }
    return $map
}

function Test-Secrets([string]$JsonText) {
    # Conservative literal-secret scan - values are NEVER printed.
    $hits = @()
    $pats = @(
        @{ Name = 'sk-token';          Rx = '"sk-[A-Za-z0-9_\-]{16,}"' },
        @{ Name = 'literal-key-field'; Rx = '(?i)"(?:api[_-]?key|apikey|access[_-]?token|secret)"\s*:\s*"(?!\$)(?!YOUR_)(?!\{\{)[^"]{12,}"' }
    )
    foreach ($p in $pats) {
        $n = [regex]::Matches($JsonText, $p.Rx).Count
        if ($n -gt 0) { $hits += , @{ Pattern = $p.Name; Count = $n } }
    }
    return $hits
}

function Get-HashesScope([string]$Pkg) {
    $entries = @()
    foreach ($f in (Get-ChildItem -LiteralPath $Pkg -Recurse -File)) {
        $rel = $f.FullName.Substring($Pkg.Length + 1) -replace '\\', '/'
        if ($rel -like 'plugins/node_modules/*') { continue }
        if ($rel -eq 'deploy-package.7z' -or $rel -eq 'HASHES.txt' -or $rel -like '*.tmp7z') { continue }
        $entries += , @{ Rel = $rel; Sha = (Get-Sha256 $f.FullName) }
    }
    $sorted = @($entries)
    # ordinal sort - byte-stable across PS/PY mirrors
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        for ($j = $i + 1; $j -lt $sorted.Count; $j++) {
            if ([string]::CompareOrdinal($sorted[$j].Rel, $sorted[$i].Rel) -lt 0) {
                $tmp = $sorted[$i]; $sorted[$i] = $sorted[$j]; $sorted[$j] = $tmp
            }
        }
    }
    return $sorted
}

function Write-HashesFile([string]$Pkg) {
    $sorted = Get-HashesScope $Pkg
    $text = (($sorted | ForEach-Object { '{0}  {1}' -f $_.Sha, $_.Rel }) -join "`n") + "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)   # no BOM, LF
    $target = Join-Path $Pkg 'HASHES.txt'
    if ((Test-Path -LiteralPath $target)) {
        $old = [System.IO.File]::ReadAllBytes($target)
        if ($old.Length -eq $bytes.Length) {
            $same = $true
            for ($i = 0; $i -lt $bytes.Length; $i++) { if ($old[$i] -ne $bytes[$i]) { $same = $false; break } }
            if ($same) { return @{ Changed = $false; Lines = $sorted.Count } }
        }
    }
    [System.IO.File]::WriteAllBytes($target, $bytes)
    return @{ Changed = $true; Lines = $sorted.Count }
}

function Find-SevenZip {
    $cmd = Get-Command '7z' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cands = @()
    if ($env:ProgramFiles) { $cands += (Join-Path $env:ProgramFiles '7-Zip\7z.exe') }
    if (${env:ProgramFiles(x86)}) { $cands += (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe') }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}

function Get-StaleFiles([string]$Pkg, [string[]]$LiveAgentNames) {
    $stale = @()
    $depAgents = Join-Path $Pkg 'agents'
    if (Test-Path -LiteralPath $depAgents) {
        foreach ($f in (Get-ChildItem -LiteralPath $depAgents -Filter '*.md' -File)) {
            if ($LiveAgentNames -notcontains $f.BaseName) { $stale += ('agents/' + $f.Name) }
        }
    }
    $pf = Join-Path $Pkg 'project-files'
    $allowedDocs = @('ARCHITECTURE.md', 'AGENTS.md', 'MCP_SETUP.md', 'PLUGIN.md')
    if (Test-Path -LiteralPath $pf) {
        foreach ($f in (Get-ChildItem -LiteralPath $pf -Filter '*.md' -File)) {
            if ($allowedDocs -notcontains $f.Name) { $stale += ('project-files/' + $f.Name) }
        }
    }
    return $stale
}

# --- Paths ------------------------------------------------------------------
$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $skillDir)))
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy-package"))) {
    $gitRoot = Invoke-Native -FilePath "git" -Arguments @("-C", $skillDir, "rev-parse", "--show-toplevel")
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { $repoRoot = ($gitRoot | Select-Object -First 1).Trim() }
}
$liveDir = Join-Path $env:USERPROFILE '.config\opencode'
$pkg = Join-Path $repoRoot 'deploy-package'
$liveAgentsDir = Join-Path $liveDir 'agents'
$liveCfgPath = Join-Path $liveDir 'opencode.json'
$liveTsPath = Join-Path $liveDir 'plugins\workflow-enforcement.ts'

# --- Pre-checks (exit 2, zero copies) ------------------------------------------
$preFail = @()
foreach ($p in @(
    @{ Path = $liveDir; What = 'live config dir' },
    @{ Path = $liveAgentsDir; What = 'live agents dir' },
    @{ Path = $liveCfgPath; What = 'live opencode.json' },
    @{ Path = $liveTsPath; What = 'live workflow-enforcement.ts' },
    @{ Path = $pkg; What = 'deploy-package dir' },
    @{ Path = (Join-Path $pkg 'agents'); What = 'deploy-package agents dir' },
    @{ Path = (Join-Path $pkg 'project-files'); What = 'deploy-package project-files dir' },
    @{ Path = (Join-Path $repoRoot 'ARCHITECTURE.md'); What = 'root ARCHITECTURE.md' },
    @{ Path = (Join-Path $repoRoot 'AGENTS.md'); What = 'root AGENTS.md' },
    @{ Path = (Join-Path $repoRoot 'MCP_SETUP.md'); What = 'root MCP_SETUP.md' },
    @{ Path = (Join-Path $repoRoot 'PLUGIN.md'); What = 'root PLUGIN.md' }
)) {
    if (-not (Test-Path -LiteralPath $p.Path)) { $preFail += "ERROR:ENV $($p.What) not found: $($p.Path)" }
}
if ($preFail.Count -gt 0) { foreach ($e in $preFail) { Write-Output $e }; exit 2 }
$liveAgentFiles = @(Get-ChildItem -LiteralPath $liveAgentsDir -Filter '*.md' -File)
if ($liveAgentFiles.Count -eq 0) {
    Write-Output "ERROR:ENV live agents dir empty: $liveAgentsDir"
    exit 2
}
$sevenZip = $null
if ($Archive) {
    $sevenZip = Find-SevenZip
    if (-not $sevenZip) {
        Write-Output 'ERROR:ENV sevenzip not found (7z in PATH, %ProgramFiles%\7-Zip\7z.exe, %ProgramFiles(x86)%\7-Zip\7z.exe)'
        exit 2
    }
}
$fileMap = Build-FileMap $liveDir $repoRoot $pkg
foreach ($e in $fileMap) {
    if (-not (Test-Path -LiteralPath $e.Src -PathType Leaf)) {
        Write-Output "ERROR:ENV mapped source missing: $($e.Src)"
        exit 2
    }
}

if (-not $Json) { Write-Output ("STATUS:BUILD_START mode={0} agents_expected={1}" -f $mode, $ExpectedAgents) }

# --- Gates (before any write) -----------------------------------------------------
$gates = @()
$gatesFailed = 0

# GATE:JSON
$cfgText = (Read-RawText $liveCfgPath).Text
$cfg = $null
$jsonOk = $true
try { $cfg = $cfgText | ConvertFrom-Json } catch { $jsonOk = $false }
if ($jsonOk) {
    $gates += , @{ Id = 'JSON'; Status = 'PASS'; Detail = 'file=opencode.json parse ok' }
} else {
    $gates += , @{ Id = 'JSON'; Status = 'BLOCK'; Detail = 'file=opencode.json invalid JSON' }
    $gatesFailed++
}

# GATE:SECRETS (values never printed - pattern name + hit count only)
$secretHits = Test-Secrets $cfgText
if ($secretHits.Count -eq 0) {
    $gates += , @{ Id = 'SECRETS'; Status = 'PASS'; Detail = 'file=opencode.json hits=0' }
} else {
    $patCsv = ($secretHits | ForEach-Object { $_.Pattern }) -join ','
    $hitsN = ($secretHits | Measure-Object -Property Count -Sum).Sum
    $gates += , @{ Id = 'SECRETS'; Status = 'BLOCK'; Detail = "file=opencode.json hits=$hitsN patterns=$patCsv" }
    $gatesFailed++
}

# COUNT:agents_live
$nAgents = $liveAgentFiles.Count
if ($nAgents -eq $ExpectedAgents) {
    $gates += , @{ Id = 'agents_live'; Status = 'PASS'; Detail = "$nAgents expected=$ExpectedAgents" }
} else {
    $gates += , @{ Id = 'agents_live'; Status = 'BLOCK'; Detail = "$nAgents expected=$ExpectedAgents" }
    $gatesFailed++
}

# COUNT:models_used
$modelsUsed = @{}
foreach ($f in $liveAgentFiles) {
    $m = Get-FmModel (Read-RawText $f.FullName).Text
    if ($m) { $modelsUsed[$m] = $true }
}
if ($modelsUsed.Count -eq $ExpectedModels) {
    $gates += , @{ Id = 'models_used'; Status = 'PASS'; Detail = "$($modelsUsed.Count) expected=$ExpectedModels" }
} else {
    $gates += , @{ Id = 'models_used'; Status = 'BLOCK'; Detail = "$($modelsUsed.Count) expected=$ExpectedModels" }
    $gatesFailed++
}

# COUNT:routing_orchestrator / routing_plankestrator (3 sources)
$archPath = Join-Path $repoRoot 'ARCHITECTURE.md'
$archText = (Read-RawText $archPath).Text
$tsText = (Read-RawText $liveTsPath).Text
$routingWarns = @()
foreach ($rs in @(
    @{ Primary = 'orchestrator'; Expected = $ExpectedOrch },
    @{ Primary = 'plankestrator'; Expected = $ExpectedPlan }
)) {
    $prim = $rs.Primary; $exp = $rs.Expected
    $jsonN = $null
    if ($jsonOk) { $jsonN = Count-TaskAllow $cfg $prim }
    $wl = Get-WhitelistCount $archText $prim
    $archH = $null; $archR = $null
    if ($null -ne $wl) { $archH = $wl.Header; $archR = $wl.Rows }
    $plugN = Count-RoutingPlugin $tsText $prim
    $ok = ($null -ne $jsonN -and $jsonN -eq $exp -and $null -ne $archH -and $archH -eq $exp -and $null -ne $archR -and $archR -eq $exp)
    if ($null -ne $plugN -and $plugN -ne $exp) { $ok = $false }
    if ($null -eq $plugN) { $routingWarns += "WARN:routing $prim plugin anchor not parsed (skipped plugin source)" }
    $plugStr = if ($null -ne $plugN) { "$plugN" } else { '-' }
    $detail = "json=$jsonN arch_header=$archH arch_rows=$archR plugin=$plugStr expected=$exp"
    if ($ok) {
        $gates += , @{ Id = "routing_$prim"; Status = 'PASS'; Detail = $detail }
    } else {
        $gates += , @{ Id = "routing_$prim"; Status = 'BLOCK'; Detail = $detail }
        $gatesFailed++
    }
}

if (-not $Json) {
    foreach ($g in $gates) {
        if ($g.Id -eq 'JSON' -or $g.Id -eq 'SECRETS') { Write-Output "GATE:$($g.Id) $($g.Detail) -> $($g.Status)" }
        elseif ($g.Id -like 'routing_*') { Write-Output "COUNT:$($g.Id) $($g.Detail) -> $($g.Status)" }
        else { Write-Output "COUNT:$($g.Id)=$($g.Detail) -> $($g.Status)" }
    }
    foreach ($w in $routingWarns) { Write-Output $w }
}

if ($gatesFailed -gt 0) {
    if ($Json) {
        $doc = @{ mode = $mode; gates = $gates; files = @(); stale = @(); hashes = $null; archive = $null
                  summary = @{ mode = $mode; gates_failed = $gatesFailed; blocked = $true } }
        $doc | ConvertTo-Json -Depth 6
    } else {
        Write-Output "SUMMARY:gates_failed=$gatesFailed"
        Write-Output "STATUS:BLOCKED gates=$gatesFailed"
    }
    exit 3
}

# --- Diff scan (SHA256 Src vs Dst) ----------------------------------------------
$diff = @()
$nSame = 0; $nChanged = 0; $nNew = 0
foreach ($e in $fileMap) {
    $srcSha = Get-Sha256 $e.Src
    if (-not (Test-Path -LiteralPath $e.Dst -PathType Leaf)) {
        $nNew++
        $diff += , @{ Rel = $e.Rel; Status = 'NEW'; Src = $e.Src; Dst = $e.Dst; Live8 = $srcSha.Substring(0, 8); Dep8 = ''; Bytes = 0 }
        if (-not $Json) { Write-Output "NEW:$($e.Rel)" }
    } else {
        $dstSha = Get-Sha256 $e.Dst
        if ($srcSha -eq $dstSha) {
            $nSame++
            $diff += , @{ Rel = $e.Rel; Status = 'SAME'; Src = $e.Src; Dst = $e.Dst; Live8 = $srcSha.Substring(0, 8); Dep8 = $dstSha.Substring(0, 8); Bytes = 0 }
            if (-not $Json) { Write-Output "SAME:$($e.Rel) sha=$($srcSha.Substring(0, 8))" }
        } else {
            $nChanged++
            $diff += , @{ Rel = $e.Rel; Status = 'CHANGED'; Src = $e.Src; Dst = $e.Dst; Live8 = $srcSha.Substring(0, 8); Dep8 = $dstSha.Substring(0, 8); Bytes = 0 }
            if (-not $Json) { Write-Output ("CHANGED:{0} live={1} deploy={2}" -f $e.Rel, $srcSha.Substring(0, 8), $dstSha.Substring(0, 8)) }
        }
    }
}

# --- STALE scan (strict block happens BEFORE any write) ---------------------------
$liveNames = @($liveAgentFiles | ForEach-Object { $_.BaseName })
$stale = Get-StaleFiles $pkg $liveNames
foreach ($s in $stale) { if (-not $Json) { Write-Output "WARN:STALE:$s" } }
if ($Strict -and $stale.Count -gt 0) {
    if ($Json) {
        $doc = @{ mode = $mode; gates = $gates; files = $diff; stale = $stale; hashes = $null; archive = $null
                  summary = @{ mode = $mode; gates_failed = 0; stale = $stale.Count; blocked = $true } }
        $doc | ConvertTo-Json -Depth 6
    } else {
        Write-Output "STATUS:BLOCKED stale=$($stale.Count)"
    }
    exit 3
}

# --- Plan mode ---------------------------------------------------------------------
if ($mode -eq 'plan') {
    $hashScope = @(Get-HashesScope $pkg)
    $hashLines = $hashScope.Count
    if ($Json) {
        $doc = @{ mode = 'plan'; gates = $gates
                  files = @($diff | ForEach-Object { @{ rel = $_.Rel; status = $_.Status; live_sha8 = $_.Live8; deploy_sha8 = $_.Dep8 } })
                  stale = $stale
                  hashes = @{ lines = $hashLines; changed = $null }
                  archive = $null
                  summary = @{ mode = 'plan'; scanned = $diff.Count; same = $nSame; changed = $nChanged; new = $nNew; stale = $stale.Count } }
        $doc | ConvertTo-Json -Depth 6
    } else {
        Write-Output "PLAN:HASHES.txt files=$hashLines"
        Write-Output "SUMMARY:mode=plan scanned=$($diff.Count) same=$nSame changed=$nChanged new=$nNew stale=$($stale.Count)"
        Write-Output 'STATUS:PLAN_OK'
    }
    exit 0
}

# --- Apply mode --------------------------------------------------------------------
$nCopied = 0; $nFailed = 0; $totalBytes = 0
foreach ($e in $diff) {
    if ($e.Status -ne 'CHANGED' -and $e.Status -ne 'NEW') { continue }
    $dstDir = Split-Path -Parent $e.Dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    $err = $null
    try {
        [System.IO.File]::Copy($e.Src, $e.Dst, $true)
    } catch {
        $err = $_.Exception.Message
    }
    if ($err) {
        $nFailed++
        if (-not $Json) { Write-Output "ERROR:$($e.Rel) copy failed: $err" }
        continue
    }
    $srcSha = Get-Sha256 $e.Src
    $dstSha = Get-Sha256 $e.Dst
    if ($srcSha -ne $dstSha) {
        $nFailed++
        if (-not $Json) { Write-Output "ERROR:$($e.Rel) hash mismatch after copy" }
        continue
    }
    $nBytes = ([System.IO.FileInfo]$e.Dst).Length
    $nCopied++
    $totalBytes += $nBytes
    if (-not $Json) {
        Write-Output "COPIED:$($e.Rel) sha=$($srcSha.Substring(0, 8)) bytes=$nBytes"
        Write-Output "VERIFY:$($e.Rel) identical"
    }
}
if ($nFailed -gt 0) {
    if ($Json) {
        $doc = @{ mode = 'apply'; gates = $gates
                  files = @($diff | ForEach-Object { @{ rel = $_.Rel; status = $_.Status; live_sha8 = $_.Live8; deploy_sha8 = $_.Dep8 } })
                  stale = $stale; hashes = $null; archive = $null
                  summary = @{ mode = 'apply'; scanned = $diff.Count; same = $nSame; changed = $nChanged; new = $nNew; copied = $nCopied; failed = $nFailed; stale = $stale.Count; bytes = $totalBytes } }
        $doc | ConvertTo-Json -Depth 6
    } else {
        Write-Output "STATUS:FAILED copied=$nCopied failed=$nFailed (copied files are KEPT - never deleted)"
    }
    exit 3
}

# HASHES.txt (content-equal -> no rewrite)
$hashInfo = $null
$hashErr = $null
try {
    $hashInfo = Write-HashesFile $pkg
} catch {
    $hashErr = $_.Exception.Message
}
if ($null -ne $hashErr) {
    if (-not $Json) { Write-Output "ERROR:HASHES write failed: $hashErr" }
    exit 3
}
if (-not $Json) {
    if ($hashInfo.Changed) { Write-Output "EDITED:HASHES.txt lines=$($hashInfo.Lines)" }
    else { Write-Output "SAME:HASHES.txt" }
}

# -Archive (only after success)
$archInfo = $null
if ($Archive) {
    $tmp = Join-Path $pkg 'deploy-package.7z.tmp7z'
    $prevLoc = Get-Location
    Set-Location -LiteralPath $repoRoot
    try {
        $null = Invoke-Native -FilePath $sevenZip -Arguments @(
            'a', '-t7z', '-mx=5', ("-w" + $repoRoot),
            'deploy-package\deploy-package.7z.tmp7z', 'deploy-package\*',
            '-xr!*.tmp7z', '-xr!deploy-package.7z')
    } finally {
        Set-Location -LiteralPath $prevLoc.Path
    }
    if ($LASTEXITCODE -ge 2) {
        if (-not $Json) { Write-Output "ERROR:ARCHIVE 7z exit=$LASTEXITCODE (tmp KEPT - never deleted)" }
        exit 3
    }
    Move-Item -LiteralPath $tmp -Destination (Join-Path $pkg 'deploy-package.7z') -Force
    $archSha = Get-Sha256 (Join-Path $pkg 'deploy-package.7z')
    $archBytes = ([System.IO.FileInfo](Join-Path $pkg 'deploy-package.7z')).Length
    $archInfo = @{ file = 'deploy-package.7z'; sha8 = $archSha.Substring(0, 8); bytes = $archBytes }
    if (-not $Json) { Write-Output "ARCHIVED:deploy-package.7z sha=$($archSha.Substring(0, 8)) bytes=$archBytes" }
}

# Manual follow-ups
if (-not $Json) {
    Write-Output 'WARN:MANUAL commit deploy-package changes via the git-commit agent'
    Write-Output 'WARN:MANUAL live-config changes take effect in a NEW opencode session'
    Write-Output 'WARN:MANUAL target install via deploy-package\scripts\install.ps1'
    Write-Output 'WARN:MANUAL recommended post-check: integrity-check + deploy-package\scripts\verify.ps1'
}

if ($Json) {
    $doc = @{ mode = 'apply'; gates = $gates
              files = @($diff | ForEach-Object { @{ rel = $_.Rel; status = $_.Status; live_sha8 = $_.Live8; deploy_sha8 = $_.Dep8 } })
              stale = $stale
              hashes = @{ lines = $hashInfo.Lines; changed = $hashInfo.Changed }
              archive = $archInfo
              summary = @{ mode = 'apply'; scanned = $diff.Count; same = $nSame; changed = $nChanged; new = $nNew; copied = $nCopied; stale = $stale.Count; bytes = $totalBytes } }
    $doc | ConvertTo-Json -Depth 6
} else {
    Write-Output "SUMMARY:mode=apply scanned=$($diff.Count) same=$nSame changed=$nChanged new=$nNew copied=$nCopied stale=$($stale.Count) bytes=$totalBytes"
    Write-Output 'STATUS:SUCCESS'
}
exit 0
