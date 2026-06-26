# Руководство по развёртыванию OpenCode Agent Orchestration

## Пошаговая инструкция установки

### Шаг 1: Установка необходимого ПО

#### Node.js (обязательно)

```powershell
# Скачать и установить Node.js 18+ с https://nodejs.org/
# Проверить установку:
node --version
```

#### OpenCode CLI (обязательно)

```powershell
npm install -g opencode
# Проверить:
opencode --version
```

#### Serena MCP Server (обязательно)

```powershell
# Скачать Serena с https://github.com/mrworkwhile/serena/releases
# Создать директорию и переместить:
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin"
Move-Item serena.exe "$env:USERPROFILE\.local\bin\serena.exe"

# Добавить в PATH (опционально):
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:USERPROFILE\.local\bin", "User")

# Проверить:
serena --version
```

#### Python и uv (для Serena)

```powershell
# Python 3.10+ с https://www.python.org/
# uv:
pip install uv
```

#### Unity MCP (опционально — только для Unity проектов)

1. Установить Unity 2021.3 LTS или новее
2. В Unity Package Manager добавить: `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main`
3. Запустить Unity Editor
4. `Window > MCP for Unity > Start Server`

---

### Шаг 2: Создание структуры директорий

```powershell
# Создать все необходимые директории:
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config\opencode"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config\opencode\agents"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config\opencode\plugins"
```

---

### Шаг 3: Копирование opencode.json

```powershell
# Копировать конфигурацию:
Copy-Item "opencode.json" "$env:USERPROFILE\.config\opencode\opencode.json" -Force
```

**ВАЖНО:** Перед копированием замените все вхождения `YOUR_API_KEY_HERE` на ваш реальный API ключ, или установите переменную окружения `LITELLM_API_KEY`.

**Путь:** `%USERPROFILE%\.config\opencode\opencode.json`

---

### Шаг 4: Копирование агентов

```powershell
# Скопировать все 32 файла агентов:
Copy-Item "agents\*.md" "$env:USERPROFILE\.config\opencode\agents\" -Force
```

**Путь:** `%USERPROFILE%\.config\opencode\agents\`

**Содержимое:** 32 файла (.md) — определения всех агентов системы.

**Проверка:**
```powershell
(Get-ChildItem "$env:USERPROFILE\.config\opencode\agents\*.md").Count
# Должно быть: 32
```

---

### Шаг 5: Копирование плагина

```powershell
# Скопировать плагин и его зависимости:
Copy-Item "plugins\workflow-enforcement.ts" "$env:USERPROFILE\.config\opencode\plugins\" -Force
Copy-Item "plugins\package.json" "$env:USERPROFILE\.config\opencode\plugins\" -Force
```

**Путь:** `%USERPROFILE%\.config\opencode\plugins\`

---

### Шаг 6: Копирование файлов проекта

```powershell
# Скопировать в корень вашего проекта:
Copy-Item "project-files\AGENTS.md" "C:\path\to\your\project\" -Force
Copy-Item "project-files\ARCHITECTURE.md" "C:\path\to\your\project\" -Force
Copy-Item "project-files\PLUGIN.md" "C:\path\to\your\project\" -Force
Copy-Item "project-files\MCP_SETUP.md" "C:\path\to\your\project\" -Force
```

---

### Шаг 7: Настройка MCP-серверов

#### Переменная окружения для API ключа

```powershell
# Установить API ключ (используется для всех LLM и MCP серверов):
[Environment]::SetEnvironmentVariable("LITELLM_API_KEY", "your-bifrost-api-key", "User")
```

Этот ключ используется для:
- **Всех LLM моделей** (все 32 агента)
- **Всех Z.AI MCP серверов** (zai_zread, zai_web_search, zai_web_reader)

#### Настройка Serena (serena MCP)

В `opencode.json` замените путь к serena.exe:

```json
"serena": {
  "type": "local",
  "command": ["C:\\Users\\<YOUR_USERNAME>\\.local\\bin\\serena.exe", "start-mcp-server", "--transport", "stdio", "--context=ide", "--project-from-cwd"],
  "enabled": true
}
```

Замените `<YOUR_USERNAME>` на ваше имя пользователя Windows.

#### Настройка Unity MCP (опционально)

Unity MCP сервер работает на `http://localhost:8080/mcp`. Убедитесь, что Unity Editor запущен с MCP сервером.

---

### Шаг 8: Проверка установки

```powershell
# Запустить скрипт проверки:
.\scripts\verify.ps1
```

Или вручную:

```powershell
# 1. Проверить opencode.json
Test-Path "$env:USERPROFILE\.config\opencode\opencode.json"

# 2. Проверить количество агентов
(Get-ChildItem "$env:USERPROFILE\.config\opencode\agents\*.md").Count

# 3. Проверить плагин
Test-Path "$env:USERPROFILE\.config\opencode\plugins\workflow-enforcement.ts"

# 4. Запустить opencode и проверить логи
opencode
# Должно появиться: "Workflow enforcement plugin initialized"
```

---

## Как настроить MCP-серверы

### Z.AI MCP серверы (через Bifrost LiteLLM)

Все три сервера автоматически настраиваются через `opencode.json`:

| Сервер | Инструменты | Назначение |
|--------|-------------|------------|
| zai_zread | `zai_zread_search_doc`, `zai_zread_read_file`, `zai_zread_get_repo_structure` | GitHub операции |
| zai_web_search | `zai_web_search_web_search_prime` | Веб-поиск |
| zai_web_reader | `zai_web_reader_webReader` | Чтение URL |

### Serena (локальный MCP)

Требует установки `serena.exe` и настройки пути в `opencode.json`.

### unity-mcp (локальный remote)

Требует запущенный Unity Editor с MCP сервером на порту 8080.

---

## Как проверить установку

### Контрольный список

- [ ] Node.js 18+ установлен
- [ ] OpenCode CLI установлен
- [ ] Serena установлен
- [ ] `LITELLM_API_KEY` установлена
- [ ] `opencode.json` скопирован в `%USERPROFILE%\.config\opencode\`
- [ ] 32 agent файла скопированы в `%USERPROFILE%\.config\opencode\agents\`
- [ ] Плагин скопирован в `%USERPROFILE%\.config\opencode\plugins\`
- [ ] Файлы проекта скопированы в корень проекта
- [ ] `opencode` запускается без ошибок
- [ ] Плагин инициализируется (лог: "Workflow enforcement plugin initialized")
- [ ] MCP инструменты доступны

### Тестовые команды

```bash
# Тест orchestrator
opencode --agent orchestrator
# Ожидается: "Workflow enforcement plugin initialized"

# Тест plankestrator
opencode --agent plankestrator
# Ожидается: "Session created — agent detected: plankestrator"
```

### Устранение проблем

| Проблема | Решение |
|----------|---------|
| Плагин не загружается | Проверить путь в opencode.json: `"plugin": ["./plugins/workflow-enforcement.ts"]` |
| MCP сервер не подключается | Проверить API ключ и URL в opencode.json |
| Serena не работает | Убедиться что serena.exe в PATH и проект открыт в IDE |
| Unity MCP не работает | Убедиться что Unity Editor запущен с MCP сервером |
| Агент вызывает не того subagent | Проверить routing tables в PLUGIN.md |
