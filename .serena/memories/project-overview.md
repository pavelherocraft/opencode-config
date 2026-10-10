# Проект «Рефакторинг» (P:\Programming\Рефакторинг)

**Назначение:** конфигурационно-документационный репозиторий (git) системы оркестрации агентов OpenCode с двумя primary-агентами (orchestrator — BUGFIX/DEVOPS/DEV/DOCS; plankestrator — PLAN/RESEARCH). Кода приложения нет — только конфиги, промпты агентов, документация, планы, бэкапы. Windows.

## Модель «live ↔ repo» (с commits 704f6c5, 2026-09-28)

Раньше источником был `deploy-package/` (2946 файлов, включая node_modules) — **удалён**. Теперь:

- **Live** `C:\Users\Admin\.config\opencode\` — единственное место правок.
- **Repo** — коммитабельное зеркало для быстрого восстановления.
- Связь через скилл `config-sync` (`.opencode/skills/config-sync/scripts/sync.ps1`): `-Plan` (drift-report), `-Save` (live → repo), `-Restore` (repo → live). **5 пар:** `agents/`, `opencode.json`, `plugin`, `skills/git-commit`, `AGENTS.md ↔ AGENTS.global.md`.
- Правку конфига делаем в live, затем `config-sync -Save`. Не копируем вручную.

## Live-конфиг (ВНЕ git)

- `opencode.json` (**2336 строки**). Top-level ключи: `$schema`, `subagent_depth`, `compaction`, `attachment`, `permission`, `skills`, `provider`, `plugin`, `mcp`, `agent`, `command`, `shell`.
  - `agent` — **41 запись**, и **ни в одной нет поля `model`**: модели ТОЛЬКО во frontmatter `agents\*.md` (Permission Authority).
  - task-блоки у десятков агентов ОДИНАКОВЫ → якоря правок должны включать ключ следующего агента.
- `agents\*.md` — **41 файл** (frontmatter авторитетен).
- `plugins\workflow-enforcement.ts` — **v7** (**2989 строк**): routing tables (orchestrator 25, plankestrator 10), enforcement подавлен в субсессиях (activeTaskDepth>0), severity-валидация reviewer'ов (SEVERITY_AGENTS, warn-only, emission-guard), инъекция [CONTEXT FILE] в Task-prompt reviewer'ов (CONTEXT_FILE_AGENTS), Multi-Phase MVP (v7): optional state, валидируется только если присутствует.
- `REVIEW_CONTEXT.md` (user-level) — per-audience контекст reviewer'ов (OMP WATCHDOG.md-аналог).
- Прочее в live (НЕ наш конфиг, не трогать): `ensemble.db*`, `ensemble.json`, `instructions.md`, `package*.json`, `bun.lock`, `opencode.json.bak-*`.

## Реестр моделей (provider.bifrost-litellm)

- **66 моделей** в `bifrost-litellm`; второй провайдер `bailian-token-plan` (13 моделей).
- **7 MCP-серверов:** Johnny the Knight MCP, zai_web_reader, zai_web_search, zai_zread, serena, unity-mcp, bq. Локальные (serena/unity-mcp/bq) в paste не приходят — сохраняем вручную.
- Namespace'ы: GLM-5.3*, Kimi K*, MiniMax-M*, Qwen*, atlas*, bytedance/*, deepseek*, gemini/*, gpt-image*, gigachat/*, mimo-v2.5*, mistral/*, nvidia/*, openrouter/*, qwen3.*, seed-2.1, stepfun/*, tencent/*, voice/xiaomi/*, xiaomi/mimo-v2.6-*.
- Два паттерна reasoning: legacy `options.thinking.enabled` и новый `options.reasoningEffort` + `variants`.
- Словарь `reasoningEffort`: `low | medium | high | xhigh | max`, плюс `none` — **только** на уровне variants (вариант `off`), никогда как top-level `options.reasoningEffort`.

## Скиллы

- **Локальные** (`.opencode/skills/`, 11): agent-add, agent-model-migrate, agent-report, backup-snapshot, bifrost-config-apply, config-sync, integrity-check, model-discovery, model-key-validate, pipeline-visualize, provider-config-audit.
- **User-level** (`~/.config/opencode/skills/`): только `git-commit` (image-gen удалён в 704f6c5).
- `git-commit` имеет режим `-PushOnly` (push уже закоммиченного без нового коммита; preflight ahead/behind/diverged, никогда не force).

## Проектные доки (repo)

`ARCHITECTURE.md` (104 KB, source of truth — включая Validation C1–C6 и File Locations), `CHANGELOG.md` (41 KB), `REVIEW_CONTEXT.md`, `AGENTS.global.md` (зеркало live AGENTS.md). Исторические снимки (не обновляются): `PLAN_MULTI_PHASE_PIPELINES.md`, `PLAN_PROMPT_ENHANCEMENTS.md`, `RESEARCH_MULTI_PHASE_PIPELINES.md`, `RESEARCH_PIPELINE_ENHANCEMENTS.md`, `RESEARCH_MEDIA_MCP_UPDATES.md`, `dev_plan.md`. **Удалены** в 704f6c5: `MCP_SETUP.md`, `PLUGIN.md`, `opencode-config/`, корневой `AGENTS.md`, 22 исторических PLAN/RESEARCH-дока.

## Грабля

- Конфиг читается на старте сессии — изменения подхватываются только в НОВОЙ сессии.
- Бэкапы: `backup\<дата>_<тема>\` (есть `2026-10-01_multi_phase`, `20260927_194849_config_sync`, `py_parity_test`).
- YAML-грабля: «: » в незакавыченном `description` ломает парсинг → кавычить в одинанарные.
- Имена моделей с пробелами/скобками (`GLM-5.3 (res)`, `Kimi K3`, `nvidia/glm-5.3 (free)`) — байт-в-байт.
- MCP-URL с пробелами (`.../Johnny the Knight MCP/mcp`) работает как есть; `%20` — эквивалент (гейтвей нормализует). Проверено handshake'ом.
- Дубликат-ключ в JSON молча теряется (`qwen3.6-flash` был и в bifrost-litellm, и в bailian-token-plan с разным `name`) — правь по `"name"`, а не по ключу.
- PowerShell: `$Config` (параметр) и `$config` (локальная) — одно имя (регистр не важен) → скаляр coercion ломал скрипт. И `ConvertTo-Json` на `string[]` даёт массив кавычек, а не JSON.
