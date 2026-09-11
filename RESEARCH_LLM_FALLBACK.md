# Исследование: Конфигурация fallback-моделей для агентов opencode

**Дата:** 2026-09-07
**Статус:** Исследование завершено
**Область:** 35 агентов (2 primary + 33 subagent), провайдер `bifrost-litellm`

---

## Executive Summary

1. **Все 35 агентов** используют единственного провайдера `bifrost-litellm` (Bifrost → LiteLLM proxy, `https://hcbifrost.herocraft.com/litellm/v1`). Единая точка отказа на уровне провайдера.
2. **Используется 10 уникальных моделей** для 35 агентов: QWEN3.7-plus (7 агентов), MiniMax-M3 (7), MiniMax-M2.7 (5), GLM-5.3 (res) (4), Kimi K3 (4), qwen3.8-max (3), mimo-v2.5-pro (2), GLM-5.3-Flash (res) (1), aliyun/qwen3.8-flash (1), Kimi K2.6 (1).
3. **Fallback-конфигурации в opencode сейчас НЕТ.** opencode не поддерживает нативный per-agent fallback (открытый feature request [anomalyco/opencode#8687](https://github.com/anomalyco/opencode/issues/8687)). Единственные «запасные» механизмы — `(res)`-варианты моделей (резервные квоты) и `small_model` (только для служебных задач вроде генерации заголовков).
4. **Правильное место для fallback — уровень LiteLLM proxy** (`fallbacks`, `context_window_fallbacks`, `default_fallbacks`), но proxy администрируется HeroCraft, поэтому нужен запрос администраторам либо локальное решение (вариантные агенты / плагин).
5. В конфиге уже есть **45+ моделей** у bifrost-litellm и второй провайдер `bailian-token-plan` (Alibaba, 13 моделей) — достаточно ресурсов для двухуровневого fallback почти для всех ролей.

---

## Current Model Configuration

### Источники
- `C:\Users\Admin\.config\opencode\opencode.json` (провайдеры, модели, лимиты)
- `C:\Users\Admin\.config\opencode\agents\*.md` (frontmatter `model:` — авторитетный источник, перекрывает JSON согласно ARCHITECTURE.md §Permission Authority)
- `P:\Programming\Рефакторинг\ARCHITECTURE.md` (таблица Subagent Models)

### Провайдеры

| Провайдер | Тип | Моделей | Назначение |
|-----------|-----|---------|------------|
| `bifrost-litellm` | `@ai-sdk/openai-compatible` | 45+ | Основной — все агенты |
| `bailian-token-plan` | `@ai-sdk/openai-compatible` | 13 | Настроен, но **ни один агент не использует** — резервный провайдер |

⚠️ **Найдена уязвимость:** в `opencode.json` в открытом виде хранится API-ключ `bailian-token-plan` (строка 640). Рекомендуется заменить на `{env:...}` и ротировать ключ.

### Текущее назначение моделей (по frontmatter `agents/*.md`)

| Модель | Контекст / Вывод | Thinking | Vision | Агенты |
|--------|------------------|----------|--------|--------|
| `QWEN3.7-plus` | 1M / 80K | ✅ | ✅ (img+video) | orchestrator, plankestrator, orchestrator-identity-probe, plankestrator-identity-probe, bugfix, consistency-checker, plan-writer-simple |
| `MiniMax-M3` | 1M / 131K | ✅ | ✅ (img+video) | worker, plan-bug, devops-agent, devops-readonly, git-commit, generate-image, generate-image-gpt |
| `MiniMax-M2.7` | 204.8K / 131K | ❌ | ❌ | utility, mcp-github, mcp-read, mcp-search, summarizer |
| `GLM-5.3 (res)` | 1M / 131K | ✅ | ❌ | execute-bug, dev-professor, plan-reviewer-simple, research-reviewer |
| `Kimi K3` | 1M / 1M | ✅ | ✅ (img+video) | dev-reviewer, rework, plan-reviewer-complex, research-writer-complex |
| `qwen3.8-max` | 1M / 131K | ✅ | ✅ (img+video) | dev-planner, plan-writer-complex, devops-reviewer |
| `mimo-v2.5-pro` | 1M / 131K | ✅ | ❌ | docs-writer, research-writer-simple |
| `GLM-5.3-Flash (res)` | 1M / 131K | ❌ | ✅ (img) | bugfix-triage |
| `aliyun/qwen3.8-flash` | 262K / 131K | ❌ | ❌ | docs-planner |
| `Kimi K2.6` | 262K / 262K | ✅ | ✅ (img) | view-image |

### Расхождения ARCHITECTURE.md ↔ фактический frontmatter

| Агент | ARCHITECTURE.md | Фактически (frontmatter) |
|-------|-----------------|--------------------------|
| dev-planner | QWEN3.7-plus | **qwen3.8-max** |
| devops-reviewer | QWEN3.7-plus | **qwen3.8-max** |
| identity probes (×2), plan-writer-* (×2), plan-reviewer-* (×2), research-* (×3), devops-readonly, git-commit, generate-image* (×2) | отсутствуют в таблице (13 subagent-агентов; primaries задокументированы отдельно в §Identity Lock п.5 — корректно; view-image — в §Shared Utility Agents, но без указания модели) | см. таблицу выше |

ARCHITECTURE.md — «single source of truth», но его таблица Subagent Models устарела/неполна. Требуется синхронизация (зона ответственности consistency-checker).

### Существующие «прото-fallback» механизмы

1. **`(res)`-варианты** (reserved quota): GLM-5.1/5.2/5.3 (res), GLM-5.3-Flash (res), `tencent/glm-5-2/5-3 (reserved - use when main is exhausted)` — резервные квотные пулы тех же моделей. Уже используются как primary у 5 агентов.
2. **Дубликаты через альтернативные апстримы**: `atlas_glm-5.1/5.2`, `atlas/qwen3.8-max`, `atlas/deepseek-v4-*`, `AlibabaTokenPlan/deepseek-v4-*`, `tencent/deepseek-v4-*` — та же модель через другой апстрим/квоту.
3. **`bailian-token-plan`** — целый второй провайдер с пересекающимся набором (qwen3.7-plus/max, deepseek-v4-pro/flash, kimi-k2.6, glm-5.1/5.2, MiniMax-M2.5).

---

## Agent Requirements Analysis

Классификация 35 агентов по требованиям к модели (на основе `ARCHITECTURE.md`, `AGENTS.md`, frontmatter permissions):

### Группа A — Роутеры (primary agents)
| Агент | Требования |
|-------|-----------|
| orchestrator, plankestrator | Максимальное следование инструкциям, стабильный JSON-вывод, длинный контекст (routing tables + pipeline state), thinking. Не пишут код. |

### Группа B — Identity probes
| Агент | Требования |
|-------|-----------|
| orchestrator-identity-probe, plankestrator-identity-probe | Тривиальные ответы, но должны работать ВСЕГДА (используются для identity lock). Дёшево/надёжно. |

### Группа C — Реализация кода (критично: agentic coding, tool use, bash)
| Агент | Требования |
|-------|-----------|
| worker, bugfix, execute-bug, rework | Сильный кодинг (SWE-bench класс), tool calling, следование плану, длинный контекст (файлы + тесты). |
| dev-professor | Кодинг + объяснения, чтение плана из dev_plan.md. |

### Группа D — Анализ и ревью кода
| Агент | Требования |
|-------|-----------|
| dev-reviewer, dev-planner, plan-bug, bugfix-triage | Глубокий анализ, reasoning, выявление edge cases. triage — быстрый и дешёвый. |

### Группа E — Валидация
| Агент | Требования |
|-------|-----------|
| consistency-checker, utility, devops-reviewer | Точность, детерминизм (temp 0.1), структурированный вывод. utility — простые проверки синтаксиса. |

### Группа F — Текст: планы и исследования
| Агент | Требования |
|-------|-----------|
| plan-writer-simple/complex, plan-reviewer-simple/complex, research-writer-simple/complex, research-reviewer | Длинный структурированный текст, анализ, синтез из нескольких источников. complex-варианты — сильный reasoning. |

### Группа G — Документация
| Агент | Требования |
|-------|-----------|
| docs-writer, docs-planner | Качественный технический русский/английский текст, понимание кода. |

### Группа H — MCP-агенты (лёгкие задачи)
| Агент | Требования |
|-------|-----------|
| mcp-search, mcp-read, mcp-github, summarizer, devops-readonly, devops-agent | Извлечение/суммаризация, вызов MCP-инструментов. Быстро и дёшево. |

### Группа I — Vision (ОБЯЗАТЕЛЬНА мультимодальность)
| Агент | Требования |
|-------|-----------|
| view-image | **Vision input обязателен** (скриншоты, диаграммы, UI). Fallback только на vision-модель. |

### Группа J — Специальные
| Агент | Требования |
|-------|-----------|
| generate-image, generate-image-gpt | LLM-часть — оркестрация skill `image-gen`; реальная генерация — `gemini/gemini-3-pro-image` / `gpt-image-1.5` (через skill). Требования к LLM низкие. |
| git-commit | Conventional commits, короткие сообщения. Низкие требования, но gated workflow. |

---

## Available Models Research

### Механизмы fallback

**1. opencode — нативной поддержки НЕТ.**
- Источник: [opencode.ai/docs/config](https://opencode.ai/docs/config/) — доступны только `model`, `small_model`, per-agent `model` (в JSON или frontmatter). `small_model` — только для служебных задач (генерация заголовков), не fallback.
- Источник: [GitHub anomalyco/opencode#8687 — "[FEATURE]: Fallback models in configuration"](https://github.com/anomalyco/opencode/issues/8687) — открытый feature request: «opencode detects if provider limits are reached and selects fallback». Не реализовано.
- Источник: zread sst/opencode «Provider and Model Routing» — модель идентифицируется составным ключом `providerID/modelID`, единственный на сессию/агента. Есть proposal «Per-Provider Quota-Aware Auto-Retry (#43324)» — тоже не реализовано.

**2. LiteLLM Proxy — полная поддержка fallback (рекомендуемый уровень).**
Источник: [docs.litellm.ai/docs/proxy/reliability](https://docs.litellm.ai/docs/proxy/reliability):
- `fallbacks: [{"model-a": ["model-b", "model-c"]}]` — общий failover (429, 500 и др.), по порядку.
- `context_window_fallbacks` — при `ContextWindowExceededError` (требует `router_settings.enable_pre_call_checks: true`).
- `content_policy_fallbacks` — при content-policy отказах.
- `default_fallbacks` — fallback по умолчанию для всех групп.
- `num_retries`, `allowed_fails`, `cooldown_time` — ретраи и cooldown до срабатывания fallback.
- Наблюдаемость: spend logs пишут `attempted_fallbacks` и `original_model_group`; заголовок `x-litellm-model-id`.
- Известная проблема: [litellm#31557](https://github.com/BerriAI/litellm/issues/31557) — fallback-цепочка молча падает, если у fallback-модели меньше контекстное окно, чем у primary. **Вывод: fallback-модель должна иметь контекст ≥ primary.**

**3. Локальный workaround для opencode (без изменения proxy):**
- Дублирующие `.md`-агенты с другой моделью (`worker-fb`) — громоздко, требует правки routing tables.
- Плагин-хук `tool.execute.after` / обработка provider error в `workflow-enforcement.ts` с переключением модели — возможно, но это разработка.
- Ручное переключение frontmatter `model:` при инциденте.

### Доступные модели bifrost-litellm (классификация по capabilities)

Источник: секция `provider.bifrost-litellm.models` в `opencode.json` + сравнительные обзоры (см. Sources Consulted).

| Класс | Модели | Контекст | Thinking | Vision |
|-------|--------|----------|----------|--------|
| **Флагманы coding/reasoning** | GLM-5.3 (+res), Kimi K3, deepseek-v4-pro, qwen3.8-max, QWEN3.7-plus, MiniMax-M3 | 1M | ✅ | K3/M3/qwen — ✅ |
| **Средний класс** | GLM-5.2 (+res), GLM-5.1 (+res), Kimi K2.7, Kimi K2.6, Qwen3.5-plus, mimo-v2.5-pro, mimo-v2.5, deepseek-v3.2, tencent/Hy4 | 160K–1M | ✅ | K2.6/K2.7/mimo-v2.5 — ✅ |
| **Быстрые/дешёвые** | GLM-5.3-Flash (+res), MiniMax-M2.7 (+highspeed), MiniMax-M2.5 (+highspeed), MiniMax-M2.1-highspeed, deepseek-v4-flash, qwen3.6-flash, aliyun/qwen3.8-flash, seed-2.1, doubao-seed-2.1-turbo, tencent/Hy3 | 200K–1M | частично | Flash-GLM/qwen3.6-flash/seed-2.1 — ✅ |
| **Image generation** | gemini/gemini-3-pro-image, gemini/gemini-3.1-flash-image, gpt-image-1.5, gpt-image-2 | — | — | output: image |
| **Резервные квоты** | `tencent/glm-5-2/5-3 (reserved)`, `atlas_*`, `AlibabaTokenPlan/*`, `tencent/deepseek-v4-*` | = основным | — | — |

**Рыночный контекст (внешние источники, семейства моделей):**
- [Morph — "Best Open-Source Coding Model 2026"](https://www.morphllm.com/best-open-source-coding-model-2026): GLM-5.2 лидирует в open-weights Intelligence Index, DeepSeek V4 — в SWE-bench Verified, Kimi K3 — сильный coding.
- [kingy.ai — "Best Open-Weight AI Models 2026"](https://kingy.ai/news/best-open-weight-ai-models-in-2026-glm-5-2-vs-deepseek-v4-vs-kimi-k2-6-vs-qwen-vs-mistral/): сравнение GLM-5.3-Flash, DeepSeek V4-Flash, Kimi K3, Qwen3.8 по стоимости/лицензиям.
- [atlascloud.ai](https://www.atlascloud.ai/blog/tips/coding-plan-best-open-source-coding-llm): DeepSeek V4, Kimi K2, GLM-5, MiniMax M2, Qwen3 — лидеры coding-класса; MiniMax отличается скоростью.
- [Medium — MiniMax M2 Review](https://medium.com/@leucopsis/minimax-m2-review-and-comparison-with-open-weight-rivals-60c676ef5346): MiniMax-M2 ~83% LiveCodeBench, на уровне GLM-4.6 и Kimi K2 Thinking; скорость ~2x GLM.

⚠️ Внешние бенчмарки описывают публичные версии семейств; внутренние версии за Bifrost (GLM-5.3, Kimi K3, Qwen3.8, MiniMax-M3) могут отличаться. Точные capabilities известны только по фактической эксплуатации.

---

## Model Classification by Role

Принципы подбора fallback:
1. **L1** — та же модель через другой квотный пул/апстрим (гарантированная идентичность capabilities), либо ближайший родственник в семействе.
2. **L2** — другая семья с сопоставимыми capabilities. Правило: ctx(fallback) ≥ ctx(primary) (из-за litellm#31557 — запрос, влезающий в primary, молча падает на fallback с меньшим окном). Исключение: для агентов с заведомо короткими диалогами (git-commit, generate-image*, devops-readonly, triage, devops-команды) допускается fallback с меньшим ctx — такие места помечены `[ctx-exception]`; риск: при неожиданно длинном диалоге fallback откажет по контексту.
3. Vision-агенты могут fallback **только** на vision-модели.
4. Роутеры и identity probes — только на модели с доказанным следованием формату JSON.
5. **Соглашение об именовании L1 «тот же пул/апстрим»**: гарантируется идентичность модели, но не обязательно идентичность опций конфига (напр., `atlas/qwen3.8-max` без `options.thinking` при thinking-первичной `qwen3.8-max`).

| Роль | Primary | Fallback L1 | Fallback L2 |
|------|---------|-------------|-------------|
| Роутеры (orchestrator, plankestrator) | QWEN3.7-plus | qwen3.8-max (семья Qwen, 1M, thinking) | GLM-5.3 (res) (1M, thinking, сильный instruction following) |
| Identity probes | QWEN3.7-plus | qwen3.8-max | GLM-5.3-Flash (res) (быстро, дёшево, задача тривиальна) |
| Coding implementation (worker, execute-bug, rework*, dev-professor) | MiniMax-M3 / GLM-5.3 (res) / Kimi K3 | Взаимно: GLM-5.3 ↔ Kimi K3 ↔ MiniMax-M3 | deepseek-v4-pro (1M, thinking, лидер SWE-bench) |
| Code review/planning (dev-reviewer, dev-planner, plan-bug) | Kimi K3 / qwen3.8-max / MiniMax-M3 | GLM-5.3 (res) | deepseek-v4-pro |
| Triage (bugfix-triage) | GLM-5.3-Flash (res) | GLM-5.3-Flash (основной пул) | MiniMax-M2.7-highspeed |
| Валидация (consistency-checker, utility, devops-reviewer) | QWEN3.7-plus / MiniMax-M2.7 / qwen3.8-max | qwen3.8-max / MiniMax-M2.7-highspeed / QWEN3.7-plus | GLM-5.3 (res) / GLM-5.3-Flash (res) |
| Планы/исследования (plan-*, research-*) | QWEN3.7-plus / qwen3.8-max / Kimi K3 / GLM-5.3 (res) / mimo-v2.5-pro | Внутрисемейные (см. матрицу) | GLM-5.3 (res) / deepseek-v4-pro |
| Документация (docs-writer, docs-planner) | mimo-v2.5-pro / aliyun/qwen3.8-flash | mimo-v2.5 / qwen3.6-flash | Qwen3.5-plus / MiniMax-M2.7 |
| MCP-агенты, summarizer | MiniMax-M2.7 | MiniMax-M2.7-highspeed (тот же вес, быстрый пул) | GLM-5.3-Flash (res) (1M контекст — запас) |
| **Vision (view-image)** | Kimi K2.6 | **Kimi K2.7** (та же семья, vision, thinking) | **GLM-5.3-Flash (res)** (vision, 1M) или qwen3.8-max (vision) |
| Image-gen orchestration | MiniMax-M3 | MiniMax-M2.7 | любая (LLM — только оркестратор skill) |
| git-commit | MiniMax-M3 | MiniMax-M2.7 | GLM-5.3-Flash (res) |

---

## Fallback Matrix

Полная матрица для всех 35 агентов. Все модели — через `bifrost-litellm/` (префикс опущен).

| # | Агент | Основная модель | Fallback L1 | Fallback L2 | Обоснование |
|---|-------|-----------------|-------------|-------------|-------------|
| 1 | orchestrator | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Роутер: критичны JSON-стабильность и instruction following; L1 — та же семья Qwen с 1M ctx; L2 — флагман с thinking. Плагин identity-lock привязан к имени агента, не к модели — смена безопасна. |
| 2 | plankestrator | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Аналогично orchestrator. |
| 3 | orchestrator-identity-probe | QWEN3.7-plus | qwen3.8-max | GLM-5.3-Flash (res) | Задача тривиальна (ответ-пробник), но должна работать всегда → L2 самый дешёвый/доступный. |
| 4 | plankestrator-identity-probe | QWEN3.7-plus | qwen3.8-max | GLM-5.3-Flash (res) | См. #3. |
| 5 | bugfix-triage | GLM-5.3-Flash (res) | GLM-5.3-Flash | MiniMax-M2.7-highspeed | L1 — та же модель, основной квотный пул (res↔main); L2 — быстрая 204K модель `[ctx-exception: 204K < 1M primary; диалог triage короткий]`. |
| 6 | bugfix | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Кодинг + bash; L1 — старшая Qwen (1M, thinking); L2 — топ open-weights coding (Intelligence Index, Morph). |
| 7 | plan-bug | MiniMax-M3 | GLM-5.3 (res) | deepseek-v4-pro | Планирование багфикса — reasoning; L1/L2 — флагманы с thinking и 1M ctx. |
| 8 | execute-bug | GLM-5.3 (res) | GLM-5.3 | Kimi K3 | L1 — основной пул той же модели; L2 — Kimi K3 (1M/1M, сильный coding). |
| 9 | worker | MiniMax-M3 | GLM-5.3 (res) | deepseek-v4-pro | Основной исполнитель: нужен лучший coding + tool calling; L2 — лидер SWE-bench Verified (Morph). |
| 10 | rework | Kimi K3 | GLM-5.3 (res) | deepseek-v4-pro | Rework по фидбеку — применение точечных правок; флагманы взаимозаменяемы. |
| 11 | dev-planner | qwen3.8-max | atlas/qwen3.8-max | GLM-5.3 (res) | L1 — та же модель через апстрим atlas (другая квота); L2 — флагман с 1M ctx. |
| 12 | dev-professor | GLM-5.3 (res) | GLM-5.3 | Kimi K3 | Кодинг + объяснения; L1 — основной пул. |
| 13 | dev-reviewer | Kimi K3 | GLM-5.3 (res) | deepseek-v4-pro | Ревью: флагманы с thinking и 1M ctx. Kimi K2.7 как L1 отвергнут: 262K < 1M primary (litellm#31557). |
| 14 | consistency-checker | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Валидация против ARCHITECTURE.md — длинный контекст + точность. |
| 15 | utility | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | Синтаксис-чек: скорость важнее глубины; L1 — тот же вес в highspeed-пуле; L2 — 1M ctx запас. |
| 16 | docs-writer | mimo-v2.5-pro | mimo-v2.5 | Qwen3.5-plus | L1 — vision-вариант той же семьи (text-only задачи docs покрывает); L2 — 1M, thinking, сильный текст. |
| 17 | docs-planner | aliyun/qwen3.8-flash | qwen3.6-flash | MiniMax-M2.7-highspeed | L1 — flash-модель Qwen с 1M ctx (больше запас по контексту); L2 — быстрая `[ctx-exception: 204K < 262K primary; план документации короткий]`. |
| 18 | research-writer-simple | mimo-v2.5-pro | mimo-v2.5 | GLM-5.2 (res) | L1 — та же семья; L2 — 1M ctx для синтеза источников. |
| 19 | research-writer-complex | Kimi K3 | GLM-5.3 (res) | deepseek-v4-pro | Complex research — глубокий reasoning; L1/L2 — флагманы с 1M ctx (Kimi K2.7 262K < primary 1M — не подходит); L2 — 1M ctx + 393K output. |
| 20 | research-reviewer | GLM-5.3 (res) | GLM-5.3 | Kimi K3 | L1 — основной пул той же модели. |
| 21 | plan-writer-simple | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Простые планы — семейная замена достаточна. |
| 22 | plan-writer-complex | qwen3.8-max | atlas/qwen3.8-max | Kimi K3 | L1 — другой апстрим той же модели; L2 — флагман с наибольшим output (1M). |
| 23 | plan-reviewer-simple | GLM-5.3 (res) | GLM-5.3 | QWEN3.7-plus | L1 — основной пул. |
| 24 | plan-reviewer-complex | Kimi K3 | GLM-5.3 (res) | deepseek-v4-pro | См. #13. |
| 25 | devops-agent | MiniMax-M3 | GLM-5.3 (res) | MiniMax-M2.7-highspeed | DevOps-команды: L2 — быстрая модель, команды короткие `[ctx-exception: 204K < 1M primary]`. |
| 26 | devops-reviewer | qwen3.8-max | atlas/qwen3.8-max | QWEN3.7-plus | См. #11. |
| 27 | devops-readonly | MiniMax-M3 | MiniMax-M2.7 | GLM-5.3-Flash (res) | Read-only задачи — можно дешевле `[ctx-exception: L1 204K < 1M primary; вывод только чтение/суммаризация]`. |
| 28 | mcp-github | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | MCP-вызовы + суммаризация; лёгкая задача. |
| 29 | mcp-read | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | См. #28. |
| 30 | mcp-search | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | См. #28. |
| 31 | summarizer | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | См. #28; L2 даёт запас контекста до 1M для длинных документов. |
| 32 | view-image | Kimi K2.6 | Kimi K2.7 | GLM-5.3-Flash (res) | **Только vision-модели.** L1 — прямой апгрейд семьи (vision+thinking); L2 — vision с 1M ctx; альтернатива L2: qwen3.8-max (img+video). |
| 33 | generate-image | MiniMax-M3 | MiniMax-M2.7 | GLM-5.3-Flash (res) | LLM только оркестрирует skill image-gen (gemini-3-pro-image); требования минимальны `[ctx-exception: L1 204K < 1M primary; промпт генерации короткий]`. |
| 34 | generate-image-gpt | MiniMax-M3 | MiniMax-M2.7 | GLM-5.3-Flash (res) | См. #33 (skill → gpt-image-1.5) `[ctx-exception: L1]`. |
| 35 | git-commit | MiniMax-M3 | MiniMax-M2.7 | GLM-5.3-Flash (res) | Короткие conventional-commit сообщения; высокая надёжность важнее качества `[ctx-exception: L1 204K < 1M primary; diff + сообщение короткие]`. |

### Дополнительно: fallback для image-generation моделей (уровень skill)

| Назначение | Primary | Fallback L1 | Fallback L2 |
|-----------|---------|-------------|-------------|
| Image-gen (Gemini) | gemini/gemini-3-pro-image | gemini/gemini-3.1-flash-image | gpt-image-2 |
| Image-gen (GPT) | gpt-image-1.5 | gpt-image-2 | gemini/gemini-3.1-flash-image |

---

## Recommendations

### Приоритет 1 — Fallback на уровне LiteLLM/Bifrost proxy (правильный слой)
Запросить у администраторов Bifrost (`hcbifrost.herocraft.com`) настройку `litellm_settings.fallbacks` по матрице выше, агрегированной до уровня моделей (10 уникальных primary → их цепочки):

```yaml
litellm_settings:
  num_retries: 2
  allowed_fails: 2
  cooldown_time: 60
  fallbacks:
    - {"QWEN3.7-plus": ["qwen3.8-max", "GLM-5.3 (res)"]}
    - {"MiniMax-M3": ["GLM-5.3 (res)", "deepseek-v4-pro"]}
    - {"MiniMax-M2.7": ["MiniMax-M2.7-highspeed", "GLM-5.3-Flash (res)"]}
    - {"GLM-5.3 (res)": ["GLM-5.3", "Kimi K3"]}
    - {"Kimi K3": ["GLM-5.3 (res)", "deepseek-v4-pro"]}
    - {"qwen3.8-max": ["atlas/qwen3.8-max", "GLM-5.3 (res)"]}
    - {"mimo-v2.5-pro": ["mimo-v2.5", "Qwen3.5-plus"]}
    - {"GLM-5.3-Flash (res)": ["GLM-5.3-Flash", "MiniMax-M2.7-highspeed"]}
    - {"aliyun/qwen3.8-flash": ["qwen3.6-flash", "MiniMax-M2.7-highspeed"]}
    - {"Kimi K2.6": ["Kimi K2.7", "GLM-5.3-Flash (res)"]}
  default_fallbacks: ["GLM-5.3 (res)"]
router_settings:
  enable_pre_call_checks: true   # для context_window_fallbacks
```

Плюсы: прозрачно для opencode, работает для всех агентов сразу, наблюдаемость через `attempted_fallbacks` в spend logs.
Минус: зависит от администраторов proxy; имена моделей с пробелами/скобками (`GLM-5.3 (res)`) — проверить корректность в YAML-ключах.

⚠️ **Ограничение агрегации:** LiteLLM применяет fallback на уровне *модели*, а не агента, поэтому агент-специфичные отличия матрицы от цепочек YAML (L2 identity probes = GLM-5.3-Flash (res); L2 plan-reviewer-simple = QWEN3.7-plus; L2 plan-writer-complex = Kimi K3; L2 research-writer-simple = GLM-5.2 (res); удешевлённые цепочки devops-readonly / generate-image* / git-commit через MiniMax-M2.7) на proxy-уровне реализованы НЕ будут — для этих агентов фактически действует цепочка их primary-модели из YAML. Постатная дифференциация возможна только локально (вариантные агенты / смена frontmatter).

### Приоритет 2 — Второй провайдер как disaster recovery
`bailian-token-plan` уже настроен, но не используется. Покрывает fallback для ключевых семейств при полном отказе Bifrost: `bailian-token-plan/qwen3.7-plus`, `.../deepseek-v4-pro`, `.../kimi-k2.6`, `.../glm-5.2`, `.../MiniMax-M2.5`. Это **L3-уровень** (ручное переключение frontmatter при длительном инциденте Bifrost). Предварительно: проверить валидность API-ключа и вынести его в env-переменную (сейчас в открытом виде в opencode.json, строка 640 — **срочно ротировать**).

### Приоритет 3 — Локальный мониторинг
- Следить за [opencode#8687](https://github.com/anomalyco/opencode/issues/8687) (native fallback) и [#43324](https://github.com/anomalyco/opencode/issues/43324) (quota-aware retry) — при реализации перейти на нативный механизм.
- Добавить в `workflow-enforcement.ts` логирование provider errors (хук `message.updated`) для раннего обнаружения деградации модели.

### Приоритет 4 — Гигиена конфигурации
1. Синхронизировать таблицу Subagent Models в ARCHITECTURE.md с фактическим frontmatter (расхождения: dev-planner, devops-reviewer; отсутствуют 13 агентов — 11 из plan/research/devops-readonly/git-commit/generate-image* + 2 identity probes; для view-image указать модель Kimi K2.6 в таблице).
2. При добавлении fallback-цепочек задокументировать их в ARCHITECTURE.md (новый раздел) — иначе consistency-checker не сможет их валидировать.
3. Не задавать `model` для агентов в opencode.json (мёртвый конфиг — frontmatter побеждает, ARCHITECTURE.md §Permission Authority).

---

## Limitations

1. **Нет нативной поддержки fallback в opencode** — матрица является проектом конфигурации для LiteLLM-уровня, а не готовым переключателем. Без доступа к админке Bifrost применить её нельзя.
2. **Внутренние версии моделей** (GLM-5.3, Kimi K3, MiniMax-M3, Qwen3.8-max, deepseek-v4, mimo-v2.5) за Bifrost могут отличаться от публичных версий, описанных в бенчмарках. Реальные capabilities/квоты/лимиты `(res)`-пулов известны только администраторам proxy — перед применением нужна верификация доступности каждой fallback-модели (`GET /models` или тестовые запросы).
3. **Совместимость thinking-опций**: у части fallback-моделей в конфиге нет `options.thinking` (MiniMax-M2.7, GLM-5.3-Flash, aliyun/qwen3.8-flash, **а также atlas/qwen3.8-max при thinking-первичной qwen3.8-max** — L1-цепочки dev-planner/plan-writer-complex/devops-reviewer теряют thinking, что противоречит принципу «L1 = идентичные capabilities»). Агенты, чьи промпты рассчитаны на reasoning (dev-reviewer, plan-writer-complex), при fallback на не-thinking модель могут деградировать в качестве — учтено в матрице (L1/L2 с thinking там, где это критично), но не проверено эмпирически.
4. **Имена моделей с пробелами и скобками** (`GLM-5.3 (res)`, `tencent/glm-5-2 (reserved - ...)`) — потенциальные проблемы экранирования в YAML/URL; требуется тест.
5. **Мультимодальные fallback'и для view-image** проверены только по декларированным `modalities` в opencode.json, а не реальными запросами.
6. **Стоимость и латентность** fallback-моделей не оценены (нет доступа к прайсингу HeroCraft); сравнения стоимости — по публичным источникам семейств.
7. Конфигурация `bailian-token-plan` не проверена на работоспособность (ключ, квоты, региональный endpoint ap-southeast-1).

---

## Sources Consulted

| # | Источник | Что извлечено |
|---|----------|---------------|
| 1 | `C:\Users\Admin\.config\opencode\opencode.json` | Провайдеры, 45+ моделей с лимитами/модальностями/thinking, отсутствие fallback-полей |
| 2 | `C:\Users\Admin\.config\opencode\agents\*.md` (35 файлов, grep `^model:`) | Фактическая модель каждого агента (авторитетный источник) |
| 3 | `P:\Programming\Рефакторинг\ARCHITECTURE.md` | Роли агентов, routing tables, таблица Subagent Models (устарела), permission authority |
| 4 | [opencode.ai/docs/config](https://opencode.ai/docs/config/) | Схема конфигурации: `model`, `small_model`, per-agent `model`; fallback отсутствует |
| 5 | [GitHub anomalyco/opencode#8687](https://github.com/anomalyco/opencode/issues/8687) | Feature request «Fallback models in configuration» — открыт, не реализован |
| 6 | [zread.ai/sst/opencode — Provider and Model Routing, Latest Updates](https://zread.ai/sst/opencode/19-provider-and-model-routing) | Модель = `providerID/modelID`; proposal #43324 quota-aware retry — не реализован |
| 7 | [docs.litellm.ai/docs/proxy/reliability](https://docs.litellm.ai/docs/proxy/reliability) | Синтаксис `fallbacks`/`context_window_fallbacks`/`default_fallbacks`, retries/cooldowns, spend-log наблюдаемость |
| 8 | [GitHub BerriAI/litellm#31557](https://github.com/BerriAI/litellm/issues/31557) | Fallback молча падает при меньшем контексте fallback-модели → правило «ctx(fallback) ≥ ctx(primary)» |
| 9 | [morphllm.com — Best Open-Source Coding Model 2026](https://www.morphllm.com/best-open-source-coding-model-2026) | GLM-5.2 топ Intelligence Index; DeepSeek V4 лидер SWE-bench Verified; Kimi K3 сильный coding |
| 10 | [kingy.ai — Best Open-Weight AI Models 2026](https://kingy.ai/news/best-open-weight-ai-models-in-2026-glm-5-2-vs-deepseek-v4-vs-kimi-k2-6-vs-qwen-vs-mistral/) | Сравнение GLM-5.3-Flash / DeepSeek V4-Flash / Kimi K3 / Qwen3.8 |
| 11 | [atlascloud.ai — Best Open Source Coding LLM 2026](https://www.atlascloud.ai/blog/tips/coding-plan-best-open-source-coding-llm) | DeepSeek V4, Kimi K2, GLM-5, MiniMax M2, Qwen3 — лидеры coding-класса |
| 12 | [Medium — MiniMax M2 Review](https://medium.com/@leucopsis/minimax-m2-review-and-comparison-with-open-weight-rivals-60c676ef5346) | MiniMax-M2 ~83% LiveCodeBench; скорость ~2x GLM |

---

```json
{
  "research_file": "RESEARCH_LLM_FALLBACK.md",
  "research_written": true,
  "next_action": "research-reviewer should read from research_file"
}
```
