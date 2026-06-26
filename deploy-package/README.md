# Пакет развёртывания OpenCode Agent Orchestration

## Что это за пакет

Это полный пакет конфигурации для системы оркестрации агентов OpenCode. Он содержит все необходимые файлы для развёртывания системы с двумя primary-агентами (orchestrator и plankestrator), 30 subagents, плагином принудительного контроля рабочих процессов и интеграцией с MCP-серверами.

## Структура папок

```
deploy-package/
├── README.md                          # Этот файл
├── DEPLOYMENT_GUIDE.md                # Пошаговая инструкция установки
├── opencode.json                      # Главная конфигурация (провайдеры, MCP, агенты)
├── agents/                            # Определения 32 агентов
│   ├── orchestrator.md                # Primary agent (BUGFIX/DEVOPS/DEV/DOCS)
│   ├── plankestrator.md               # Primary agent (PLAN/RESEARCH/RESEARCH+PLAN)
│   ├── worker.md                      # Implementation agent
│   ├── bugfix.md                      # Bug fix agent
│   ├── ...                            # Ещё 28 агентов
│   └── view-image.md                  # Image analysis agent
├── plugins/                           # Плагины
│   ├── workflow-enforcement.ts        # Плагин контроля рабочих процессов
│   └── package.json                   # Зависимости плагина
├── project-files/                     # Файлы проекта (копировать в корень проекта)
│   ├── AGENTS.md                      # Правила проекта
│   ├── ARCHITECTURE.md                # Требования к архитектуре
│   ├── PLUGIN.md                      # Документация плагина
│   └── MCP_SETUP.md                   # Руководство по настройке MCP
└── scripts/                           # Скрипты автоматизации
    ├── install.ps1                    # Автоматическая установка
    └── verify.ps1                     # Проверка установки
```

## Быстрый старт

### 1. Автоматическая установка (рекомендуется)

```powershell
cd deploy-package
.\scripts\install.ps1
```

### 2. Ручная установка

```powershell
# Скопировать opencode.json
Copy-Item opencode.json "$env:USERPROFILE\.config\opencode\opencode.json"

# Скопировать агентов
Copy-Item agents\*.md "$env:USERPROFILE\.config\opencode\agents\" -Force

# Скопировать плагин
Copy-Item plugins\*.* "$env:USERPROFILE\.config\opencode\plugins\" -Force

# Скопировать файлы проекта в корень вашего проекта
Copy-Item project-files\*.md "C:\path\to\your\project\" -Force
```

### 3. Настроить API ключ

```powershell
[Environment]::SetEnvironmentVariable("LITELLM_API_KEY", "your-api-key", "User")
```

### 4. Проверить установку

```powershell
.\scripts\verify.ps1
```

## Требования

| Программное обеспечение | Версия | Назначение |
|-------------------------|--------|------------|
| Node.js | 18+ | Среда выполнения плагинов |
| OpenCode CLI | Последняя | Оркестрация агентов |
| Git | 2.x | Операции с репозиторием |
| Python | 3.10+ | MCP-сервер Serena |
| uv | Последняя | Менеджер пакетов Python (для Serena) |

### Опционально (для Unity проектов)

| Программное обеспечение | Версия | Назначение |
|-------------------------|--------|------------|
| Unity Editor | 2021.3 LTS+ | Хост MCP-сервера Unity |
| unity-mcp package | Последняя | Интеграция Unity MCP |

## Агенты (32 файла)

### Primary агенты (2)

| Агент | Роль | Модели |
|-------|------|--------|
| orchestrator | Операционные задачи: BUGFIX, DEVOPS, DEV, DOCS | QWEN3.7-plus |
| plankestrator | Планирование и исследования: PLAN, RESEARCH, RESEARCH+PLAN | QWEN3.7-plus |

### Subagents (30)

Включают: worker, bugfix, execute-bug, dev-planner, dev-professor, dev-reviewer, rework, consistency-checker, utility, docs-writer, docs-planner, mcp-github, mcp-read, mcp-search, summarizer, devops-agent, devops-reviewer, devops-readonly, bugfix-triage, plan-bug, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, view-image, orchestrator-identity-probe, plankestrator-identity-probe.

## MCP-серверы

| Сервер | Тип | Назначение |
|--------|-----|------------|
| zai_zread | Remote (Bifrost) | GitHub: поиск, чтение файлов, структура репо |
| zai_web_search | Remote (Bifrost) | Веб-поиск |
| zai_web_reader | Remote (Bifrost) | Чтение содержимого URL |
| serena | Local | Операции с кодовыми символами |
| unity-mcp | Remote (localhost) | Операции Unity Editor |

## Лицензия

Внутренний инструмент. Все права защищены.
