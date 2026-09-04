# Generate or edit an image via the Bifrost LiteLLM gateway.
# Routes by model:
#   gemini/*    -> POST /chat/completions (modalities: text+image)
#   gpt-image-* -> POST /images/generations (or /images/edits in edit mode)
#   edit mode   -> POST /images/edits (multipart, any model)
# Prints one line per saved file: SAVED: <path> (<bytes> bytes)

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Prompt,

    [string]$Model = $env:BIFROST_IMAGE_MODEL,
    [string]$BaseUrl = $env:BIFROST_BASE_URL,
    [ValidateSet('generate', 'edit')]
    [string]$Mode = 'generate',
    [string]$InputPath,
    [string]$OutDir = './generated-images',
    [string]$Name,
    [string]$Size = '1024x1024',
    [int]$MaxInputSizeKb = 300
)

$ErrorActionPreference = 'Stop'

if (-not $Model)   { $Model = 'gemini/gemini-3.1-flash-image' }
if (-not $BaseUrl) { $BaseUrl = 'https://hcbifrost.herocraft.com/litellm/v1' }
$ApiKey = $env:LITELLM_API_KEY
if (-not $ApiKey) { $ApiKey = $env:BIFROST_API_KEY }
if (-not $ApiKey) { $ApiKey = $env:OPENAI_API_KEY }
if (-not $ApiKey) { throw 'Set LITELLM_API_KEY (or BIFROST_API_KEY / OPENAI_API_KEY).' }

function Get-Slug([string]$Text, [int]$MaxLen = 40) {
    $s = ($Text.ToLower() -replace '[^a-z0-9]+', '_').Trim('_')
    if (-not $s) { $s = 'image' }
    if ($s.Length -gt $MaxLen) { $s = $s.Substring(0, $MaxLen) }
    return $s
}

function Compress-InputImage([string]$Path) {
    $origSize = (Get-Item -LiteralPath $Path).Length
    if ($origSize -le ($MaxInputSizeKb * 1024)) { return $Path }

    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Path).Path)
    $ratio = [Math]::Min([double](1024 / $img.Width), [double](1024 / $img.Height))
    if ($ratio -gt 1.0) { $ratio = 1.0 }
    $newW = [int][Math]::Max(1, $img.Width * $ratio)
    $newH = [int][Math]::Max(1, $img.Height * $ratio)
    $bmp = New-Object System.Drawing.Bitmap $newW, $newH
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, 0, 0, $newW, $newH)
    $g.Dispose(); $img.Dispose()

    $tmp = Join-Path $env:TEMP ("imagegen-input-" + [Guid]::NewGuid().ToString('N') + '.jpg')
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $encParams = New-Object System.Drawing.Imaging.EncoderParameters 1
    $quality = 80
    $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$quality)
    do {
        $bmp.Save($tmp, $codec, $encParams)
        if ((Get-Item -LiteralPath $tmp).Length -le ($MaxInputSizeKb * 1024)) { break }
        $quality -= 10
        if ($quality -lt 30) { break }
        $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$quality)
    } while ($true)
    $bmp.Dispose()
    return $tmp
}

function Save-FromB64([string]$B64, [string]$OutFile) {
    [System.IO.File]::WriteAllBytes($OutFile, [Convert]::FromBase64String($B64))
}

# Resolve edit-mode source
$srcImage = $null
if ($Mode -eq 'edit') {
    if (-not $InputPath) { throw 'Edit mode requires -InputPath <path-to-image>' }
    if (-not (Test-Path -LiteralPath $InputPath)) { throw "Input not found: $InputPath" }
    $srcImage = Compress-InputImage $InputPath
}

# Output path (extension for gemini path is finalized after MIME is known)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$slug = if ($Name) { Get-Slug $Name } else { Get-Slug $Prompt }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$ext = if ($Mode -eq 'edit' -or $Model -like 'gpt-image*') { 'png' } else { 'jpg' }
$outFile = Join-Path $OutDir "$($timestamp)_$($slug).$ext"

$api = $BaseUrl.TrimEnd('/')

if ($Mode -eq 'edit') {
    # multipart POST /images/edits
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(180)
    $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $ApiKey)

    $content = New-Object System.Net.Http.MultipartFormDataContent
    $imgBytes = [System.IO.File]::ReadAllBytes($srcImage)
    $imgC = New-Object System.Net.Http.ByteArrayContent (,$imgBytes)
    $imgC.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('image/png')
    $content.Add($imgC, 'image', [System.IO.Path]::GetFileName($srcImage))
    $content.Add((New-Object System.Net.Http.StringContent $Prompt), 'prompt')
    $content.Add((New-Object System.Net.Http.StringContent $Model), 'model')
    $content.Add((New-Object System.Net.Http.StringContent '1'), 'n')
    if ($Size) { $content.Add((New-Object System.Net.Http.StringContent $Size), 'size') }

    $resp = $client.PostAsync("$api/images/edits", $content).Result
    if (-not $resp.IsSuccessStatusCode) {
        $body = $resp.Content.ReadAsStringAsync().Result
        throw "HTTP $([int]$resp.StatusCode): $($body.Substring(0, [Math]::Min(1000, $body.Length)))"
    }
    $obj = $resp.Content.ReadAsStringAsync().Result | ConvertFrom-Json
    $b64 = $obj.data[0].b64_json
    if (-not $b64) { throw 'No b64_json in edit response' }
    Save-FromB64 $b64 $outFile
}
elseif ($Model -like 'gpt-image*' -or $Model -like '*dall-e*') {
    # POST /images/generations
    $body = @{ model = $Model; prompt = $Prompt; size = $Size; n = 1 } | ConvertTo-Json
    $resp = Invoke-RestMethod -Uri "$api/images/generations" -Method Post `
        -Headers @{ Authorization = "Bearer $ApiKey" } `
        -ContentType 'application/json' -Body $body -TimeoutSec 180
    $b64 = $resp.data[0].b64_json
    if (-not $b64) { throw 'No b64_json in response' }
    Save-FromB64 $b64 $outFile
}
else {
    # gemini path: POST /chat/completions with modalities
    $body = @{
        model      = $Model
        messages   = @(@{ role = 'user'; content = $Prompt })
        modalities = @('text', 'image')
    } | ConvertTo-Json -Depth 5
    $resp = Invoke-RestMethod -Uri "$api/chat/completions" -Method Post `
        -Headers @{ Authorization = "Bearer $ApiKey" } `
        -ContentType 'application/json' -Body $body -TimeoutSec 180

    $imgs = @($resp.choices[0].message.images)
    if (-not $imgs -or $imgs.Count -eq 0) { throw 'No image in response (refusal or safety block)' }
    $dataUri = $imgs[0].image_url.url
    if (-not $dataUri -or -not $dataUri.StartsWith('data:')) { throw 'Unexpected image payload' }
    $parts = $dataUri -split ',', 2
    $b64 = $parts[1]
    $mime = $parts[0].Substring(5).Split(';')[0]
    # derive extension from the ACTUAL mime and rebuild the output path
    $realExt = 'png'
    if ($mime -match 'jpeg|jpg') { $realExt = 'jpg' }
    elseif ($mime -match 'webp') { $realExt = 'webp' }
    $outFile = Join-Path $OutDir "$($timestamp)_$($slug).$realExt"
    Save-FromB64 $b64 $outFile
}

if ((Test-Path -LiteralPath $outFile) -and (Get-Item -LiteralPath $outFile).Length -gt 0) {
    Write-Output "SAVED: $((Resolve-Path -LiteralPath $outFile).Path) ($((Get-Item -LiteralPath $outFile).Length) bytes)"
}
else { throw "Save verification failed: $outFile" }
