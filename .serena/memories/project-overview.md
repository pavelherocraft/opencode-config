# Проект «Рефакторинг» (P:\Programming\Рефакторинг)

**Назначение:** конфигурационно-документационный репозиторий (git) системы оркестрации агентов OpenCode с двумя primary-агентами (orchestrator — BUGFIX/DEVOPS/DEV/DOCS; plankestrator — PLAN/RESEARCH). Кода приложения нет — только конфиги, промпты агентов, документация, планы, бэкапы. Windows.

**Live-конфиг (ВНЕ git):** `C:\Users\Admin\.config\opencode\`
- `opencode.json` (1684 строки): секции всех агентов; НЕТ поля model (модели ТОЛЬКО во frontmatter .md — Permission Authority); task-блоки ОДИНАКОВЫ у десятков агентов → якоря правок должны включать ключ следующего агента.
- `agents\*.md` — 37 файлов (36 старых + advisor.md; frontmatter авторитетен).
- `plugins\workflow-enforcement.ts` — **v5** (1443 строки): routing tables (orchestrator 25, plankestrator 10), enforcement подавлен в субсессиях (activeTaskDepth>0), severity-валидация reviewer'ов (SEVERITY_AGENTS, warn-only, emission-guard: дедуп seenFindings + фильтр пустых фраз + бюджет 4 non-blocker/update), инъекция [CONTEXT FILE] в Task-prompt reviewer'ов (CONTEXT_FILE_AGENTS).
- `REVIEW_CONTEXT.md` (user-level) — per-audience контекст reviewer'ов (OMP WATCHDOG.md-аналог).

**Счётчики (после OMP P0+P1, 2026-09-21):** whitelist orchestrator **25** (+advisor)/plankestrator 10, сумма записей 35 (view-image shared), уникальных субагентов 35, total **37**, agent-файлов 37. Grand Total ARCHITECTURE: `**35** | **37**`. Subagent Models: 35 строк (+advisor/Kimi K3; plan-bug=qwen3.8-max, execute-bug=MiniMax-M3 — prewalk-инверсия). consistency-checker: **11 checks** (+Check 11 Model Role Compliance). verify.ps1: `-ge 37`.

**Ключевые изменения v5 (PLAN_OMP_P0_P1.md, 2026-09-21, бэкап `backup/2026-09-21_omp_p0p1/phase0/`):**
- P0-1 severity-таксономия: `severity: nit|concern|blocker` в JSON dev-reviewer/consistency-checker/advisor; nit→rework skip, concern→rework, blocker→⚠️ triggered turn; missing=concern (fail-closed).
- P0-2 prewalk: plan-bug (qwen3.8-max, strong) → execute-bug (MiniMax-M3, cheap); контракт self-contained bug_plan.md; escape hatch `plan_gap: true`.
- P0-3 REVIEW_CONTEXT.md ×2 (project root + user-level); секции CONTEXT FILE в 6 reviewer-промптах + advisor.
- P1-1 advisor-агент (Kimi K3, строго read-only, task:deny): DEV COMPLEX и BUGFIX DEEP после исполнителя до dev-reviewer; NIT_ONLY_MODE (immuneTurns=3) после blocker.
- P1-2 Model Roles: ARCHITECTURE §Model Roles (13 ролей → 37 агентов, single source of truth; prewalk-принцип tier(planner) ≥ tier(executor); role-алиасы ЗАБЛОКИРОВАНЫ до поддержки рантаймом).

**Новые секции ARCHITECTURE.md:** Model Roles, Reviewer Severity Field (§3), Advisor Step (§2), Per-Audience Context Files (§8).

**Проектные доки:** `ARCHITECTURE.md` (source of truth; копии `opencode-config\` + `deploy-package\project-files\` — синхронны), `AGENTS.md`/`PLUGIN.md` (routing-зеркала ×3; PLUGIN.md копии исторически НЕ идентичны — правки по текстовым якорям), `MCP_SETUP.md` ×2 (root + deploy; Subagents 35/Total 37), `CHANGELOG.md` ([Unreleased] — 5 записей OMP P0-1..P1-2), `REVIEW_CONTEXT.md` (project-level), `deploy-package\` (agents\ — 37 snapshots; opencode.json — зеркало live; verify.ps1 `-ge 37`, requiredAgents +advisor).

**SUPERCOMPLEX step iteration (2026-09-21, бэкап `backup/2026-09-21_supercomplex_step_iteration/`):** orchestrator.md имеет секцию SUPERCOMPLEX PIPELINE (3 стадии): Stage 1 — определение списка шагов (приоритет: явный список пользователя → заголовки research-файла (`## P0-1`, `## Phase 1`, `## Шаг 1`) через classification read / ОДИН вызов mcp-read → dev-planner `MODE: DECOMPOSITION` возвращает JSON {decomposition, steps[]} БЕЗ записи dev_plan.md); Stage 2 — per-step цикл dev-planner (пишет dev_plan.md для шага) → dev-professor → dev-reviewer → consistency-checker → [rework ×3] → utility; Stage 3 — завершение. ВАЖНО: devops-readonly НЕ вызывается из orchestrator (он в whitelist plankestrator) — используется mcp-read. dev-planner.md имеет Operating Modes (Mode 1 DECOMPOSITION / Mode 2 detailed). Live ARCHITECTURE.md в ~/.config/opencode расходится с корневой группой в Model Roles (plan-bug=qwen3.8-max/Kimi K3 vs frontmatter-корректных GLM-5.3 (res)/HY4 в корне) — предсуществующее расхождение, SUPERCOMPLEX-секция синхронизирована.

**Ключевые планы:** `PLAN_OMP_IMPLEMENTATION.md` (Phases 0–5, scout), `PLAN_OMP_P0_P1.md` (Phases 0–6 — ИСПОЛНЕН 2026-09-21), `PLAN_LLM_FALLBACK.md` (НЕ исполнен — платформенное требование). Исторические доки (RESEARCH_*, IMPLEMENTATION_PLAN, REMEDIATION_*) — не обновляются (снимки).

**Грабля:** конфиг читается на старте сессии — изменения подхватываются только в НОВОЙ сессии (пилоты v5 — в новых сессиях). Бэкапы: `backup\<дата>_<тема>\`. YAML-грабля: «: » в незакавыченном description ломает парсинг. Имена моделей с пробелами/скобками (GLM-5.3 (res), Kimi K3) — байт-в-байт. Live-копии PLUGIN.md/MCP_SETUP.md в ~/.config/opencode/ — устарели (отдельный тикет).