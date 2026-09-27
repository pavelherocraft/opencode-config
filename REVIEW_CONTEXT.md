# REVIEW_CONTEXT.md — reviewer-only context (project level, OMP WATCHDOG.md analog)

Адресаты и severity-таксономия — см. user-level `~/.config/opencode/REVIEW_CONTEXT.md`.

## Приоритеты ревью ЭТОГО проекта
1. Routing tables живут в 4 местах — live plugin `ROUTING_TABLES` (orchestrator/plankestrator), `orchestrator.md` routing line (OPENCODE_ROUTING_TABLE, ~L26), `opencode.json` task-блоки первичных агентов, ARCHITECTURE.md §1 (заголовки + строки таблиц). Любое изменение whitelist — во ВСЕХ местах.
2. ARCHITECTURE.md (корень репо) — единственный канон и source of truth; в live НЕ копируется. Правки проектных доков — только здесь.
3. Модели агентов — ТОЛЬКО в frontmatter live agents/*.md (в opencode.json поля model нет; frontmatter wins — Permission Authority).
4. Счётчики выводные: 40 агентов, whitelist 28/10, live==repo==opencode.json entries — ожидания НЕ хардкодятся (см. ARCHITECTURE §1 Routing Tables, integrity-check).
5. Sync-пары (5): live agents/ ↔ repo agents/, opencode.json, plugins/workflow-enforcement.ts, skills/git-commit/, AGENTS.md ↔ AGENTS.global.md. Правки — в LIVE; перед коммитом `config-sync --save` (repo = снапшот). Restore — только явный `config-sync --restore`.

## Known traps
- YAML frontmatter: последовательность «: » (двоеточие+пробел) в незакавыченном description ломает парсинг (прецедент: баг gated: secrets в git-commit.md)
- Имена моделей содержат пробелы и скобки: GLM-5.3 (res), GLM-5.3-Flash (res), Kimi K3, aliyun/qwen3.8-flash — воспроизводить байт-в-байт
- Live-конфиг C:\Users\Admin\.config\opencode\ ВНЕ git; репо — коммит-снапшот live; drift нормален между правками, устраняется config-sync --save
- Якоря в opencode.json проверять count→1 ПЕРЕД string-replace (task-блоки одинаковы у десятков агентов — якорь должен включать ключ следующего агента)
- opencode.json (live) с UTF-8 BOM — парсить через utf-8-sig / ConvertFrom-Json после Read-RawText
- Конфиг читается на старте сессии: изменения подхватываются только в НОВОЙ сессии
- Code fences внутри agents/*.md: проверять вложенность при правке
- consistency-checker — генерик: всё проектно-специфичное он берёт из ARCHITECTURE.md, хардкод путей/счётчиков в его промпте запрещён
