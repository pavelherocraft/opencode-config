# verify.ps1 - Проверка установки OpenCode Agent Orchestration
# Usage: .\verify.ps1

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " OpenCode Installation Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configDir = "$env:USERPROFILE\.config\opencode"
$totalChecks = 0
$passedChecks = 0
$failedChecks = 0

function Test-Check {
    param(
        [string]$Name,
        [bool]$Result,
        [string]$FailMessage = ""
    )
    $script:totalChecks++
    if ($Result) {
        $script:passedChecks++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:failedChecks++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($FailMessage) {
            Write-Host "         $FailMessage" -ForegroundColor Yellow
        }
    }
}

# Check 1: Node.js
Write-Host "[Программное обеспечение]" -ForegroundColor Yellow
try {
    $nodeVersion = node --version 2>$null
    Test-Check "Node.js установлен ($nodeVersion)" ($LASTEXITCODE -eq 0)
} catch {
    Test-Check "Node.js установлен" $false "Установите Node.js 18+ с https://nodejs.org/"
}

# Check 2: OpenCode CLI
try {
    $ocVersion = opencode --version 2>$null
    Test-Check "OpenCode CLI установлен ($ocVersion)" ($LASTEXITCODE -eq 0)
} catch {
    Test-Check "OpenCode CLI установлен" $false "Установите: npm install -g opencode"
}

# Check 3: Serena
try {
    $serenaVersion = serena --version 2>$null
    Test-Check "Serena установлен ($serenaVersion)" ($LASTEXITCODE -eq 0)
} catch {
    Test-Check "Serena установлен" $false "Скачайте с https://github.com/mrworkwhile/serena/releases"
}

# Check 4: API Key
Write-Host ""
Write-Host "[Переменные окружения]" -ForegroundColor Yellow
$apiKey = [Environment]::GetEnvironmentVariable("LITELLM_API_KEY", "User")
Test-Check "LITELLM_API_KEY установлена" ($null -ne $apiKey -and $apiKey -ne "") "Установите: [Environment]::SetEnvironmentVariable('LITELLM_API_KEY', 'your-key', 'User')"

# Check 5: Directory structure
Write-Host ""
Write-Host "[Структура директорий]" -ForegroundColor Yellow
Test-Check "$configDir существует" (Test-Path $configDir)
Test-Check "$configDir\agents существует" (Test-Path "$configDir\agents")
Test-Check "$configDir\plugins существует" (Test-Path "$configDir\plugins")

# Check 6: opencode.json
Write-Host ""
Write-Host "[Конфигурация]" -ForegroundColor Yellow
$configPath = "$configDir\opencode.json"
Test-Check "opencode.json существует" (Test-Path $configPath)

if (Test-Path $configPath) {
    $configContent = Get-Content $configPath -Raw
    
    # Validate JSON
    try {
        $null = $configContent | ConvertFrom-Json
        Test-Check "opencode.json — валидный JSON" $true
    } catch {
        Test-Check "opencode.json — валидный JSON" $false "Ошибка парсинга JSON"
    }
    
    # Check for placeholder
    $hasPlaceholder = $configContent -match "YOUR_API_KEY_HERE"
    Test-Check "opencode.json — без плейсхолдеров" (-not $hasPlaceholder) "Замените YOUR_API_KEY_HERE на реальный ключ"
    
    # Check plugin reference
    $hasPlugin = $configContent -match "workflow-enforcement"
    Test-Check "opencode.json — плагин настроен" $hasPlugin "Добавьте: `'plugin`': ['./plugins/workflow-enforcement.ts']"
    
    # Check MCP servers
    $hasMCP = $configContent -match "zai_web_search" -and $configContent -match "serena"
    Test-Check "opencode.json — MCP серверы настроены" $hasMCP
}

# Check 7: Agent files
Write-Host ""
Write-Host "[Агенты]" -ForegroundColor Yellow
$agentFiles = Get-ChildItem "$configDir\agents\*.md" -ErrorAction SilentlyContinue
$agentCount = if ($agentFiles) { $agentFiles.Count } else { 0 }
Test-Check "Агенты: $agentCount/32 файлов" ($agentCount -ge 32) "Ожидается 32 файла агентов"

$requiredAgents = @(
    "orchestrator", "plankestrator", "worker", "bugfix", "utility",
    "dev-planner", "dev-professor", "dev-reviewer", "execute-bug",
    "consistency-checker", "view-image"
)
foreach ($agent in $requiredAgents) {
    $exists = Test-Path "$configDir\agents\$agent.md"
    Test-Check "  $agent.md" $exists
}

# Check 8: Plugin files
Write-Host ""
Write-Host "[Плагин]" -ForegroundColor Yellow
$pluginPath = "$configDir\plugins\workflow-enforcement.ts"
Test-Check "workflow-enforcement.ts существует" (Test-Path $pluginPath)

# Check 9: MCP configuration
Write-Host ""
Write-Host "[MCP конфигурация]" -ForegroundColor Yellow
if (Test-Path $configPath) {
    $configContent = Get-Content $configPath -Raw
    
    $mcpServers = @("zai_zread", "zai_web_search", "zai_web_reader", "serena", "unity-mcp")
    foreach ($server in $mcpServers) {
        $hasServer = $configContent -match $server
        Test-Check "MCP: $server настроен" $hasServer
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Результаты проверки" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Всего проверок: $totalChecks" -ForegroundColor White
Write-Host "  Пройдено: $passedChecks" -ForegroundColor Green
Write-Host "  Провалено: $failedChecks" -ForegroundColor $(if ($failedChecks -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failedChecks -eq 0) {
    Write-Host "  Все проверки пройдены! Установка корректна." -ForegroundColor Green
    Write-Host "  Запустите: opencode" -ForegroundColor Green
} else {
    Write-Host "  Есть проблемы. Исправьте их и запустите проверку снова." -ForegroundColor Red
    Write-Host "  См. DEPLOYMENT_GUIDE.md для инструкций." -ForegroundColor Yellow
}
Write-Host ""
