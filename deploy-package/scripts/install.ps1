# install.ps1 - Автоматическая установка OpenCode Agent Orchestration
# Usage: .\install.ps1 [-ProjectPath "C:\path\to\project"]

param(
    [string]$ProjectPath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " OpenCode Agent Orchestration Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$packageDir = Split-Path -Parent $scriptDir
$configDir = "$env:USERPROFILE\.config\opencode"

# Step 1: Create directories
Write-Host "[1/6] Создание директорий..." -ForegroundColor Yellow
$dirs = @(
    "$configDir",
    "$configDir\agents",
    "$configDir\plugins"
)
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-Host "  Создано: $dir" -ForegroundColor Green
    } else {
        Write-Host "  Существует: $dir" -ForegroundColor DarkGray
    }
}

# Step 2: Copy opencode.json
Write-Host ""
Write-Host "[2/6] Копирование opencode.json..." -ForegroundColor Yellow
$sourceConfig = Join-Path $packageDir "opencode.json"
$destConfig = Join-Path $configDir "opencode.json"

if (Test-Path $sourceConfig) {
    Copy-Item $sourceConfig $destConfig -Force
    Write-Host "  Скопировано: $destConfig" -ForegroundColor Green
} else {
    Write-Host "  ОШИБКА: Файл не найден: $sourceConfig" -ForegroundColor Red
    exit 1
}

# Step 3: Copy agent files
Write-Host ""
Write-Host "[3/6] Копирование агентов..." -ForegroundColor Yellow
$agentsSource = Join-Path $packageDir "agents"
$agentsDest = Join-Path $configDir "agents"

if (Test-Path $agentsSource) {
    $agentFiles = Get-ChildItem -Path $agentsSource -Filter "*.md"
    Copy-Item "$agentsSource\*.md" $agentsDest -Force
    Write-Host "  Скопировано $($agentFiles.Count) файлов агентов" -ForegroundColor Green
} else {
    Write-Host "  ОШИБКА: Директория не найдена: $agentsSource" -ForegroundColor Red
    exit 1
}

# Step 4: Copy plugin files
Write-Host ""
Write-Host "[4/6] Копирование плагина..." -ForegroundColor Yellow
$pluginSource = Join-Path $packageDir "plugins"
$pluginDest = Join-Path $configDir "plugins"

if (Test-Path $pluginSource) {
    Copy-Item "$pluginSource\*" $pluginDest -Force -Recurse
    $pluginFiles = Get-ChildItem -Path $pluginDest
    Write-Host "  Скопировано $($pluginFiles.Count) файлов плагина" -ForegroundColor Green
} else {
    Write-Host "  ОШИБКА: Директория не найдена: $pluginSource" -ForegroundColor Red
    exit 1
}

# Step 5: Copy project files
Write-Host ""
Write-Host "[5/6] Копирование файлов проекта..." -ForegroundColor Yellow

if ($ProjectPath -eq "") {
    Write-Host "  Пропуск: -ProjectPath не указан." -ForegroundColor DarkGray
    Write-Host "  Скопируйте файлы из project-files\ вручную в корень вашего проекта:" -ForegroundColor DarkGray
    Write-Host "    - AGENTS.md" -ForegroundColor DarkGray
    Write-Host "    - ARCHITECTURE.md" -ForegroundColor DarkGray
    Write-Host "    - PLUGIN.md" -ForegroundColor DarkGray
    Write-Host "    - MCP_SETUP.md" -ForegroundColor DarkGray
} else {
    $projectFilesSource = Join-Path $packageDir "project-files"
    if (Test-Path $projectFilesSource) {
        $projectFiles = Get-ChildItem -Path $projectFilesSource -Filter "*.md"
        foreach ($file in $projectFiles) {
            Copy-Item $file.FullName $ProjectPath -Force
            Write-Host "  Скопировано: $($file.Name) -> $ProjectPath" -ForegroundColor Green
        }
    } else {
        Write-Host "  ОШИБКА: Директория не найдена: $projectFilesSource" -ForegroundColor Red
    }
}

# Step 6: Check API key
Write-Host ""
Write-Host "[6/6] Проверка API ключа..." -ForegroundColor Yellow
$apiKey = [Environment]::GetEnvironmentVariable("LITELLM_API_KEY", "User")
if ($apiKey) {
    Write-Host "  LITELLM_API_KEY установлена" -ForegroundColor Green
} else {
    Write-Host "  ВНИМАНИЕ: LITELLM_API_KEY не установлена!" -ForegroundColor Red
    Write-Host "  Установите: [Environment]::SetEnvironmentVariable('LITELLM_API_KEY', 'your-key', 'User')" -ForegroundColor Yellow
}

# Check for placeholder in opencode.json
$configContent = Get-Content $destConfig -Raw
if ($configContent -match "YOUR_API_KEY_HERE") {
    Write-Host ""
    Write-Host "  ВНИМАНИЕ: opencode.json содержит плейсхолдер YOUR_API_KEY_HERE" -ForegroundColor Yellow
    Write-Host "  Замените на ваш реальный API ключ или установите переменную LITELLM_API_KEY" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Установка завершена!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Следующие шаги:" -ForegroundColor White
Write-Host " 1. Установите LITELLM_API_KEY (если ещё не установлен)" -ForegroundColor White
Write-Host " 2. Скопируйте project-files\ в корень вашего проекта" -ForegroundColor White
Write-Host " 3. Настройте путь к serena.exe в opencode.json" -ForegroundColor White
Write-Host " 4. Запустите: opencode" -ForegroundColor White
Write-Host " 5. Проверьте: .\scripts\verify.ps1" -ForegroundColor White
Write-Host ""
