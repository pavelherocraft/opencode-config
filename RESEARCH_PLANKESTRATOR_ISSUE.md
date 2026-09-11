# Исследование: почему plankestrator не делегирует задачи субагентам

## Executive Summary

Корневая причина — **структурная асимметрия между orchestrator и plankestrator**: work product orchestrator (код, файлы, команды) физически заблокирован permissions (`edit: deny`, `bash: deny`), а work product plankestrator — это **текст**, для генерации которого не нужен ни один запрещённый инструмент. Доступные plankestrator инструменты (`read`/`grep`/`glob`) — это ровно тот набор, который нужен для поверхностного исследования, поэтому affordance инструментов провоцирует self-work. Промпт смягчает, но не устраняет проблему: граница «inspect ONLY to classify» субъективна, few-shot примеров нет, запреты сформулированы только негативно, а plugin проверяет форму (JSON, routing table), но не семантику сообщения (не отличает «классификацию» от «самостоятельного исследования»).

---

## Root Cause Analysis

### Причина 1 (фундаментальная): текстовый work product не блокируется permissions

| | orchestrator | plankestrator |
|---|---|---|
| Work product | код, файлы, команды | текст (план / исследование) |
| Инструменты для self-work | `edit`, `write`, `bash` — **deny** | не нужны — текст генерируется в теле сообщения |
| Физическая возможность нарушить | НЕТ для кода/файлов/команд (v3 lockdown, ARCHITECTURE.md стр. 192); текстовые объяснения возможны, но явно запрещены промптом (orchestrator.md стр. 121) | ДА, всегда (текст и есть work product) |

Из ARCHITECTURE.md (строка 192): *«orchestrator and plankestrator kept "doing things themselves" because the old config had edit: "ask"... v3 lockdown removes those tools from the model's toolset entirely»*. Lockdown закрыл orchestrator, но для plankestrator он закрывает только **запись** результата, а не **генерацию** результата в тексте ответа.

### Причина 2: affordance разрешённых инструментов совпадает с инструментами исследования

plankestrator имеет `read: allow`, `grep: allow`, `glob: allow` (frontmatter `plankestrator.md` строки 9–11, подтверждено `opencode.json` строки 1405–1407). Для RESEARCH-задачи «прочитать файлы и обобщить» — это полный необходимый набор. Модель, обученная быть полезной, видя доступные инструменты и вопрос пользователя, следует affordance: читает → обобщает → отвечает сама.

### Причина 3: граница инспекции субъективна и самооцениваема

`plankestrator.md` строка 58:
> «(Optional) Inspect to classify ONLY: read/glob/grep to determine type and complexity. **The moment you can fill the JSON — STOP inspecting.**»

«The moment you can fill the JSON» — это self-assessment. Модель рационализирует продолжение чтения («мне нужно ещё один файл, чтобы оценить complexity»). Критерий complexity («1 file / 1 source» vs «2+ files / 2+ sources», строки 106–107) **провоцирует** инспекцию: чтобы отличить SIMPLE от COMPLEX, модель чувствует необходимость посмотреть на файлы, хотя для RESEARCH-запроса сложность очевидна из текста запроса (число вопросов, источников, объектов сравнения).

### Причина 4: plugin не проверяет семантику, только форму

Plugin (`workflow-enforcement.ts`) валидирует:
- routing table (строки 636–693);
- JSON-поля и значения (строки 955–1040);
- запрет action-инструментов (Gate A, строки 467–511);
- forbidden vocabulary — но только терминологию **другого** агента (строки 89–100).

Plugin **не проверяет**:
- содержит ли текст сообщения plan/research-контент (самостоятельная работа);
- количество вызовов read/grep/glob (нет бюджета инспекции);
- стадию пайплайна (инспекция после старта пайплайна не запрещена);
- «не более одного Task за ход» (правило из промпта строка 114 в plugin не реализовано).

При этом сам plugin в комментарии (строки 579–583) признаёт: *«direct read/glob/grep is a convenience for quick lookups, not a substitute for delegation»* — но это комментарий, не enforcement.

---

## Prompt Analysis (`agents/plankestrator.md`, 118 строк)

### Недостаточно чёткие инструкции

1. **Строка 58 — опциональная инспекция без количественной границы.**
   У orchestrator есть жёсткий числовой лимит: *«To count steps you MAY read the plan file once — the ONLY direct file read you are allowed»* (`orchestrator.md` строка 114). У plankestrator такого лимита нет — инспекция ограничена только субъективным «the moment you can fill the JSON».

2. **Отсутствует запрет инспекции на ходах 2..N.**
   У orchestrator есть прямое правило: *«🚫 No read/glob/grep during pipeline execution (Turns 2..N)»* (`orchestrator.md` строка 124). В `plankestrator.md` аналога **нет** — секция PROHIBITIONS (строки 109–118) не запрещает инспекцию после старта пайплайна.

3. **Строка 77 — COMPLETE-ход разрешает summary, которое модель раздувает.**
   *«One short user-facing summary: which agents ran, what they produced, where the output file lives»* — модель интерпретирует «what they produced» как лицензию пересказать содержание исследования, фактически дублируя работу research-writer в своём сообщении.

4. **Строка 72 (а также 19 и 111–112) — «don't analyze» сформулировано негативно.**
   *«don't analyze, don't critique, don't summarize its content as your own»* — чисто негативная формулировка без позитивной модели поведения. Общепринятая практика prompt engineering: позитивные инструкции («делай X») удерживаются надёжнее запретов («не делай Y») — утверждение основано на общеизвестных паттернах, эмпирически для QWEN3.7-plus не проверялось (см. Ограничения).

5. **Нет few-shot примеров.**
   Весь промпт декларативен: таблица + алгоритм + запреты. Ни одного примера правильного хода (identity line → JSON → Task call) и ни одного примера нарушения с коррекцией. Для router-роли, противоречащей RLHF-«полезности» модели, примеры критичны.

### Места вольной интерпретации

| Строка | Текст | Как интерпретирует модель |
|---|---|---|
| 58 | «Inspect to classify ONLY» | «Классификация требует понимания → читаю файлы подробно» |
| 106–107 | complexity по числу файлов/источников | «Надо посмотреть файлы, чтобы посчитать» |
| 77 | «what they produced» | «Перескажу содержание отчёта» |
| 19 | «You NEVER write plans or research yourself» | «Я не пишу в файл — значит, не нарушаю» (модель не считает текст в сообщении "writing") |
| 59 | view-image как «inspection helper» | Прецедент: инспекция — легитимная активность, размывает границу |

### Противоречия и неоднозначности

- **Turn 1 (строки 56–62) допускает в одном ходу**: инспекцию (несколько read/grep) + JSON + Task call. Это размывает принцип «один ход = одно действие» и нормализует многошаговую инспекцию.
- **Противоречие между description и поведением**: frontmatter description говорит «NEVER edits files or runs commands» — но не говорит «NEVER investigates». Слово «research» в описании роли («Planning and research state machine») модель может прочитать как «я исследователь».
- **`type=RESEARCH` правила (строка 99)** срабатывают на слова «investigate», «analyze», «разберись» — те же слова описывают и действия самого plankestrator при инспекции, создавая ролевую путаницу («я должен разобраться»).

---

## Model Behavior Analysis (QWEN3.7-plus, temperature 0.1)

### Почему модель не следует инструкциям

1. **RLHF-конфликт «helpfulness vs routing».** Базовое обучение инструктивных моделей оптимизирует «ответь на вопрос пользователя». Роль «роутер, который НЕ отвечает, а делегирует» — противоестественна для этой оптимизации. Каждый запрос пользователя — аттрактор, тянущий модель к прямому ответу. Чем сильнее запрос похож на вопрос («почему», «исследуй», «сравни»), тем сильнее аттрактор. RESEARCH-запросы — самый сильный случай.

2. **Temperature 0.1 не решает проблему.** Низкая температура делает поведение детерминированным, но не правильным: если наиболее вероятная траектория по мнению модели — «прочитать файлы и ответить», она будет стабильно её выбирать.

3. **Длинный промпт с 8 негативными запретами.** Секция PROHIBITIONS — 8 пунктов «🚫 No ...». LLM хуже удерживают множественные негативные ограничения, особенно когда запрещённое действие семантически близко к разрешённому («inspect to classify» vs «inspect to answer» — одно и то же действие read, различие только в намерении, которое модель сама себе атрибутирует постфактум).

4. **Рационализация self-assessment.** Границы вида «STOP when you can fill the JSON» требуют от модели оценить собственную достаточность информации. Известный паттерн: модель генерирует обоснование продолжения («чтобы точно определить complexity, проверю ещё…»), потому что генерация обоснования дешевле, чем остановка.

### Паттерны поведения, ведущие к self-work

| Паттерн | Механизм | Триггер в промпте |
|---|---|---|
| Инспекция → эскалация | read даёт контент → контент провоцирует ответ | строка 58 (опциональная инспекция) |
| «Классификация требует понимания» | рационализация чтения файлов | строки 106–107 (complexity по файлам) |
| Summary-эскалация | COMPLETE-резюме превращается в пересказ | строка 77 |
| Текст ≠ «writing» | модель считает, что «не писать» = «не использовать write tool» | строки 19, 111 |
| Помощь напрямую | RLHF-аттрактор прямого ответа | отсутствие few-shot контрпримеров |

---

## Plugin Enforcement Analysis (`plugins/workflow-enforcement.ts`, 1040 строк)

### Что есть для plankestrator

| Проверка | Строки | Сила |
|---|---|---|
| Routing table (только whitelisted субагенты) | 636–693 | HARD (throw) |
| JSON до Task call | 601–618 | HARD (throw; есть исключения: первый Task call сессии и identity-probe — условие `!isFirstTaskCall`, стр. 603) |
| Запрет action-инструментов (Gate A) | 467–511 | HARD (throw) |
| Валидация JSON-полей и значений | 955–1040 | WARN (только лог) |
| Identity lock / drift | 338–372 | ERROR (лог, не блокирует) |
| Forbidden vocabulary | 405–434 | ERROR (лог, не блокирует) |

### Пробелы, позволяющие self-work

1. **Нет бюджета инспекции.** Gate A разрешает `read`/`glob`/`grep` безлимитно. Нет счётчика вызовов, нет ограничения «только Turn 1».

2. **Нет stage-aware gating.** Plugin не отслеживает, начался ли пайплайн (был ли первый Task call). Можно добавить: для locked primary agent — после первого успешного `task` вызова любые `read`/`grep`/`glob` → throw. WorkflowSteps (строка 81) уже логирует все вызовы — данных достаточно. ⚠️ Нюанс: view-image вызывается через Task ДО классификации (plankestrator.md стр. 59) — определение «пайплайн начался» должно исключать target=view-image, иначе легитимная инспекция Turn 1 будет заблокирована.

3. **Нет семантической проверки контента сообщения.** `FORBIDDEN_VOCAB` (строки 95–99) для plankestrator содержит только orchestrator-термины (`bugfix-triage`, `execute-bug`...). Не содержит маркеров самостоятельного исследования: `## Findings`, `## Research`, `Executive Summary`, `## Analysis`, `### Root Cause`. Такие заголовки в сообщении primary-агента — надёжный сигнал self-work.

4. **Правило «один Task за ход» не реализовано.** Промпт требует (строка 114), plugin не проверяет.

5. **Валидация JSON — только WARN.** `INVALID JSON OUTPUT` логируется как warn (строки 378–390), сообщение пропускается. Модель не получает обратной связи о нарушении. Примечание: смена warn→error меняет лишь видимость в логах для разработчика и НЕ даёт модели обратную связь — для этого нужно расширить throw-гейт (строки 601–618): требовать не «JSON был», а «JSON валиден» перед не-первым Task call.

6. **Комментарий-признание без enforcement** (строки 579–583): plugin знает, что read/glob/grep — «not a substitute for delegation», но не кодирует это в проверку.

### Как усилить plugin (конкретные механизмы)

```typescript
// 1. Inspection budget для locked primary agents
const INSPECTION_BUDGET = 3  // read+grep+glob суммарно за сессию до первого Task
// в tool.execute.before:
if (identityLocked && ["read","grep","glob"].includes(input.tool)) {
  const used = workflowSteps.filter(s => ["read","grep","glob"].includes(s.tool)).length
  // view-image (Task) — инспекционный helper ДО классификации (plankestrator.md стр. 59), не старт пайплайна
  const taskStarted = workflowSteps.some(s => s.tool === "task" && s.target !== "view-image")
  if (taskStarted) throw new Error("⛔ INSPECTION AFTER PIPELINE START — delegate instead")
  if (used >= INSPECTION_BUDGET) throw new Error("⛔ INSPECTION BUDGET EXHAUSTED — classify and delegate NOW")
}

// 2. Маркеры self-work в FORBIDDEN_VOCAB.plankestrator
"## Findings", "## Research", "Executive Summary", "## Analysis",
"### Root Cause", "## Recommendations", "## Overview"
// + эскалация с log до throw для locked agent
```

---

## Сравнение: почему orchestrator делегирует, а plankestrator — нет

| Фактор | orchestrator | plankestrator | Эффект |
|---|---|---|---|
| Self-work физически возможен? | НЕТ (нужны edit/bash — deny) | ДА (текст не требует инструментов) | **Главный фактор** |
| Лимит инспекции | «the ONLY direct file read you are allowed» (стр. 114) | нет числового лимита | plankestrator читает безгранично |
| Запрет инспекции на ходах 2..N | ЕСТЬ (стр. 124) | **ОТСУТСТВУЕТ** | инспекция в середине пайплайна |
| Ack-ритуал делегирования | «→ DELEGATED to \<agent\> for: \<goal\>» (стр. 70) | нет | у orchestrator позитивный ритуал |
| Классификация требует файлов? | Редко: тип определяется ключевыми словами; DEV-complexity тоже считает файлы (стр. 112–113), но чтение ограничено явно («the ONLY direct file read», стр. 114) | complexity «по файлам» — основной сигнал, провоцирует чтение | стр. 106–107 |
| Похожесть задачи на роль | Реализация ≠ классификация (чёткая грань) | «исследуй» ≈ «прочитай и расскажи» (размытая грань) | ролевая путаница |
| Награда за нарушение | Низкая (результат нельзя записать) | Высокая (пользователь получает ответ сразу) | RLHF-аттрактор |

**Вывод:** orchestrator делегирует не потому, что его промпт лучше (они структурно почти идентичны), а потому что у него **отнята физическая возможность** сделать работу, и его классификация не требует контекста. Plankestrator сохраняет и возможность (текст), и соблазн (read/grep/glob), и рационализацию (complexity-правила).

---

## Best Practices для LLM-роутеров

1. **Убирать affordance, а не запрещать словами.** Самый надёжный способ заставить роутер делегировать — не дать ему инструменты для самостоятельной работы. Для plankestrator это означает: либо радикально урезать `read`/`grep`/`glob`, либо жёсткий числовой бюджет через plugin (см. выше). Для RESEARCH-задач классификация (тип + сложность) определяется из текста запроса — инспекция файлов не нужна вообще.

2. **Few-shot примеры > декларативные запреты.** Router-роль конфликтует с helpfulness-обучением; примеры — главный механизм перебить этот prior. Минимум два примера:
   - позитивный: полный правильный Turn 1 (identity → JSON → Task call) для RESEARCH-запроса;
   - негативный с коррекцией: «❌ НЕПРАВИЛЬНО: read файла → объяснение. ✅ ПРАВИЛЬНО: JSON → Task».

3. **Позитивная формулировка роли.** Вместо «You NEVER write plans yourself» — «Your ONLY outputs are: (1) identity line, (2) JSON block, (3) one Task call. Nothing else.» Перечисление разрешённых артефактов сильнее перечисления запрещённых.

4. **Числовые границы вместо self-assessment.** «Max 2 read calls, Turn 1 only» проверяемо; «stop when you can fill the JSON» — нет.

5. **Stage-aware tool gating на уровне runtime.** Промпт — это просьба; plugin — это закон. Всё критичное должно дублироваться throw-гейтом в plugin: бюджет инспекции, запрет инспекции после старта пайплайна, маркеры self-work в тексте.

6. **Ритуал делегирования.** Обязательная ack-строка «→ DELEGATED to X» (как у orchestrator) — позитивное завершение хода, снижающее тягу «добавить что-то от себя».

7. **Классификация из запроса, не из файлов.** Переписать критерии complexity так, чтобы они опирались на текст запроса (число вопросов, объектов сравнения, требование сравнительного анализа), а не на инспекцию кодовой базы. Для RESEARCH+PLAN всегда COMPLEX — убрать неоднозначность.

8. **Сужение COMPLETE-хода.** «Summary = список агентов + путь к файлу. Запрещено пересказывать содержание: оно в файле.»

---

## Recommendations

### Приоритет 1 — Plugin (hard enforcement, эффект немедленный)

1. **Inspection budget**: для locked plankestrator — максимум 2–3 вызова `read`/`grep`/`glob` суммарно, только до первого Task call; далее throw. Данные для проверки уже есть в `workflowSteps`.
2. **Post-pipeline inspection ban**: после первого успешного `task` вызова (кроме `view-image` — инспекционный helper до классификации, plankestrator.md стр. 59) любой `read`/`grep`/`glob` от locked primary agent → throw.
3. **Self-work vocabulary**: расширить `FORBIDDEN_VOCAB.plankestrator` маркерами (`## Findings`, `## Research`, `Executive Summary`, `## Recommendations`, `### Root Cause`) и для locked agent эскалировать с log до throw.
4. **JSON validation → enforcement**: поднять уровень `INVALID JSON OUTPUT` с warn до error (видимость в логах) и расширить throw-гейт 601–618: блокировать не-первый Task call, пока `validateJSONOutput()` не вернёт `valid: true` — только так модель получит обратную связь.

### Приоритет 2 — Промпт (снижение соблазна)

5. Добавить в PROHIBITIONS аналог правила orchestrator: *«🚫 No read/glob/grep during pipeline execution (Turns 2..N)»* и *«🚫 Max 2 inspection calls total, Turn 1 only»*.
6. Переписать критерии complexity на основе текста запроса (число вопросов/источников/объектов), убрав привязку к «1 file / 2+ files».
7. Добавить секцию `## EXAMPLES` с одним позитивным и одним негативным few-shot примером для RESEARCH-запроса.
8. Добавить ack-строку делегирования: `→ DELEGATED to <agent> for: <goal>` (как у orchestrator, стр. 70).
9. Сузить COMPLETE-ход: «summary = agents ran + output file path. Content recap is FORBIDDEN — it lives in the file.»
10. Позитивная рамка в строке 19: «Your ONLY outputs are: identity line, JSON block, one Task call per turn.»

### Приоритет 3 — Структурный (если 1–2 недостаточно)

11. **Полностью убрать `read`/`grep`/`glob` у plankestrator** (permissions deny + удаление из Gate A whitelist для plankestrator). Классификация RESEARCH/PLAN не требует файлов; если нужен контекст — делегировать `devops-readonly` через Task (он уже в routing table). Это ставит plankestrator в то же положение, что и orchestrator: self-work физически невозможен.
12. Рассмотреть смену формулировки description: убрать слово «research» из описания роли, заменив на «routes planning and research tasks to writer agents».

### Порядок внедрения

Сначала пп. 1–4 (plugin) — они дают детерминированную гарантию независимо от поведения модели. Затем пп. 5–10 (промпт) — снижают частоту срабатывания гейтов. П. 11 — радикальный, но самый надёжный вариант, если после 1–10 нарушения сохраняются.

---

## Источники

- `C:\Users\Admin\.config\opencode\agents\plankestrator.md` (118 строк) — промпт plankestrator
- `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (127 строк) — промпт orchestrator (база сравнения)
- `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (1040 строк) — enforcement plugin
- `C:\Users\Admin\.config\opencode\opencode.json` (строки 1398–1428) — permissions plankestrator
- `P:\Programming\Рефакторинг\ARCHITECTURE.md` (строки 166, 170, 192, 211–224, 245) — требования архитектуры и история v3 lockdown
- `P:\Programming\Рефакторинг\AGENTS.md` (строки 193–201) — определение роли plankestrator

## Ограничения исследования

- Не анализировались реальные логи сессий plankestrator (`~/.local/share/opencode/log/`) — выводы о поведении модели основаны на анализе промпта/конфигурации и известных паттернах LLM, а не на трассировке конкретных нарушений.
- Эффективность few-shot примеров и бюджета инспекции для QWEN3.7-plus не проверена эмпирически — требуется A/B-тест после внедрения.
- Промпты writer-агентов (`plan-writer-*.md`, `research-writer-*.md`) не анализировались — возможно, часть self-work связана с их недоступностью/ошибками, что не проверялось.
