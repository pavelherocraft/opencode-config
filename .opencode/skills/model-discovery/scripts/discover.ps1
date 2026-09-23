<#
.SYNOPSIS
    Discover models in bifrost-litellm API vs config

.DESCRIPTION
    Queries the /v1/models endpoint and compares with configured models.
    Reports models in API but not in config, in config but not in API,
    and context/output limit mismatches (when the API exposes them).

.PARAMETER ApiBaseUrl
    Base URL of the API (default: https://hcbifrost.herocraft.com/litellm/v1)

.PARAMETER Config
    Path to opencode.json (default: ~/.config/opencode/opencode.json)

.PARAMETER Json
    Output as JSON instead of text

.OUTPUTS
    IN_API_NOT_CONFIG:/IN_CONFIG_NOT_API:/LIMIT_MISMATCH: lines (or JSON if -Json)

.NOTES
    Exit codes: 0 no findings, 2 usage/environment error, 3 findings present.

.EXAMPLE
    .\discover.ps1
    .\discover.ps1 -ApiBaseUrl "https://hcbifrost.herocraft.com/litellm/v1"
    .\discover.ps1 -Json
#>

param(
    [string]$ApiBaseUrl = "https://hcbifrost.herocraft.com/litellm/v1",
    [string]$Config = "$env:USERPROFILE\.config\opencode\opencode.json",
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# Check API key
if (-not $env:LITELLM_API_KEY) {
    Write-Output "ERROR: LITELLM_API_KEY env var not set"
    exit 2
}

# Check config
if (-not (Test-Path -LiteralPath $Config)) {
    Write-Output "ERROR: Config not found: $Config"
    exit 2
}

# Fetch models from API
$apiUrl = "$ApiBaseUrl/models"
$headers = @{
    "Authorization" = "Bearer $env:LITELLM_API_KEY"
    "Content-Type" = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
    $apiData = @($response.data)
} catch {
    Write-Output "ERROR: API request failed: $_"
    exit 2
}

$apiModels = @($apiData | ForEach-Object { $_.id })
$apiById = @{}
foreach ($m in $apiData) {
    if ($m.id) { $apiById[$m.id] = $m }
}

# Read config
# NB: do not name this $config — it would collide (case-insensitively) with
# the [string]-constrained $Config parameter and be coerced back to a string.
$cfg = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
$configModelMap = $cfg.provider.'bifrost-litellm'.models
$configModels = @($configModelMap.PSObject.Properties.Name)

# Resolve a numeric limit from the API model, accepting common field names.
function Get-ApiLimit($model, [string[]]$fields) {
    foreach ($f in $fields) {
        $prop = $model.PSObject.Properties[$f]
        if ($prop -and $null -ne $prop.Value) { return [long]$prop.Value }
    }
    return $null
}

# Compare membership
$inApiNotConfig = @($apiModels | Where-Object { $_ -notin $configModels })
$inConfigNotApi = @($configModels | Where-Object { $_ -notin $apiModels })

# Compare limits (only when the API exposes them)
$limitMismatches = New-Object System.Collections.Generic.List[object]
foreach ($key in $configModels) {
    if (-not $apiById.ContainsKey($key)) { continue }
    $apiModel = $apiById[$key]
    $cfgModel = $configModelMap.$key

    $cfgContext = if ($cfgModel.limit) { $cfgModel.limit.context } else { $null }
    $cfgOutput  = if ($cfgModel.limit) { $cfgModel.limit.output } else { $null }

    $apiContext = Get-ApiLimit $apiModel @('max_input_tokens', 'context_length', 'context_window')
    $apiOutput  = Get-ApiLimit $apiModel @('max_output_tokens', 'max_tokens', 'output_tokens')

    if ($null -ne $apiContext -and $null -ne $cfgContext -and [long]$apiContext -ne [long]$cfgContext) {
        $limitMismatches.Add(@{
            key = $key
            limit = "context"
            config = [long]$cfgContext
            api = [long]$apiContext
        })
    }
    if ($null -ne $apiOutput -and $null -ne $cfgOutput -and [long]$apiOutput -ne [long]$cfgOutput) {
        $limitMismatches.Add(@{
            key = $key
            limit = "output"
            config = [long]$cfgOutput
            api = [long]$apiOutput
        })
    }
}

$hasFindings = ($inApiNotConfig.Count -gt 0) -or ($inConfigNotApi.Count -gt 0) -or ($limitMismatches.Count -gt 0)

# Output
if ($Json) {
    @{
        in_api_not_config = $inApiNotConfig
        in_config_not_api = $inConfigNotApi
        limit_mismatch    = $limitMismatches
    } | ConvertTo-Json -Depth 6
} else {
    foreach ($model in $inApiNotConfig) {
        Write-Output "IN_API_NOT_CONFIG: $model"
    }

    foreach ($model in $inConfigNotApi) {
        Write-Output "IN_CONFIG_NOT_API: $model"
    }

    foreach ($m in $limitMismatches) {
        Write-Output "LIMIT_MISMATCH: $($m.key) $($m.limit) (config=$($m.config) api=$($m.api))"
    }

    if (-not $hasFindings) {
        Write-Output "STATUS:OK (config matches API)"
    } else {
        Write-Output "STATUS:FINDINGS ($($inApiNotConfig.Count) in API not config, $($inConfigNotApi.Count) in config not API, $($limitMismatches.Count) limit mismatch(es))"
    }
}

if ($hasFindings) { exit 3 }
exit 0