<#
.SYNOPSIS
    Audit the bifrost-litellm provider config for issues

.DESCRIPTION
    Validates the provider config: duplicate keys, invalid limits, malformed
    modalities/options/variants. Returns severity-tagged findings.

.PARAMETER Config
    Path to opencode.json (default: ~/.config/opencode/opencode.json)

.PARAMETER Provider
    Provider name to audit (default: bifrost-litellm)

.PARAMETER Json
    Output as JSON instead of text

.OUTPUTS
    SEVERITY:/FINDING:/LOCATION: lines (or JSON if -Json)

.NOTES
    Exit codes: 0 no findings (or nit-only), 2 usage/environment error,
    3 findings at concern/blocker severity.

.EXAMPLE
    .\audit.ps1
    .\audit.ps1 -Config "C:\path\to\opencode.json"
    .\audit.ps1 -Json
#>

param(
    [string]$Config = "$env:USERPROFILE\.config\opencode\opencode.json",
    [string]$Provider = "bifrost-litellm",
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Config)) {
    Write-Output "ERROR: Config not found: $Config"
    exit 2
}

$raw = Get-Content -LiteralPath $Config -Raw

# Invalid JSON is a blocker finding (documented), not an unhandled exception.
try {
    # NB: do not name this $config — it would collide (case-insensitively) with
    # the [string]-constrained $Config parameter and be coerced back to a string.
    $cfg = $raw | ConvertFrom-Json
} catch {
    $msg = "invalid JSON: $($_.Exception.Message)"
    if ($Json) {
        @(@{ severity = "blocker"; finding = $msg; location = $Config }) | ConvertTo-Json -Depth 5
    } else {
        Write-Output "BLOCKER:${msg}:$Config"
        Write-Output "STATUS:FINDINGS (1 total)"
    }
    exit 3
}

if (-not $cfg.provider.$Provider) {
    Write-Output "ERROR: Provider $Provider not found"
    exit 2
}

$models = $cfg.provider.$Provider.models
$findings = New-Object System.Collections.Generic.List[object]

# --- Check 1: duplicate keys (raw-text scan; ConvertFrom-Json deduplicates) ---
function Get-DuplicateKeys {
    param([string]$Text)

    $dups = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Stack
    $i = 0
    $n = $Text.Length
    $pendingKey = $null

    while ($i -lt $n) {
        $c = $Text[$i]

        if ($c -eq '"') {
            $sb = New-Object System.Text.StringBuilder
            $i++
            while ($i -lt $n) {
                $ch = $Text[$i]
                if ($ch -eq '\') {
                    [void]$sb.Append($ch)
                    $i++
                    if ($i -lt $n) { [void]$sb.Append($Text[$i]); $i++ }
                    continue
                }
                if ($ch -eq '"') { break }
                [void]$sb.Append($ch)
                $i++
            }
            $str = $sb.ToString()

            # A string followed by ':' is an object key.
            $j = $i + 1
            while ($j -lt $n -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
            if ($j -lt $n -and $Text[$j] -eq ':' -and $stack.Count -gt 0) {
                $frame = $stack.Peek()
                if ($frame.Keys.Contains($str)) {
                    $names = @($stack.ToArray() | ForEach-Object { $_.Name } | Where-Object { $_ })
                    [array]::Reverse($names)
                    $path = if ($names.Count -gt 0) { $names -join '.' } else { '<root>' }
                    $dups.Add(@{ name = $str; path = $path })
                } else {
                    [void]$frame.Keys.Add($str)
                }
                $pendingKey = $str
            }
            $i++
            continue
        }

        if ($c -eq '{') {
            $stack.Push(@{ Name = $pendingKey; Keys = (New-Object 'System.Collections.Generic.HashSet[string]') })
            $pendingKey = $null
            $i++
            continue
        }

        if ($c -eq '}') {
            if ($stack.Count -gt 0) { [void]$stack.Pop() }
            $pendingKey = $null
            $i++
            continue
        }

        $i++
    }

    return $dups
}

foreach ($dup in (Get-DuplicateKeys $raw)) {
    $findings.Add(@{
        severity = "concern"
        finding = "duplicate key: $($dup.name)"
        location = $dup.path
    })
}

# --- Check 2: per-model validation ---------------------------------------
$validInputs = @("text", "image", "audio", "video")
$validEfforts = @("low", "medium", "high", "max")

foreach ($key in $models.PSObject.Properties.Name) {
    $model = $models.$key

    # Check limit
    if (-not $model.limit) {
        $findings.Add(@{
            severity = "blocker"
            finding = "missing limit"
            location = $key
        })
        continue
    }

    if ($null -ne $model.limit.context -and [long]$model.limit.context -lt 0) {
        $findings.Add(@{
            severity = "concern"
            finding = "invalid limit.context (< 0)"
            location = $key
        })
    }

    if ($null -ne $model.limit.output -and [long]$model.limit.output -lt 0) {
        $findings.Add(@{
            severity = "concern"
            finding = "invalid limit.output (< 0)"
            location = $key
        })
    }

    # context=0 is non-conventional except for placeholder models -> nit
    if ($null -ne $model.limit.context -and [long]$model.limit.context -eq 0 -and $key -notmatch 'placeholder') {
        $findings.Add(@{
            severity = "nit"
            finding = "non-conventional limit.context=0"
            location = $key
        })
    }

    # Check modalities
    if ($model.modalities) {
        if ($model.modalities.input) {
            foreach ($input in $model.modalities.input) {
                if ($input -notin $validInputs) {
                    $findings.Add(@{
                        severity = "concern"
                        finding = "invalid modalities.input value: $input"
                        location = $key
                    })
                }
            }
        }

        if ($model.modalities.output) {
            foreach ($output in $model.modalities.output) {
                if ($output -notin $validInputs) {
                    $findings.Add(@{
                        severity = "concern"
                        finding = "invalid modalities.output value: $output"
                        location = $key
                    })
                }
            }
        }
    }

    # Check options.reasoningEffort
    if ($model.options -and $model.options.reasoningEffort) {
        if ($model.options.reasoningEffort -notin $validEfforts) {
            $findings.Add(@{
                severity = "concern"
                finding = "invalid options.reasoningEffort: $($model.options.reasoningEffort)"
                location = $key
            })
        }
    }

    # Check options.thinking (legacy)
    if ($model.options -and $model.options.thinking) {
        $findings.Add(@{
            severity = "nit"
            finding = "legacy options.thinking (migrate to reasoningEffort+variants)"
            location = $key
        })
    }

    # Check variants
    if ($model.variants) {
        foreach ($variantKey in $model.variants.PSObject.Properties.Name) {
            $variant = $model.variants.$variantKey
            if (-not $variant.reasoningEffort) {
                $findings.Add(@{
                    severity = "concern"
                    finding = "variant $variantKey missing reasoningEffort"
                    location = $key
                })
            }
        }
    }

    # Check attachment
    if ($model.PSObject.Properties.Name -contains "attachment") {
        if ($model.attachment -isnot [bool]) {
            $findings.Add(@{
                severity = "concern"
                finding = "attachment is not boolean"
                location = $key
            })
        }
    }
}

# --- Output --------------------------------------------------------------
if ($Json) {
    @($findings) | ConvertTo-Json -Depth 5
} else {
    foreach ($finding in $findings) {
        Write-Output "$($finding.severity.ToUpper()):$($finding.finding):$($finding.location)"
    }

    if ($findings.Count -eq 0) {
        Write-Output "STATUS:OK (no findings)"
    } else {
        Write-Output "STATUS:FINDINGS ($($findings.Count) total)"
    }
}

# Exit 3 when any concern/blocker finding exists (nit-only stays 0).
$gating = @($findings | Where-Object { $_.severity -ne 'nit' }).Count
if ($gating -gt 0) { exit 3 }
exit 0