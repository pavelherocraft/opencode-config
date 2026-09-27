# Global Rules

Применяются во ВСЕХ проектах и сессиях. Специфика проекта — в ARCHITECTURE.md корня проекта (если есть).

## Git Commits — HARD RULE

**НИКОГДА не выполняй `git commit`, `git push`, `git tag` сам. ВСЕГДА делегируй агенту `git-commit` через Task tool (subagent_type: "git-commit"). Без исключений.**
- Прямые git commit/push заблокированы permissions для всех, кроме агента git-commit. Отказ в правах = сигнал делегировать через task, не обходить
- Push передавай только если пользователь явно попросил
- Если task tool недоступен — скажи пользователю, не коммить вручную

## Media Generation — HARD RULE

**Генерация изображений/видео/речи — ТОЛЬКО через профильных субагентов** (image-creator, video-generator, voice-synthesizer, voice-clone, voice-transcriber) через Task tool. Не вызывай медиа-API напрямую и не генерируй сам.

## Image Analysis

Анализ изображений — только агент `view-image` через Task tool (subagent_type: "view-image").

## MCP Tools Rules

### Search
Всегда `zai_web_search` (tool: zai_web_search_web_search_prime) для веб-поиска. НЕ webfetch. Запросы — на английском.

### Read URLs
Всегда `zai_web_reader` для чтения URL. НЕ webfetch.

### GitHub
Всегда `zai_zread` инструменты (search_doc, read_file, get_repo_structure) для GitHub-репозиториев и опенсорс-документации.

## Serena MCP Rules

Serena-инструменты ПЕРВИЧНЫ для кодовых операций (find_symbol, find_referencing_symbols, get_symbols_overview, rename_symbol, safe_delete_symbol, replace_symbol_body, insert_after/before_symbol). Встроенные grep/read/edit — вторичны, только при отказе Serena или для текстовых паттернов.

## unity-mcp Rules

Для Unity-проектов — ВСЕГДА unity-mcp (CoplayDev) инструменты МАКСИМАЛЬНО: manage_gameobject, manage_scene, create_script, manage_script, manage_asset, read_console и др. Встроенные edit/write/bash для Unity-операций НЕ использовать (только если unity-mcp недоступен).

## Per-Audience Context Files

`REVIEW_CONTEXT.md` (корень проекта + user-level) — инструкции ТОЛЬКО для reviewer-агентов. Исполнительные агенты не читают.
