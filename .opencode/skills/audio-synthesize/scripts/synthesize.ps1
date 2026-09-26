# MiMo-V2.5-TTS Synthesis Script — real API integration
# Usage: synthesize.ps1 -Text "..." -OutputPath "..." [-Voice "mimo_default"] [-VoiceDescription "..."] [-ReferenceAudio "..."] [-Format "wav"] [-Model "..."]
# Model is auto-selected by mode: standard -> voice/xiaomi/mimo-v2.5-tts, clone -> voice/xiaomi/mimo-v2.5-tts-voiceclone, design -> voice/xiaomi/mimo-v2.5-tts-voicedesign

param(
    [Parameter(Mandatory=$true)]
    [string]$Text,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,
    
    [string]$Voice = "mimo_default",
    [string]$VoiceDescription,
    [string]$ReferenceAudio,
    [string]$Format = "wav",
    [string]$Model
)

$BASE_URL = "https://hcbifrost.herocraft.com/litellm/v1"

# Check API key
$apiKey = $env:LITELLM_API_KEY
if (-not $apiKey) {
    Write-Host "ERROR: LITELLM_API_KEY environment variable not set"
    exit 3
}

# Validation
if ($Text.Length -gt 5000) {
    Write-Host "ERROR: Text exceeds 5000 character limit"
    exit 3
}

# Determine mode and model
if ($ReferenceAudio) {
    $Mode = "clone"
    if (-not (Test-Path $ReferenceAudio)) {
        Write-Host "ERROR: Reference audio not found: $ReferenceAudio"
        exit 3
    }
    $Model = if ($Model) { $Model } else { "voice/xiaomi/mimo-v2.5-tts-voiceclone" }
} elseif ($VoiceDescription) {
    $Mode = "design"
    if ($VoiceDescription.Length -lt 10) {
        Write-Host "ERROR: Voice description must be at least 10 characters"
        exit 3
    }
    $Model = if ($Model) { $Model } else { "voice/xiaomi/mimo-v2.5-tts-voicedesign" }
} else {
    $Mode = "standard"
    $Model = if ($Model) { $Model } else { "voice/xiaomi/mimo-v2.5-tts" }
}

# Build messages
if ($Mode -eq "design") {
    $userContent = $VoiceDescription
} elseif ($Mode -eq "clone") {
    $userContent = "Clone the voice from the provided reference audio. Text to synthesize: $Text"
} else {
    $userContent = "Synthesize the following text with voice '$Voice'."
}

$messages = @(
    @{ role = "user"; content = $userContent },
    @{ role = "assistant"; content = $Text }
)

# Build request body
$body = @{
    model = $Model
    messages = $messages
    audio = @{
        voice = $Voice
        format = $Format
    }
} | ConvertTo-Json -Depth 10

# Ensure output directory exists
$outputDir = Split-Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Clone mode caveat
if ($Mode -eq "clone") {
    Write-Host "WARNING: Voice clone mode — reference audio path included in prompt"
    Write-Host "  Reference: $ReferenceAudio"
    Write-Host "  (API parameter for reference audio not yet documented)"
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

# Extract audio
try {
    $audioData = $response.choices[0].message.audio.data
    if (-not $audioData) {
        throw "audio.data missing in response"
    }
    $rawBytes = [Convert]::FromBase64String($audioData)
} catch {
    Write-Host "ERROR: Failed to parse API response: $_"
    exit 3
}

# Save audio
[System.IO.File]::WriteAllBytes($OutputPath, $rawBytes)

# Output
$usage = if ($response.usage) { $response.usage | ConvertTo-Json -Compress } else { "{}" }
Write-Host "STATUS: success"
Write-Host "MODE: $Mode"
Write-Host "MODEL: $Model"
Write-Host "OUTPUT_PATH: $OutputPath"
Write-Host "SIZE_BYTES: $($rawBytes.Length)"
Write-Host "FORMAT: $Format"
Write-Host "USAGE: $usage"

exit 0
