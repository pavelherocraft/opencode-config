# REVIEW_CONTEXT.md — reviewer-only context (project level, OMP WATCHDOG.md analog)

Адресаты и severity-таксономия — см. user-level `~/.config/opencode/REVIEW_CONTEXT.md`.

## Приоритеты ревью ЭТОГО проекта
1. Синхронизация зеркал: routing tables живут в 6+ местах — plugin ×3 (live/project/deploy), ARCHITECTURE.md ×3, AGENTS.md ×3, PLUGIN.md ×3, MCP_SETUP.md ×2, orchestrator.md L26 (OPENCODE_ROUTING_TABLE), opencode.json ×2 (task-блок orchestrator). Любое изменение whitelist — во ВСЕХ местах.
2. ARCHITECTURE.md — source of truth; AGENTS.md/PLUGIN.md — routing-зеркала БЕЗ счётчиков total; MCP_SETUP.md root — актуальная копия.
3. Модели агентов — ТОЛЬКО в frontmatter agents/*.md (в opencode.json поля model нет).
4. Счётчики: whitelist 26/10, Grand Total ARCHITECTURE `**36** | **38**`, verify.ps1 «-ge 38», MCP_SETUP L43–44 (Subagents 36 / Total 38).

## Known traps
- YAML frontmatter: последовательность «: » (двоеточие+пробел) в незакавыченном description ломает парсинг (прецедент: баг gated: secrets в git-commit.md)
- Имена моделей содержат пробелы и скобки: GLM-5.3 (res), GLM-5.3-Flash (res), Kimi K3, aliyun/qwen3.8-flash — воспроизводить байт-в-байт
- Live-конфиг C:\Users\Admin\.config\opencode\ ВНЕ git; проектные plugins\ и opencode-config\ — зеркала; сверка fc /b
- Якоря в opencode.json проверять rg -c → 1 ПЕРЕД string-replace (task-блоки одинаковы у десятков агентов — якорь должен включать ключ следующего агента)
- Конфиг читается на старте сессии: изменения подхватываются только в НОВОЙ сессии
- Code fences внутри agents/*.md: проверять вложенность при правке
