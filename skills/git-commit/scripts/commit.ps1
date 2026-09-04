# git-commit skill script: analyze repo state and create gated conventional commits.
#
# Modes:
#   -Analyze                          dry-run: status, diff stats, log style, hygiene report
#   -Message "..." [-Files a,b] [-StagedOnly] [-Push]
#                                     stage (explicit files or already-staged), run safety
#                                     gates, commit, optionally push
#
# Gates (BLOCK = refuse to commit):
#   - git identity (user.name/user.email) missing
#   - sensitive filenames staged (.env*, *.pem, *.key, *.p12, *.pfx, id_rsa*, credentials.json)
#   - secret patterns in staged diff (sk-, ghp_..., AKIA..., PRIVATE KEY blocks, xox-, AIza, Bearer <literal>)
#   - conflict markers (<<<<<<< / >>>>>>>) in staged diff
# WARN (commit continues):
#   - staged file > 5MB
#   - commit subject > 72 chars
# Never used by this script: --no-verify, amend, force-push.
#
# Output lines: STATUS:/STAGED:/UNSTAGED:/STYLE:/WARN:/BLOCK:/COMMITTED:/PUSHED:/ERROR:

param(
    [string]$Message,
    [string[]]$Files = @(),
    [switch]$StagedOnly,
    [switch]$Push,
    [switch]$Analyze,
    [string]$RepoDir = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

# ---------- helpers ----------

$Script:Blocks = New-Object System.Collections.Generic.List[string]
$Script:Warns   = New-Object System.Collections.Generic.List[string]

function Block([string]$Text) { $Script:Blocks.Add($Text); Write-Output "BLOCK: $Text" }
function Warn([string]$Text)  { $Script:Warns.Add($Text);  Write-Output "WARN: $Text" }

$SecretPatterns = @(
    @{ Name = 'OpenAI-style key';   Regex = 'sk-[A-Za-z0-9_-]{20,}' },
    @{ Name = 'GitHub token';       Regex = 'gh[pousr]_[A-Za-z0-9]{30,}' },
    @{ Name = 'GitHub PAT';         Regex = 'github_pat_[A-Za-z0-9_]{22,}' },
    @{ Name = 'AWS access key';     Regex = 'AKIA[0-9A-Z]{16}' },
    @{ Name = 'Private key block';  Regex = '-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----' },
    @{ Name = 'Slack token';        Regex = 'xox[baprs]-[A-Za-z0-9-]{10,}' },
    @{ Name = 'Google API key';     Regex = 'AIza[0-9A-Za-z_-]{35}' },
    @{ Name = 'Bearer literal';     Regex = 'Bearer\s+[A-Za-z0-9]{30,}' }
)

$SensitiveNamePatterns = @(
    '\.env($|\.)',
    '\.pem$',
    '\.key$',
    '\.p12$',
    '\.pfx$',
    '^id_(rsa|ed25519|ecdsa)',
    'credentials\.json$',
    'service[-_]?account.*\.json$'
)

function Find-Secrets([string]$Text) {
    $hits = @()
    if (-not $Text) { return $hits }
    foreach ($p in $SecretPatterns) {
        $m = [regex]::Matches($Text, $p.Regex)
        if ($m.Count -gt 0) { $hits += ("{0} (x{1})" -f $p.Name, $m.Count) }
    }
    return $hits
}

function Get-StagedFiles() {
    $names = @()
    git diff --cached --name-only | ForEach-Object { if ($_ -match '\S') { $names += $_ } }
    return $names
}

function Test-SensitiveName([string]$Path) {
    foreach ($p in $SensitiveNamePatterns) {
        if ($Path -match $p) { return $p }
    }
    return $null
}

# ---------- main ----------

Push-Location -LiteralPath $RepoDir
try {
    # repo sanity
    $insideRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $insideRepo -ne 'true') {
        Write-Output "ERROR: not a git repository: $RepoDir"; exit 2
    }

    # mid-rebase / mid-merge detection
    $gitDir = git rev-parse --git-dir
    if ((Test-Path (Join-Path $gitDir 'rebase-merge')) -or (Test-Path (Join-Path $gitDir 'rebase-apply')) -or (Test-Path (Join-Path $gitDir 'MERGE_HEAD'))) {
        Write-Output 'ERROR: rebase/merge in progress - resolve it first'; exit 2
    }

    # identity
    $userName = git config user.name
    $userEmail = git config user.email
    $identityOk = ($userName -and $userEmail)

    # ------------- ANALYZE MODE -------------
    if ($Analyze) {
        Write-Output '=== ANALYZE (dry-run, nothing committed) ==='
        Write-Output ("REPO: " + (git rev-parse --show-toplevel))
        Write-Output ("BRANCH: " + (git branch --show-current))
        if ($identityOk) { Write-Output "IDENTITY: OK ($userName <$userEmail>)" }
        else { Write-Output 'IDENTITY: MISSING user.name/user.email (BLOCK for commit)' }

        Write-Output '--- STATUS ---'
        git status --porcelain=v1 -b

        $stagedStat = git diff --cached --stat
        if ($stagedStat) { Write-Output '--- STAGED DIFF (stat) ---'; $stagedStat | Select-Object -Last 3 }
        else { Write-Output '--- STAGED DIFF: (empty)' }

        $unstagedStat = git diff --stat
        if ($unstagedStat) { Write-Output '--- UNSTAGED DIFF (stat) ---'; $unstagedStat | Select-Object -Last 3 }

        $untracked = @(git ls-files --others --exclude-standard)
        if ($untracked.Count -gt 0) { Write-Output ("--- UNTRACKED: " + ($untracked -join ', ')) }

        Write-Output '--- RECENT COMMIT STYLE (last 8) ---'
        git log --oneline -8

        # hygiene on staged + untracked
        $candidates = @(Get-StagedFiles) + $untracked | Select-Object -Unique
        foreach ($f in $candidates) {
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $size = (Get-Item -LiteralPath $f -ErrorAction SilentlyContinue).Length
            if ($size -and $size -gt 5MB) { Warn ("large file: {0} = {1:N1} MB (>5MB)" -f $f, ($size / 1MB)) }
            $sens = Test-SensitiveName ($f -replace '\\', '/')
            if ($sens) { Block ("sensitive filename: $f (matches $sens)") }
        }
        $stagedDiff = git diff --cached
        foreach ($hit in (Find-Secrets $stagedDiff)) { Block ("secret pattern in staged diff: $hit") }
        if ($stagedDiff -match '(?m)^(<{7}|>{7}) ') { Block 'conflict markers in staged diff' }
        Write-Output '=== END ANALYZE ==='
        exit 0
    }

    # ------------- COMMIT MODE -------------
    if (-not $Message -or -not $Message.Trim()) { Write-Output 'ERROR: -Message is required'; exit 2 }
    $subject = ($Message -split "`n")[0].TrimEnd()
    if ($subject.Length -gt 72) { Warn ("subject is $($subject.Length) chars (>72)") }
    if ($subject -notmatch '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|sync)(\([a-z0-9._-]+\))?: \S') {
        Warn 'subject does not match conventional-commit pattern type(scope): subject'
    }

    if (-not $identityOk) { Write-Output "ERROR: git identity missing (user.name='$userName' user.email='$userEmail')"; exit 2 }

    # staging decision
    if ($Files.Count -gt 0) {
        foreach ($f in $Files) {
            git add -- $f
            if ($LASTEXITCODE -ne 0) { Write-Output "ERROR: git add failed for: $f"; exit 2 }
        }
    }
    elseif ($StagedOnly) { <# use index as-is #> }
    else {
        Write-Output 'ERROR: refusing blind commit - pass explicit -Files or -StagedOnly'
        exit 2
    }

    $staged = @(Get-StagedFiles)
    if ($staged.Count -eq 0) { Write-Output 'ERROR: nothing staged after git add'; exit 2 }

    # gates on staged set
    foreach ($f in $staged) {
        $sens = Test-SensitiveName ($f -replace '\\', '/')
        if ($sens) { Block ("sensitive filename staged: $f (matches $sens)") }
        $size = (Get-Item -LiteralPath $f -ErrorAction SilentlyContinue).Length
        if ($size -and $size -gt 5MB) { Warn ("large staged file: {0} = {1:N1} MB" -f $f, ($size / 1MB)) }
    }

    $diff = git diff --cached
    if ($diff.Length -gt 200000) { $diff = $diff.Substring(0, 200000); Warn 'staged diff truncated at 200k chars for scanning' }
    foreach ($hit in (Find-Secrets $diff)) { Block ("secret pattern in staged diff: $hit") }
    if ($diff -match '(?m)^(<{7}|>{7}) ') { Block 'conflict markers in staged diff' }

    if ($Script:Blocks.Count -gt 0) {
        Write-Output ("ERROR: commit blocked by $($Script:Blocks.Count) gate(s) listed above")
        exit 3
    }

    # commit
    git commit -m $Message
    if ($LASTEXITCODE -ne 0) { Write-Output 'ERROR: git commit failed'; exit 2 }
    $hash = git rev-parse --short HEAD
    Write-Output "COMMITTED: $hash $subject"
    Write-Output ("FILES: " + ($staged -join ', '))

    if ($Push) {
        $branch = git branch --show-current
        git push
        if ($LASTEXITCODE -ne 0) { Write-Output 'ERROR: git push failed (commit remains local)'; exit 2 }
        $upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
        Write-Output "PUSHED: $branch -> $upstream"
    }
    exit 0
}
finally { Pop-Location }
