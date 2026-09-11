# LLM Fallback Implementation Plan

**Дата:** 2026-09-07
**Источник:** `RESEARCH_LLM_FALLBACK.md` (исследование завершено 2026-09-07)
**Область:** 35 агентов (2 primary + 33 subagent), провайдер `bifrost-litellm`, резервный провайдер `bailian-token-plan`
**Статус:** План готов к ревью (plan-reviewer-complex)

---

## Цель

Обеспечить отказоустойчивость LLM-конфигурации opencode в условиях, когда:
1. opencode **не поддерживает нативный per-agent fallback** (открытый FR [anomalyco/opencode#8687](https://github.com/anomalyco/opencode/issues/8687), proposal [#43324](https://github.com/anomalyco/opencode/issues/43324) — не реализованы);
2. правильный слой для fallback — **LiteLLM proxy** (`hcbifrost.herocraft.com/litellm/v1`), администрируемый HeroCraft (нет прямого доступа);
3. все 35 агентов зависят от единственного провайдера `bifrost-litellm` — единая точка отказа.

## Критерии успеха

| # | Критерий | Проверяется |
|---|----------|-------------|
| SC-1 | Все 35 агентов имеют документированные fallback-цепочки (L1/L2) | Раздел «LLM Fallback Chains» в ARCHITECTURE.md содержит матрицу на 35 строк |
| SC-2 | ARCHITECTURE.md синхронизирован с фактическим frontmatter `agents/*.md` | consistency-checker проходит; `rg` по таблице даёт 33 subagent-строки, совпадающие с frontmatter |
| SC-3 | API-ключ `bailian-token-plan` ротирован или удалён из `opencode.json` | `rg "sk-sp-" opencode.json` → 0 совпадений |
| SC-4 | YAML-конфигурация `litellm_settings.fallbacks` готова для передачи админам Bifrost | Файл `BIFROST_FALLBACK_REQUEST.md` существует и содержит валидный YAML + тестовый план |
| SC-5 | Документированы ручные действия при недоступности модели (L3 disaster recovery) | Файл `FALLBACK_RUNBOOK.md` существует |

## Приоритизация фаз

| Фаза | Приоритет | Категория | Зависимости |
|------|-----------|-----------|-------------|
| Phase 1: Ротация API-ключа | **Критический** | security | нет |
| Phase 2: Синхронизация ARCHITECTURE.md | **Высокий** | consistency | нет |
| Phase 3: Fallback-цепочки + запрос Bifrost | **Средний** | resilience | Phase 2 (раздел добавляется после синхронизированной таблицы) |
| Phase 4: Альтернативные стратегии | **Низкий** | optimization | Phase 3 (runbook ссылается на матрицу) |
| Phase 5: Финальная валидация | — | acceptance | Phases 1–4 |

## Исполнители операций

- **`.md`-операции** (Phases 2–4, большинство): агент с `edit: allow` для `.md` (worker / docs-writer) через orchestrator, либо plan-writer при явном запросе пользователя.
- **Операции с `opencode.json`** (Ops 1.1, 4.1): НЕ `.md`-файл — выполняет worker (у него `edit: allow` без ограничения) или пользователь вручную. plan-writer-агентам запрещено.
- **Ротация ключа в Alibaba Cloud** (Op 1.2): только пользователь вручную (нет API-доступа к консоли).
- **Применение YAML на proxy** (Phase 3): только администраторы Bifrost/HeroCraft — вне нашего контроля.

---

## Phase 1: Security — ротация и вынос API-ключа bailian-token-plan (КРИТИЧЕСКИЙ)

> Уязвимость: в `C:\Users\Admin\.config\opencode\opencode.json` **строка 640** хранит API-ключ провайдера `bailian-token-plan` в открытом виде (`"apiKey": "sk-sp-D.DDHP..."` — полный ключ НЕ дублируется в этом плане намеренно). Ни один из 35 агентов провайдер не использует, поэтому операционный риск правки ≈ 0, но ключ скомпрометирован фактом хранения в plaintext и подлежит ротации.

### Operation 1.1: Заменить plaintext-ключ на env-ссылку в opencode.json
- **File:** `C:\Users\Admin\.config\opencode\opencode.json` (строка 640, секция `provider.bailian-token-plan.options.apiKey`)
- **Action:** заменить
  ```json
  "apiKey": "sk-sp-D.DDHP....(полное значение в конфиге)"
  ```
  на
  ```json
  "apiKey": "{env:BAILIAN_TOKEN_PLAN_API_KEY}"
  ```
  Перед правкой сделать резервную копию файла (`copy opencode.json opencode.json.bak-2026-09-07`). ⚠️ **Бэкап содержит скомпрометированный ключ в plaintext** — после успешной верификации (Op 1.3) удалить его (`del opencode.json.bak-2026-09-07`) либо переместить в защищённое хранилище вне каталога конфига; до удаления бэкапа SC-3 НЕ считается выполненным.
- **Verify:** `rg -n "sk-sp-" C:\Users\Admin\.config\opencode\opencode.json` → 0 совпадений; opencode стартует без ошибок конфигурации провайдера.
- **Risk:** если env-переменная ещё не задана (Op 1.2), провайдер `bailian-token-plan` станет нерабочим. Acceptable: ни один агент его не использует. (Допустим альтернативный порядок без окна поломки: сначала Op 1.2 п.1–2 — новый ключ + `setx`, затем Op 1.1 — замена на env-ссылку; оба варианта корректны.) **Откат:** восстановить строку 640 из `opencode.json.bak-2026-09-07` (до его удаления).

### Operation 1.2: Ротировать ключ в Alibaba Cloud и задать env-переменную
- **File:** консоль Alibaba Cloud (Model Studio / Token Plan, регион `ap-southeast-1`) + пользовательские env-переменные Windows
- **Action (пользователь вручную):**
  1. Выпустить новый API-ключ для Token Plan (`https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`).
  2. Задать переменную: `setx BAILIAN_TOKEN_PLAN_API_KEY "<новый ключ>"` (или System Properties → Environment Variables).
  3. Отозвать старый ключ `sk-sp-D.DDHP...` **только после** успешной проверки нового (Ops 1.3).
  4. Проверить, что старый ключ не остался в plaintext нигде, кроме временного бэкапа Op 1.1: `rg -l "sk-sp-" P:\Programming\Рефакторинг` → 0 совпадений вне `backup/`; **и** `rg -l "sk-sp-" C:\Users\Admin\.config\opencode --glob "!node_modules" --glob "!*.map"` → единственное допустимое совпадение — `opencode.json.bak-2026-09-07` (удаляется после Op 1.3). В git-историю `opencode.json` не попадает — репозиторий его не содержит (см. MCP_SETUP.md строка 440).
- **Verify:** в новой shell `echo %BAILIAN_TOKEN_PLAN_API_KEY%` непусто; оба grep выше зелёные.
- **Risk:** отзыв старого ключа до проверки нового сломает доступ. **Откат:** выпустить ещё один ключ в консоли (старые отозванные не восстанавливаются — поэтому порядок «сначала проверить, потом отзывать» обязателен).

### Operation 1.3: Верифицировать работоспособность bailian-token-plan (L3 disaster recovery)
- **File:** `FALLBACK_RUNBOOK.md` (создаётся в Op 4.2 — результат записать туда; до создания — временная заметка в этом плане/коммите)
- **Action:** выполнить тестовый запрос (исследование Limitations №7: провайдер никогда не проверялся):
  ```
  curl -H "Authorization: Bearer %BAILIAN_TOKEN_PLAN_API_KEY%" https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/models
  ```
  Затем — один chat-completion к `bailian-token-plan/qwen3.7-plus`. Зафиксировать результат (работает / ошибка ключа / ошибка региона).
- **Verify:** HTTP 200 на `/models`; список содержит `qwen3.7-plus`, `qwen3.7-max`, `deepseek-v4-pro`, `kimi-k2.6`, `glm-5.2` (13 моделей по конфигу).
- **Risk:** провайдер может оказаться нерабочим (квоты/регион) — тогда L3-уровень фиктивен. **Откат:** не требуется (read-only проверка); при нерабочем провайдере — пометить в runbook «L3 НЕДОСТУПЕН, требуется настройка» и не полагаться на него в инцидентах.

---

## Phase 2: Consistency — синхронизация ARCHITECTURE.md с frontmatter (ВЫСОКИЙ)

> Расхождения (исследование, строки 50–58): `dev-planner` и `devops-reviewer` указаны как `QWEN3.7-plus`, фактически — `qwen3.8-max`; **13 subagent-агентов отсутствуют** в таблице (identity probes ×2, plan-writer-* ×2, plan-reviewer-* ×2, research-* ×3, devops-readonly, git-commit, generate-image ×2); `view-image` упомянут в §Shared Utility Agents (строка 63) без модели.

### Operation 2.0: Снять авторитетное состояние frontmatter (подготовка)
- **File:** `C:\Users\Admin\.config\opencode\agents\*.md` (35 файлов, read-only)
- **Action:** выполнить `rg -n "^model:" C:\Users\Admin\.config\opencode\agents\*.md` и зафиксировать вывод как эталон для Ops 2.1–2.3. Frontmatter — авторитетный источник (ARCHITECTURE.md §Permission Authority, строки 134–144: frontmatter мерджится после opencode.json и побеждает).
- **Verify:** вывод содержит ровно 35 строк `model:`.
- **Risk:** нет (read-only).

### Operation 2.1: Обновить таблицу Subagent Models в корневом ARCHITECTURE.md
- **File:** `P:\Programming\Рефакторинг\ARCHITECTURE.md` — секция `## Subagent Models` (строка 65), таблица строки 67–87
- **Action:**
  1. **Исправить 2 строки:**
     - строка 74: `| dev-planner | bifrost-litellm/QWEN3.7-plus |` → `| dev-planner | bifrost-litellm/qwen3.8-max |`
     - строка 87: `| devops-reviewer | bifrost-litellm/QWEN3.7-plus |` → `| devops-reviewer | bifrost-litellm/qwen3.8-max |`
  2. **Добавить 14 строк** (13 отсутствующих агентов + view-image с моделью):
     ```markdown
     | orchestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
     | plankestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
     | plan-writer-simple | bifrost-litellm/QWEN3.7-plus |
     | plan-writer-complex | bifrost-litellm/qwen3.8-max |
     | plan-reviewer-simple | bifrost-litellm/GLM-5.3 (res) |
     | plan-reviewer-complex | bifrost-litellm/Kimi K3 |
     | research-writer-simple | bifrost-litellm/mimo-v2.5-pro |
     | research-writer-complex | bifrost-litellm/Kimi K3 |
     | research-reviewer | bifrost-litellm/GLM-5.3 (res) |
     | devops-readonly | bifrost-litellm/MiniMax-M3 |
     | git-commit | bifrost-litellm/MiniMax-M3 |
     | generate-image | bifrost-litellm/MiniMax-M3 |
     | generate-image-gpt | bifrost-litellm/MiniMax-M3 |
     | view-image | bifrost-litellm/Kimi K2.6 |
     ```
  3. **Добавить примечание** под таблицей: primaries (orchestrator, plankestrator — `bifrost-litellm/QWEN3.7-plus`) задокументированы в §Identity Lock Mechanism (v3) п.5 (строка 553) — в таблицу не дублируются.
  4. Перед применением сверить каждую строку с эталоном из Op 2.0 (модели в таблице выше взяты из исследования, строки 39–48; при любом расхождении с frontmatter — приоритет у frontmatter).
- **Verify:** таблица содержит 33 subagent-строки; `rg -n "dev-planner|devops-reviewer" P:\Programming\Рефакторинг\ARCHITECTURE.md` показывает `qwen3.8-max` в обеих строках таблицы моделей; построчное совпадение с выводом Op 2.0.
- **Risk:** ошибка в имени модели (регистр, пробелы, `(res)`) сломает валидацию consistency-checker. **Откат:** `git checkout -- ARCHITECTURE.md` (файл в git-репозитории `P:\Programming\Рефакторинг`).

### Operation 2.2: Синхронизировать копии ARCHITECTURE.md
- **File:**
  - `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md` — секция `## Subagent Models` на строке 61
  - `P:\Programming\Рефакторинг\deploy-package\project-files\ARCHITECTURE.md` — секция `## Subagent Models` на строке 18
- **Action:** применить те же изменения, что в Op 2.1 (с учётом иной нумерации строк и возможных отличий в составе таблиц — сначала diff секций). Каталог `backup\` **НЕ трогать** (исторические снимки).
- **Verify:** `rg -n "qwen3.8-max" opencode-config\ARCHITECTURE.md deploy-package\project-files\ARCHITECTURE.md` → строки dev-planner/devops-reviewer обновлены; `rg -c "^\| " <секция таблицы>` — одинаковое число строк во всех трёх копиях.
- **Risk:** копии могли разойтись исторически (deploy-package — урезанная версия); слепая замена может сломать их структуру. **Откат:** `git checkout -- opencode-config/ARCHITECTURE.md deploy-package/project-files/ARCHITECTURE.md`.

### Operation 2.3: Валидация consistency-checker
- **File:** — (запуск агента)
- **Action:** через orchestrator запустить `consistency-checker` для проверки ARCHITECTURE.md против `agents/*.md` (зона его ответственности по исследованию, строка 58).
- **Verify:** отчёт consistency-checker без расхождений по моделям.
- **Risk:** consistency-checker может выявить дополнительные (не описанные в исследовании) расхождения — не откат, а вход для новой итерации Phase 2. **Откат при ложных срабатываниях:** git revert коммита синхронизации.

---

## Phase 3: Resilience — fallback-цепочки и запрос админам Bifrost (СРЕДНИЙ)

### Operation 3.1: Новый раздел «LLM Fallback Chains» в ARCHITECTURE.md
- **File:** `P:\Programming\Рефакторинг\ARCHITECTURE.md` — вставить после §Subagent Models (после строки 87 с учётом добавлений Op 2.1)
- **Action:** добавить раздел, содержащий (без него consistency-checker не сможет валидировать цепочки — исследование, Recommendations §4.2):
  1. **Принципы подбора** (исследование, строки 174–179):
     - L1 — та же модель через другой квотный пул/апстрим, либо ближайший родственник семейства;
     - L2 — другая семья с сопоставимыми capabilities; правило **ctx(fallback) ≥ ctx(primary)** (из-за [litellm#31557](https://github.com/BerriAI/litellm/issues/31557) — fallback с меньшим окном молча падает); исключения помечены `[ctx-exception]` для агентов с заведомо короткими диалогами;
     - L3 — disaster recovery через второй провайдер `bailian-token-plan` (ручное переключение frontmatter);
     - vision-агенты (view-image) — fallback только на vision-модели;
     - роутеры и identity probes — только модели с доказанной JSON-стабильностью.
  2. **Полную матрицу 35 агентов** (скопировать из RESEARCH_LLM_FALLBACK.md, строки 202–238 — все 35 строк с обоснованиями; значения ниже в «Приложении A» данного плана).
  3. **Агрегированные цепочки уровня моделей** (10 уникальных primary) — YAML из Op 3.2.
  4. **Ограничение агрегации** (исследование, строка 278): LiteLLM применяет fallback на уровне модели, не агента; агент-специфичные отличия (L2 identity probes = GLM-5.3-Flash (res); L2 plan-reviewer-simple = QWEN3.7-plus; L2 plan-writer-complex = Kimi K3; L2 research-writer-simple = GLM-5.2 (res); удешевлённые цепочки devops-readonly / generate-image* / git-commit через MiniMax-M2.7) на proxy-уровне НЕ реализуются — для них действует цепочка их primary-модели; постатная дифференциация возможна только локально (смена frontmatter по runbook).
  5. **Уровень skill image-gen** (исследование, строки 242–245):
     | Назначение | Primary | Fallback L1 | Fallback L2 |
     |-----------|---------|-------------|-------------|
     | Image-gen (Gemini) | gemini/gemini-3-pro-image | gemini/gemini-3.1-flash-image | gpt-image-2 |
     | Image-gen (GPT) | gpt-image-1.5 | gpt-image-2 | gemini/gemini-3.1-flash-image |
- **Verify:** `rg -n "LLM Fallback Chains" ARCHITECTURE.md` → 1 совпадение; матрица содержит 35 строк; повторный прогон consistency-checker (Op 2.3) без замечаний.
- **Risk:** раздел увеличивает объём ARCHITECTURE.md (676 строк сейчас) — рост контекста для consistency-checker. Acceptable. **Откат:** `git checkout -- ARCHITECTURE.md` / удалить раздел.

### Operation 3.2: Подготовить BIFROST_FALLBACK_REQUEST.md (запрос админам Bifrost)
- **File:** `P:\Programming\Рефакторинг\BIFROST_FALLBACK_REQUEST.md` (новый)
- **Action:** создать документ-запрос для администраторов `hcbifrost.herocraft.com` со следующей YAML-конфигурацией (исследование, строки 254–273 — сохранить без изменений):
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
  Дополнительно включить в документ:
  1. Список fallback-цепочек для каждой из 10 моделей с обоснованием (из матрицы).
  2. **Предупреждения для админов:**
     - имена моделей содержат пробелы и скобки (`GLM-5.3 (res)`, `GLM-5.3-Flash (res)`) — проверить экранирование в YAML-ключах и URL-роутинге (исследование, Limitations №4);
     - перед применением — верификация доступности каждой fallback-модели (`GET /models` или тестовые запросы; Limitations №2 — внутренние версии моделей могут отличаться от публичных);
     - правило ctx(fallback) ≥ ctx(primary) (litellm#31557);
     - опционально: `context_window_fallbacks` и `content_policy_fallbacks` (docs.litellm.ai/docs/proxy/reliability).
  3. Тестовый план из Op 3.3.
  4. Указание на наблюдаемость: spend logs пишут `attempted_fallbacks` и `original_model_group`; заголовок ответа `x-litellm-model-id`.
- **Verify:** файл существует; YAML парсится (`python -c "import yaml,sys; yaml.safe_load(open('BIFROST_FALLBACK_REQUEST.md').read().split('```yaml')[1].split('```')[0])"` или yamllint по извлечённому блоку); 10 цепочек + default_fallbacks присутствуют.
- **Risk:** админы отклонят запрос или не ответят → переход к Phase 4 (альтернативные стратегии). Документ от этого не теряет ценности (фиксация намерения). **Откат:** не требуется (новый .md-файл).

### Operation 3.3: Тестовый план после применения конфигурации админами
- **File:** `P:\Programming\Рефакторинг\BIFROST_FALLBACK_REQUEST.md` (раздел «Test Plan» — часть Op 3.2)
- **Action:** зафиксировать шаги приёмки (выполняются ПОСЛЕ того, как админы применят YAML):
  1. `GET https://hcbifrost.herocraft.com/litellm/v1/models` — все 10 primary + все fallback-модели присутствуют и активны.
  2. Для каждой из 10 цепочек: штатный запрос к primary (200 OK); затем (по возможности — админы симулируют 429/500 или переводят primary в cooldown) — проверить, что ответ пришёл от fallback: заголовок `x-litellm-model-id` указывает fallback-модель, spend log содержит `attempted_fallbacks` и `original_model_group`.
  3. Context-window тест: запрос, превышающий окно primary, но влезающий в fallback → `context_window_fallbacks` срабатывает (требуется `enable_pre_call_checks: true`).
  4. Vision-тест цепочки `Kimi K2.6 → Kimi K2.7 → GLM-5.3-Flash (res)`: запрос с изображением к каждому звену (Limitations №5 — мультимодальность view-image не проверена эмпирически).
  5. Тест thinking-деградации (Limitations №3): цепочка `qwen3.8-max → atlas/qwen3.8-max` — у апстрим-варианта нет `options.thinking`; зафиксировать фактическое поведение для dev-planner / plan-writer-complex / devops-reviewer.
  6. Регрессия opencode: запуск типовой сессии (orchestrator → worker → utility) — убедиться, что fallback прозрачен для opencode и identity-lock не ломается (плагин привязан к имени агента, не к модели — исследование, строка 204).
- **Verify:** чек-лист из 6 пунктов, все зелёные; результаты записать в раздел «Test Results» того же файла.
- **Risk:** тесты выявят нерабочие fallback-модели (квоты/имена) → итерация запроса к админам с корректировкой цепочек. **Откат:** админы откатывают `litellm_settings.fallbacks` (конфигурация аддитивна, primary-трафик не затрагивает).

### Operation 3.4: Гигиена — проверка отсутствия per-agent `model` в opencode.json
- **File:** `C:\Users\Admin\.config\opencode\opencode.json` (read-only проверка)
- **Action:** убедиться, что в секции `agent` нет полей `model` (мёртвый конфиг — frontmatter побеждает; исследование, Recommendations §4.3). Предварительный grep `"model"\s*:` совпадений в файле не нашёл — операция подтверждает это и фиксирует правило в ARCHITECTURE.md §Permission Authority (одна фраза: «per-agent `model` в opencode.json не задаётся — только frontmatter»).
- **Verify:** `rg -n "\"model\"" C:\Users\Admin\.config\opencode\opencode.json` → 0 совпадений в agent-секциях.
- **Risk:** нет (проверка). Если совпадения найдутся — удалить их отдельной операцией с откатом из бэкапа (Op 1.1).

---

## Phase 4: Optimization — альтернативные стратегии и graceful degradation (НИЗКИЙ)

> Выполняются в любом случае (не зависят от ответа админов Bifrost): покрывают сценарий «админы не отвечают» и локальную отказоустойчивость.

### Operation 4.1: Задать small_model для служебных задач
- **File:** `C:\Users\Admin\.config\opencode\opencode.json` (корневой уровень конфига)
- **Action:** `small_model` сейчас **не задан** (подтверждено grep — используется дефолт opencode). Добавить:
  ```json
  "small_model": "bifrost-litellm/GLM-5.3-Flash (res)"
  ```
  Обоснование: дешёвая модель с резервной квотой и 1M контекста; `small_model` используется только для служебных задач (генерация заголовков сессий) — не fallback в полном смысле, но снижает нагрузку на флагманы и даёт служебным операциям независимый от primary-моделей пул. Альтернатива: `bifrost-litellm/MiniMax-M2.7-highspeed`.
- **Verify:** создать новую сессию в opencode → заголовок генерируется; в логах (`~/.local/share/opencode/log/`) модель заголовков = GLM-5.3-Flash (res); ошибок провайдера нет.
- **Risk:** имя модели с пробелами/скобками может некорректно резолвиться в `small_model` (не проверено). **Откат:** удалить строку `small_model` (вернуться к дефолту); при проблеме экранирования — попробовать `MiniMax-M2.7-highspeed`.

### Operation 4.2: Создать FALLBACK_RUNBOOK.md (ручные действия при инциденте)
- **File:** `P:\Programming\Рефакторинг\FALLBACK_RUNBOOK.md` (новый)
- **Action:** документировать пошаговый runbook:
  1. **Диагностика:** признаки недоступности модели (ошибки 429/500 от `bifrost-litellm` в логах opencode, `ContextWindowExceededError`, таймауты Task-вызовов); где смотреть логи (`~/.local/share/opencode/log/`, storage/session_diff).
  2. **L1/L2 — локальное переключение frontmatter:** при недоступности primary-модели агента отредактировать `model:` в `C:\Users\Admin\.config\opencode\agents\<agent>.md` на L1, затем L2 из матрицы (Приложение A). Пример для worker:
     ```yaml
     # было:
     model: bifrost-litellm/MiniMax-M3
     # L1:
     model: bifrost-litellm/GLM-5.3 (res)
     # L2:
     model: bifrost-litellm/deepseek-v4-pro
     ```
     Перезапустить сессию (модель резолвится на старте сессии/агента — zread: «единственный на сессию/агента»).
  3. **L3 — disaster recovery при полном отказе Bifrost:** переключить критичных агентов на `bailian-token-plan/<model>`: `qwen3.7-plus` (роутеры, bugfix, consistency-checker), `deepseek-v4-pro` (кодинг), `kimi-k2.6` (view-image), `glm-5.2`, `MiniMax-M2.5` (лёгкие задачи). Требование: Op 1.3 подтвердил работоспособность провайдера.
  4. **Откат:** вернуть исходное значение `model:` (таблица «до» хранится в ARCHITECTURE.md §Subagent Models).
  5. **Мониторинг апстрима:** отслеживать [opencode#8687](https://github.com/anomalyco/opencode/issues/8687) (native fallback) и [#43324](https://github.com/anomalyco/opencode/issues/43324) (quota-aware auto-retry) — при релизе перейти на нативный механизм и упростить runbook.
  6. Ссылка на статус запроса админам (BIFROST_FALLBACK_REQUEST.md) и результаты его тест-плана.
- **Verify:** файл существует; каждая из 10 primary-моделей упомянута в runbook с L1/L2/L3; команды переключения воспроизводимы (dry-run на одном некритичном агенте, например summarizer, с возвратом).
- **Risk:** runbook устареет после применения proxy-конфигурации (L1/L2 станут автоматическими). **Откат/актуализация:** после Op 3.3 добавить в runbook пометку «L1/L2 работают автоматически на proxy; ручное переключение — только для L3 и агент-специфичных исключений».

### Operation 4.3: Предложения по graceful degradation в промптах агентов (документировать, НЕ применять сразу)
- **File:** `P:\Programming\Рефакторинг\FALLBACK_RUNBOOK.md` (раздел «Proposed prompt changes»)
- **Action:** зафиксировать предложения (применение — отдельным DEV-пайплайном после ревью, т.к. правка промптов primary-агентов затрагивает identity-lock):
  1. **orchestrator / plankestrator:** при получении provider error из Task-вызова — не повторять вызов бесконечно; одна повторная попытка, затем сообщение пользователю со ссылкой на FALLBACK_RUNBOOK.md (модель субагента недоступна, требуется ручное переключение).
  2. **primary-агенты:** не менять модель на лету внутри сессии (невозможно технически — модель фиксируется на сессию); вместо этого — явная эскалация пользователю.
  3. **worker/bugfix/execute-bug:** при деградации качества после fallback на не-thinking модель (Limitations №3) — предупреждать в выводе, что модель заменена и результат требует дополнительного ревью dev-reviewer.
- **Verify:** раздел существует; каждое предложение помечено «НЕ применено, требует DEV-пайплайна».
- **Risk:** если применить сразу без ревью — поломка identity-lock / workflow-enforcement. Поэтому — только документирование. **Откат:** не требуется.

### Operation 4.4 (опционально): Логирование provider errors в workflow-enforcement.ts
- **File:** `~/.config/opencode/plugins/workflow-enforcement.ts` (или `P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts`)
- **Action:** добавить хук `message.updated` с логированием provider-ошибок (429/500/ContextWindowExceeded) в `log/` — раннее обнаружение деградации модели (исследование, Priority 3). Это DEV-задача: выполнять через orchestrator (DEV SIMPLE: worker → utility), не в рамках этого плана напрямую.
- **Verify:** после внедрения — спровоцировать ошибку (невалидная модель в тестовой сессии) и убедиться, что запись появилась в логе.
- **Risk:** хук может замедлить обработку сообщений / конфликтовать с существующими 6 хуками плагина (PLUGIN.md). **Откат:** git revert коммита плагина; enforcement-логика не затрагивается (хук чисто наблюдательный).

---

## Phase 5: Финальная валидация и приёмка

### Operation 5.1: Сквозная проверка критериев успеха
- **File:** — (проверки)
- **Action:** последовательно проверить SC-1…SC-5:
  ```
  rg -c "^\| \d+ \| .* \| .* \| .* \| .* \| .* \|" P:\Programming\Рефакторинг\ARCHITECTURE.md   # матрица fallback (6 колонок): 35 строк (SC-1); routing-таблицы имеют 3 колонки и не матчатся
  rg -n "sk-sp-" C:\Users\Admin\.config\opencode\opencode.json          # 0 совпадений (SC-3)
  rg -n "qwen3.8-max" P:\Programming\Рефакторинг\ARCHITECTURE.md        # dev-planner + devops-reviewer (SC-2)
  dir P:\Programming\Рефакторинг\BIFROST_FALLBACK_REQUEST.md            # существует (SC-4)
  dir P:\Programming\Рефакторинг\FALLBACK_RUNBOOK.md                    # существует (SC-5)
  ```
- **Verify:** все 5 критериев зелёные.
- **Risk:** частичное выполнение (админы не ответили) → SC-4 считается выполненным по факту готовности документа, применение — вне контроля; зафиксировать статус в отчёте.

### Operation 5.2: Прогон consistency-checker и коммит
- **File:** — (агент + git)
- **Action:** запустить consistency-checker (полный прогон: ARCHITECTURE.md ↔ agents/*.md ↔ AGENTS.md); при зелёном результате — коммит через агента **git-commit** (HARD RULE: никогда не коммитить напрямую). Сообщения: `docs(architecture): sync subagent models table + add fallback chains`, `docs: add bifrost fallback request and runbook`, `chore(security): externalize bailian api key`.
- **Verify:** git log содержит коммиты; working tree чист.
- **Risk:** consistency-checker находит новые расхождения → цикл rework (max 3) по стандартному пайплайну. **Откат:** git revert.

---

## Риски и откаты (сводно)

| Риск | Вероятность | Митигция | Откат |
|------|-------------|----------|-------|
| Админы Bifrost не отвечают / отклоняют запрос | Высокая | Phase 4 выполняется независимо: runbook ручного переключения L1/L2/L3, small_model, graceful degradation | Не требуется — локальные стратегии работают автономно |
| Ротация ключа ломает bailian-token-plan | Низкая (провайдер не используется агентами) | Порядок Op 1.2: сначала новый ключ + проверка (Op 1.3), потом отзыв старого | Выпустить ещё один ключ; восстановить env-переменную |
| Бэкап `opencode.json.bak-2026-09-07` сохраняет скомпрометированный ключ в plaintext | Средняя (если забыть удалить) | Op 1.1: удаление бэкапа — обязательный шаг после Op 1.3; Op 1.2 п.4: grep по каталогу конфига, не только по проекту; SC-3 не засчитывается до удаления бэкапа | Удалить бэкап; ключ в любом случае отзывается в Op 1.2 п.3 |
| Синхронизация ARCHITECTURE.md ломает consistency-checker | Средняя | Op 2.0 (эталон из frontmatter) + Op 2.3 (валидация сразу после) | `git checkout -- ARCHITECTURE.md` (+ копии) |
| Fallback-модель недоступна/имеет меньший ctx (litellm#31557) | Средняя | Правило ctx(fallback) ≥ ctx(primary); `[ctx-exception]` только для коротких диалогов; верификация `GET /models` до применения (Op 3.3 п.1) | Админы корректируют цепочку; локально — следующее звено L2 |
| Имена моделей с пробелами/скобками ломают YAML/URL | Средняя | Явное предупреждение админам (Op 3.2 п.2); тест small_model (Op 4.1) | Переименование через model alias на proxy (запрос админам) |
| Thinking-деградация при fallback (atlas/qwen3.8-max без options.thinking) | Средняя | Op 3.3 п.5 — эмпирический тест; предупреждение в промптах (Op 4.3 п.3) | Исключить atlas-звено из цепочки qwen3.8-max, заменить L1 на GLM-5.3 (res) |
| Правка промптов primary-агентов ломает identity-lock | Низкая (не применяется в этом плане) | Op 4.3 — только документирование; применение через отдельный DEV-пайплайны с ревью | git revert |
| opencode.json правится неавторизованным агентом | Низкая | Секция «Исполнители операций»: .json правит только worker/пользователь; бэкап перед каждой правкой (Op 1.1) | Восстановление из `.bak` |

## Тестирование (стратегия)

1. **Статические проверки** после каждой операции — команды `rg` в полях Verify (мгновенная обратная связь).
2. **consistency-checker** — после Phase 2 и после Phase 5 (структурная валидация документации).
3. **Функциональные тесты провайдеров** — Op 1.3 (bailian `/models` + chat-completion), Op 4.1 (генерация заголовка сессии).
4. **Приёмочные тесты proxy** — Op 3.3 (6 пунктов: models, 10 цепочек, context-window, vision, thinking, регрессия opencode) — выполняются только после применения YAML админами.
5. **Регрессия пайплайнов** — контрольный прогон BUGFIX SIMPLE (bugfix-triage → worker → utility) и PLAN SIMPLE после всех фаз: identity lock держится, JSON-валидация плагина без новых ошибок.

## Оценка трудоёмкости

| Фаза | Трудоёмкость | Комментарий |
|------|--------------|-------------|
| Phase 1 | 0.5–1 ч (+ ожидание пользователя на ротацию в консоли Alibaba) | Правка 1 строки + ручная ротация + curl-проверки |
| Phase 2 | 1–2 ч | 2 строки + 14 строк таблицы × 3 файла + валидация |
| Phase 3 | 2–3 ч (+ неопределённый срок ответа админов Bifrost) | Копирование матрицы, оформление запроса, тест-план |
| Phase 4 | 1–2 ч (Op 4.4 — отдельная DEV-задача, +1–2 ч) | small_model + runbook + документирование предложений |
| Phase 5 | 0.5 ч | Проверки + git-commit через агента |
| **Итого** | **5–8.5 ч** активной работы; применение на proxy — вне контроля | Критический путь: Phase 1 (безопасность) не блокируется ничем |

---

## Приложение A: Матрица fallback для всех 35 агентов

(копия из RESEARCH_LLM_FALLBACK.md строки 202–238; префикс `bifrost-litellm/` опущен; предназначена для вставки в ARCHITECTURE.md в Op 3.1)

| # | Агент | Основная модель | Fallback L1 | Fallback L2 | Обоснование |
|---|-------|-----------------|-------------|-------------|-------------|
| 1 | orchestrator | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Роутер: критичны JSON-стабильность и instruction following; L1 — та же семья Qwen с 1M ctx; L2 — флагман с thinking. Плагин identity-lock привязан к имени агента, не к модели — смена безопасна. |
| 2 | plankestrator | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Аналогично orchestrator. |
| 3 | orchestrator-identity-probe | QWEN3.7-plus | qwen3.8-max | GLM-5.3-Flash (res) | Задача тривиальна (ответ-пробник), но должна работать всегда → L2 самый дешёвый/доступный. |
| 4 | plankestrator-identity-probe | QWEN3.7-plus | qwen3.8-max | GLM-5.3-Flash (res) | См. #3. |
| 5 | bugfix-triage | GLM-5.3-Flash (res) | GLM-5.3-Flash | MiniMax-M2.7-highspeed | L1 — та же модель, основной квотный пул (res↔main); L2 — быстрая 204K модель `[ctx-exception: 204K < 1M primary; диалог triage короткий]`. |
| 6 | bugfix | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Кодинг + bash; L1 — старшая Qwen (1M, thinking); L2 — топ open-weights coding. |
| 7 | plan-bug | MiniMax-M3 | GLM-5.3 (res) | deepseek-v4-pro | Планирование багфикса — reasoning; L1/L2 — флагманы с thinking и 1M ctx. |
| 8 | execute-bug | GLM-5.3 (res) | GLM-5.3 | Kimi K3 | L1 — основной пул той же модели; L2 — Kimi K3 (1M/1M, сильный coding). |
| 9 | worker | MiniMax-M3 | GLM-5.3 (res) | deepseek-v4-pro | Основной исполнитель: лучший coding + tool calling; L2 — лидер SWE-bench Verified. |
| 10 | rework | Kimi K3 | GLM-5.3 (res) | deepseek-v4-pro | Rework по фидбеку — точечные правки; флагманы взаимозаменяемы. |
| 11 | dev-planner | qwen3.8-max | atlas/qwen3.8-max | GLM-5.3 (res) | L1 — та же модель через апстрим atlas (другая квота); L2 — флагман с 1M ctx. |
| 12 | dev-professor | GLM-5.3 (res) | GLM-5.3 | Kimi K3 | Кодинг + объяснения; L1 — основной пул. |
| 13 | dev-reviewer | Kimi K3 | GLM-5.3 (res) | deepseek-v4-pro | Ревью: флагманы с thinking и 1M ctx. Kimi K2.7 как L1 отвергнут: 262K < 1M primary (litellm#31557). |
| 14 | consistency-checker | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Валидация против ARCHITECTURE.md — длинный контекст + точность. |
| 15 | utility | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | Синтаксис-чек: скорость важнее глубины; L1 — тот же вес в highspeed-пуле; L2 — 1M ctx запас. |
| 16 | docs-writer | mimo-v2.5-pro | mimo-v2.5 | Qwen3.5-plus | L1 — вариант той же семьи (text-only задачи docs покрывает); L2 — 1M, thinking, сильный текст. |
| 17 | docs-planner | aliyun/qwen3.8-flash | qwen3.6-flash | MiniMax-M2.7-highspeed | L1 — flash-модель Qwen с 1M ctx; L2 — быстрая `[ctx-exception: 204K < 262K primary; план документации короткий]`. |
| 18 | research-writer-simple | mimo-v2.5-pro | mimo-v2.5 | GLM-5.2 (res) | L1 — та же семья; L2 — 1M ctx для синтеза источников. |
| 19 | research-writer-complex | Kimi K3 | GLM-5.3 (res) | deepseek-v4-pro | Complex research — глубокий reasoning; Kimi K2.7 (262K) < primary (1M) — не подходит; L2 — 1M ctx + 393K output. |
| 20 | research-reviewer | GLM-5.3 (res) | GLM-5.3 | Kimi K3 | L1 — основной пул той же модели. |
| 21 | plan-writer-simple | QWEN3.7-plus | qwen3.8-max | GLM-5.3 (res) | Простые планы — семейная замена достаточна. |
| 22 | plan-writer-complex | qwen3.8-max | atlas/qwen3.8-max | Kimi K3 | L1 — другой апстрим той же модели; L2 — флагман с наибольшим output (1M). |
| 23 | plan-reviewer-simple | GLM-5.3 (res) | GLM-5.3 | QWEN3.7-plus | L1 — основной пул. |
| 24 | plan-reviewer-complex | Kimi K3 | GLM-5.3 (res) | deepseek-v4-pro | См. #13. |
| 25 | devops-agent | MiniMax-M3 | GLM-5.3 (res) | MiniMax-M2.7-highspeed | DevOps-команды короткие `[ctx-exception: 204K < 1M primary]`. |
| 26 | devops-reviewer | qwen3.8-max | atlas/qwen3.8-max | QWEN3.7-plus | См. #11. |
| 27 | devops-readonly | MiniMax-M3 | MiniMax-M2.7 | GLM-5.3-Flash (res) | Read-only — можно дешевле `[ctx-exception: L1 204K < 1M primary]`. |
| 28 | mcp-github | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | MCP-вызовы + суммаризация; лёгкая задача. |
| 29 | mcp-read | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | См. #28. |
| 30 | mcp-search | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | См. #28. |
| 31 | summarizer | MiniMax-M2.7 | MiniMax-M2.7-highspeed | GLM-5.3-Flash (res) | См. #28; L2 даёт запас контекста до 1M для длинных документов. |
| 32 | view-image | Kimi K2.6 | Kimi K2.7 | GLM-5.3-Flash (res) | **Только vision-модели.** L1 — прямой апгрейд семьи (vision+thinking); L2 — vision с 1M ctx; альтернатива L2: qwen3.8-max (img+video). |
| 33 | generate-image | MiniMax-M3 | MiniMax-M2.7 | GLM-5.3-Flash (res) | LLM только оркестрирует skill image-gen (gemini-3-pro-image) `[ctx-exception: L1 204K < 1M primary]`. |
| 34 | generate-image-gpt | MiniMax-M3 | MiniMax-M2.7 | GLM-5.3-Flash (res) | См. #33 (skill → gpt-image-1.5) `[ctx-exception: L1]`. |
| 35 | git-commit | MiniMax-M3 | MiniMax-M2.7 | GLM-5.3-Flash (res) | Короткие conventional-commit сообщения `[ctx-exception: L1 204K < 1M primary]`. |

## Приложение B: Целевая таблица Subagent Models для ARCHITECTURE.md (результат Op 2.1)

```markdown
## Subagent Models

| Agent | Model |
|-------|-------|
| worker | bifrost-litellm/MiniMax-M3 |
| bugfix-triage | bifrost-litellm/GLM-5.3-Flash (res) |
| bugfix | bifrost-litellm/QWEN3.7-plus |
| plan-bug | bifrost-litellm/MiniMax-M3 |
| execute-bug | bifrost-litellm/GLM-5.3 (res) |
| dev-planner | bifrost-litellm/qwen3.8-max |
| dev-professor | bifrost-litellm/GLM-5.3 (res) |
| dev-reviewer | bifrost-litellm/Kimi K3 |
| rework | bifrost-litellm/Kimi K3 |
| consistency-checker | bifrost-litellm/QWEN3.7-plus |
| docs-writer | bifrost-litellm/mimo-v2.5-pro |
| docs-planner | bifrost-litellm/aliyun/qwen3.8-flash |
| utility | bifrost-litellm/MiniMax-M2.7 |
| mcp-github | bifrost-litellm/MiniMax-M2.7 |
| mcp-read | bifrost-litellm/MiniMax-M2.7 |
| mcp-search | bifrost-litellm/MiniMax-M2.7 |
| summarizer | bifrost-litellm/MiniMax-M2.7 |
| devops-agent | bifrost-litellm/MiniMax-M3 |
| devops-reviewer | bifrost-litellm/qwen3.8-max |
| orchestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
| plankestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
| plan-writer-simple | bifrost-litellm/QWEN3.7-plus |
| plan-writer-complex | bifrost-litellm/qwen3.8-max |
| plan-reviewer-simple | bifrost-litellm/GLM-5.3 (res) |
| plan-reviewer-complex | bifrost-litellm/Kimi K3 |
| research-writer-simple | bifrost-litellm/mimo-v2.5-pro |
| research-writer-complex | bifrost-litellm/Kimi K3 |
| research-reviewer | bifrost-litellm/GLM-5.3 (res) |
| devops-readonly | bifrost-litellm/MiniMax-M3 |
| git-commit | bifrost-litellm/MiniMax-M3 |
| generate-image | bifrost-litellm/MiniMax-M3 |
| generate-image-gpt | bifrost-litellm/MiniMax-M3 |
| view-image | bifrost-litellm/Kimi K2.6 |

Note: primary agents (orchestrator, plankestrator) run on `bifrost-litellm/QWEN3.7-plus`
and are documented in §Identity Lock Mechanism (v3), item 5 — not duplicated here.
```

---

```json
{
  "agent": "plan-writer-complex",
  "plan_file": "PLAN_LLM_FALLBACK.md",
  "plan_written": true,
  "phases": 5,
  "operations": 17,
  "next_action": "plan-reviewer-complex should read from plan_file"
}
```
