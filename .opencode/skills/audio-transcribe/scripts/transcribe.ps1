# MiMo-V2.5-ASR Transcription Script — real API integration
# Usage: transcribe.ps1 -InputPath "audio.wav" -OutputPath "transcript.txt" [-Language "auto"]

param(
    [Parameter(Mandatory=$true)]
    [string]$InputPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,
    
    [string]$Language = "auto"
)

$BASE_URL = "https://hcbifrost.herocraft.com/litellm/v1"

# Check API key
$apiKey = $env:LITELLM_API_KEY
if (-not $apiKey) {
    Write-Host "ERROR: LITELLM_API_KEY environment variable not set"
    exit 3
}

# Validation
if (-not (Test-Path $InputPath)) {
    Write-Host "ERROR: Input file not found: $InputPath"
    exit 3
}

# Validate input format
$ext = [System.IO.Path]::GetExtension($InputPath).ToLower()
if ($ext -notin @(".wav", ".mp3", ".m4a")) {
    Write-Host "ERROR: Unsupported input format: $ext"
    Write-Host "Supported formats: wav, mp3, m4a"
    exit 3
}

# Read audio file
$audioBytes = [System.IO.File]::ReadAllBytes($InputPath)
$audioBase64 = [Convert]::ToBase64String($audioBytes)

# Determine MIME type
$mimeType = switch ($ext) {
    ".wav" { "audio/wav" }
    ".mp3" { "audio/mpeg" }
    ".m4a" { "audio/mp4" }
    default { "audio/wav" }
}

# Build messages
if ($Language -eq "auto") {
    $userContent = ""
} else {
    $userContent = "<$Language>"
}

$messages = @(
    @{ role = "user"; content = $userContent }
)

# Build request body
$body = @{
    model = "voice/xiaomi/mimo-v2.5-asr"
    messages = $messages
    audio = @{
        url = "data:$mimeType;base64,$audioBase64"
        format = $ext.TrimStart(".")
    }
} | ConvertTo-Json -Depth 10

# Ensure output directory exists
$outputDir = Split-Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Make API call (HttpClient: works on PowerShell 5.1 and 7+, honors timeout)
Add-Type -AssemblyName System.Net.Http
$uri = "$BASE_URL/chat/completions"
$client = New-Object System.Net.Http.HttpClient
try {
    $client.Timeout = [TimeSpan]::FromSeconds(180)
    $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $apiKey)
    $httpContent = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, "application/json")
    $httpResponse = $client.PostAsync($uri, $httpContent).Result
    $responseText = $httpResponse.Content.ReadAsStringAsync().Result
    if (-not $httpResponse.IsSuccessStatusCode) {
        Write-Host "ERROR: API request failed: $([int]$httpResponse.StatusCode) $($httpResponse.ReasonPhrase)"
        Write-Host $responseText
        exit 3
    }
    $response = $responseText | ConvertFrom-Json
} catch {
    Write-Host "ERROR: API request failed: $_"
    exit 3
} finally {
    if ($client) { $client.Dispose() }
}

# Extract transcription
try {
    $transcription = $response.choices[0].message.content
    if ($null -eq $transcription) {
        throw "content missing in response"
    }
} catch {
    Write-Host "ERROR: Failed to parse API response: $_"
    exit 3
}

# Save output
[System.IO.File]::WriteAllText($OutputPath, $transcription, [System.Text.Encoding]::UTF8)

# Output
$usage = if ($response.usage) { $response.usage | ConvertTo-Json -Compress } else { "{}" }
Write-Host "STATUS: success"
Write-Host "MODEL: voice/xiaomi/mimo-v2.5-asr"
Write-Host "INPUT_PATH: $InputPath"
Write-Host "OUTPUT_PATH: $OutputPath"
Write-Host "LANGUAGE: $Language"
Write-Host "WORD_COUNT: $($transcription.Split().Count)"
Write-Host "USAGE: $usage"

exit 0
