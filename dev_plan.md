# Implementation Plan — Миграция медиа-агентов на media MCP (5 агентов)

**Задача:** создать 4 новых агента (`image-creator`, `video-generator`, `voice-transcriber`, `voice-clone`), переписать `voice-synthesizer` на media MCP, удалить агентов `generate-image`/`generate-image-gpt` и скиллы `audio-synthesize`/`audio-transcribe`/`image-gen`, обновить ВСЕ синхронные копии документации и конфигов.
**Дата инспекции файлов:** 2026-09-27. Все якоря — ТЕКСТОВЫЕ (переживают дрейф номеров строк); номера строк даны только как справка на дату инспекции.
**Исполнитель:** dev-professor (реализует строго из этого файла). Язык промптов агентов — английский (конвенция `agents/*.md`); диалоговые примеры — билингвальные; язык этого плана — русский.
**Инструменты правок:** файловые инструменты (write/edit) в UTF-8. НЕ использовать `Set-Content`/`echo` из PowerShell 5.1 для файлов с кириллицей (риск кодировки).

---

## Goal

Перевести медиа-возможности системы со скиллов (Python/PS-скрипты, локальные файлы) на remote MCP-сервер `media` (уже настроен в `opencode.json` mcp-секции, строки ~1058–1065):

| Было | Стало |
|------|-------|
| `generate-image` + `generate-image-gpt` (скилл `image-gen`, mimo-v2.5) | `image-creator` (MCP: generate_image + edit_image, 7+7 моделей, MiniMax-M3) |
| — (не было) | `video-generator` (MCP: generate_video + video_status, async) |
| — (не было) | `voice-transcriber` (MCP: transcribe_audio, ASR) |
| `voice-synthesizer` (скилл `audio-synthesize`, 3 режима вкл. clone) | `voice-synthesizer` (MCP: synthesize_speech, 3 TTS-модели, 17 голосов) + `voice-clone` (MCP: clone_speech) — отдельные агенты |
| Скиллы `audio-synthesize`, `audio-transcribe`, `image-gen` | Удалены (заменены media MCP) |

**Каталог media MCP подтверждён вызовом `media_media-list_media_models` на этапе планирования** (сервер доступен, модели/голоса соответствуют таблицам ниже).

## Architecture

### Ключевые решения

1. **Source-of-truth + config-sync.** Все правки выполняются в ОДНОЙ авторитетной копии каждого файла, затем размножаются скиллом `config-sync` (группы: agents, config, plugin, architecture, mcp-setup, agents-md, plugin-md) + ручным `Copy-Item` для live-копий `ARCHITECTURE.md`/`MCP_SETUP.md`/`PLUGIN.md` в `C:\Users\Admin\.config\opencode\` (эти 3 копии НЕ входят в группы sync).

   | Файл | Source of truth (правим здесь) | Размножение |
   |------|-------------------------------|-------------|
   | `agents/*.md` (5 новых/изменённых + orchestrator + plankestrator) | `C:\Users\Admin\.config\opencode\agents\` | sync group `agents` → `deploy-package\agents\` |
   | `opencode.json` | `C:\Users\Admin\.config\opencode\opencode.json` | sync group `config` → `deploy-package\opencode.json` |
   | `workflow-enforcement.ts` | `C:\Users\Admin\.config\opencode\plugins\` | sync group `plugin` → `plugins\` → `deploy-package\plugins\` |
   | `ARCHITECTURE.md` | `P:\Programming\Рефакторинг\ARCHITECTURE.md` | sync group `architecture` → `opencode-config\` → `deploy-package\project-files\`; ВРУЧНУЮ → `C:\Users\Admin\.config\opencode\` |
   | `AGENTS.md` | `P:\Programming\Рефакторинг\AGENTS.md` | sync group `agents-md` → все 4 копии (вкл. live) |
   | `MCP_SETUP.md` | `P:\Programming\Рефакторинг\MCP_SETUP.md` | sync group `mcp-setup` → `deploy-package\project-files\`; ВРУЧНУЮ → `C:\Users\Admin\.config\opencode\` |
   | `PLUGIN.md` | `P:\Programming\Рефакторинг\PLUGIN.md` | sync group `plugin-md` → `opencode-config\` → `deploy-package\project-files\`; ВРУЧНУЮ → `C:\Users\Admin\.config\opencode\` |
   | `CHANGELOG.md`, `deploy-package\README.md`, `deploy-package\scripts\verify.ps1` | правятся напрямую (единственные копии / не входят в sync) | — |

2. **Почему НЕ скилл `agent-add`:** он добавляет ОДНОГО агента и не умеет (а) удалять агентов и скиллы, (б) править нестандартные счётчики/таблицы (Skill-only models → Media models, unity-mcp-исключения, Outdated Terms, §11 media-блок, README, verify.ps1), (в) покрывать live-копию `ARCHITECTURE.md` в `.config`. Ручные правки по якорям + config-sync дают полный контроль. Скиллы `backup-snapshot`, `config-sync`, `integrity-check` — ИСПОЛЬЗУЕМ.

3. **Единый permission-профиль медиа-агентов** (frontmatter .md + зеркало в opencode.json): все файловые инструменты и bash — deny (агенты работают ТОЛЬКО через MCP, файлы не сохраняют — все результаты это hosted URL); все посторонние MCP-серверы — deny; `media.*: allow`; `task: deny` (листовые агенты).

4. **Модель всех 5 агентов:** `bifrost-litellm/MiniMax-M3` (роль `executor-cheap` в ARCHITECTURE §Model Roles). Температура: 0.3 (креативные диалоги) / 0.1 (voice-transcriber — дословность).

5. **Порядок замен (ГРАБЛЯ):** при любых глобальных заменах сначала обрабатывать `generate-image-gpt`, потом `generate-image` (иначе вторая замена портит первую). В этом плане все правки — полнострочные якоря, риск минимален, но для rg/sed-зачисток правило обязательно.

### Сводка счётчиков (до → после)

| Счётчик | До | После | Где встречается |
|---------|----|----|-----------------|
| Всего уникальных агентов | 38 | **40** | ARCHITECTURE L59/L61/L121/L144; MCP_SETUP L13/L44/L282/L537/L1063/L1086/L1253/L1272; AGENTS L185; README deploy L97+2=99 контекст |
| Subagents | 36 | **38** | MCP_SETUP L43/L1278; deploy README L97 |
| orchestrator whitelist | 26 | **28** | ARCHITECTURE L7/L57/L65; AGENTS L221; MCP_SETUP L381/L658/L1351; PLUGIN.md; orchestrator.md L26; opencode.json (task-блок orchestrator); workflow-enforcement.ts |
| plankestrator whitelist | 10 | 10 | без изменений |
| Агентских .md файлов (live и deploy) | 38 | **40** | каталоги agents\; verify.ps1 L108 |
| MiniMax-M3 агентов | 11 | **15** | MCP_SETUP L51; ARCHITECTURE L138 |
| mimo-v2.5 агентов | 3 | **1** (scout) | MCP_SETUP L55; ARCHITECTURE L142 |
| Уникальных моделей агентов | 10 | 10 | БЕЗ ИЗМЕНЕНИЙ (mimo-v2.5 остаётся у scout; новые агенты на существующем MiniMax-M3) |
| unity-mcp исключений | 3 | **7** | ARCHITECTURE L696; MCP_SETUP L537 |
| integrity-check аргументы | 38/10/26/10 | **40/10/28/10** | команда Phase 8 + дефолты скриптов (Phase 4.8) |

### Расчёт агентов (проверка арифметики задачи)

Было 38 (2 primary + 36 subagents). Удаляем 2 (generate-image, generate-image-gpt) → 36. Добавляем 4 (image-creator, video-generator, voice-transcriber, voice-clone) → **40** (2 primary + 38 subagents). `voice-synthesizer` модифицируется (0). Whitelist orchestrator: 26 − 2 + 4 = **28**. plankestrator: 10 (без изменений). Grand Total ARCHITECTURE: записей whitelist 28+10=**38**, уникальных whitelisted субагентов 37 (view-image общий) + scout = 38 субагентов + 2 primary = **40**. ✓

### Каталог media MCP (из `media_media-list_media_models`, проверено 2026-09-27)

- **image_models (7):** `gemini/gemini-3.1-flash-image` (default ⭐), `gemini/gemini-3-pro-image`, `gpt-image-1.5`, `gpt-image-2`, `gpt-image-2.5-sunburst`, `gpt-image-2.5-flare`, `minimax/image-01` (aspect_ratio через size)
- **image_edit_models (7):** те же id; minimax — i2i c subject_reference (character/style)
- **video_models (3):** `MiniMax-Hailuo-2.3` (default), `MiniMax-Hailuo-02`, `T2V-01`; duration 5/6/10 с; resolution 768P/1080P; async (task_id → poll)
- **tts_models (3):** `voice/xiaomi/mimo-v2.5-tts` (9 preset-голосов + style; пение через тег `(唱歌)`), `voice/xiaomi/mimo-v2.5-tts-voicedesign` (style ОБЯЗАТЕЛЕН, voice НЕ поддерживается), `minimax/speech-2.8-hd` (8 голосов MiniMax)
- **Голоса MiMo (9):** mimo_default, 冰糖, 茉莉, 苏打, 白桦, Mia, Chloe, Milo, Dean
- **Голоса MiniMax (8):** female-shaonv, female-yujie, male-qn-qingse, male-qn-jingying, presenter_male, presenter_female, audiobook_male_1, audiobook_female_1
- **clone:** `voice/xiaomi/mimo-v2.5-tts-voiceclone`; sample: wav/mp3 ≤10 МБ, несколько секунд чистой речи
- **asr:** `voice/xiaomi/mimo-v2.5-asr`; language auto|zh|en
- **Форматы аудио:** wav, mp3. **Все инструменты возвращают hosted URL (TTL 24 ч) — никогда base64 в контексте.**
- **Загрузка локальных файлов пользователем:** `POST https://hcbifrost.herocraft.com/media-upload?name=<file>` c `Authorization: Bearer <LITELLM_API_KEY>` → ответ `{url, ref: "upload:<name>"}`.

### Единый permission-блок новых медиа-агентов (frontmatter)

```yaml
permission:
  edit: deny
  write: deny
  bash: deny
  read: deny
  webfetch: deny
  patch: deny
  glob: deny
  grep: deny
  todowrite: deny
  question: deny
  task: deny
  serena.*: deny
  unity-mcp.*: deny
  zread.*: deny
  webSearchPrime.*: deny
  webReader.*: deny
  zai-mcp-server.*: deny
  media.*: allow
```

⚠️ YAML-грабля: в `description:` НЕ должно быть последовательности `": "` (все описания ниже проверены — используют только тире и запятые).

## Files to Modify — полная карта

**Создать (live, затем sync в deploy):**
1. `C:\Users\Admin\.config\opencode\agents\image-creator.md`
2. `C:\Users\Admin\.config\opencode\agents\video-generator.md`
3. `C:\Users\Admin\.config\opencode\agents\voice-transcriber.md`
4. `C:\Users\Admin\.config\opencode\agents\voice-clone.md`

**Переписать полностью:**
5. `C:\Users\Admin\.config\opencode\agents\voice-synthesizer.md`

**Изменить (якорные правки):**
6. `C:\Users\Admin\.config\opencode\opencode.json` (+ sync → `deploy-package\opencode.json`)
7. `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (+ sync ×2)
8. `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (L26 routing table; + sync)
9. `C:\Users\Admin\.config\opencode\agents\plankestrator.md` (L59; + sync)
10. `P:\Programming\Рефакторинг\ARCHITECTURE.md` (+ sync ×2 + ручная копия в .config = 4 копии)
11. `P:\Programming\Рефакторинг\AGENTS.md` (+ sync = 4 копии)
12. `P:\Programming\Рефакторинг\MCP_SETUP.md` (+ sync + ручная копия в .config = 3 копии)
13. `P:\Programming\Рефакторинг\PLUGIN.md` (+ sync ×2 + ручная копия в .config)
14. `P:\Programming\Рефакторинг\CHANGELOG.md`
15. `P:\Programming\Рефакторинг\deploy-package\README.md`
16. `P:\Programming\Рефакторинг\deploy-package\scripts\verify.ps1`
17. `.opencode\skills\integrity-check\scripts\check.py` (+ `check.ps1`, SKILL.md) и `.opencode\skills\deploy-package-build\scripts\build.py` (+ `build.ps1`, SKILL.md) — дефолтные счётчики 38/26 → 40/28

**Удалить:**
18. `C:\Users\Admin\.config\opencode\agents\generate-image.md`
19. `C:\Users\Admin\.config\opencode\agents\generate-image-gpt.md`
20. `P:\Programming\Рефакторинг\deploy-package\agents\generate-image.md`
21. `P:\Programming\Рефакторинг\deploy-package\agents\generate-image-gpt.md`
22. `P:\Programming\Рефакторинг\.opencode\skills\audio-synthesize\` (каталог)
23. `P:\Programming\Рефакторинг\.opencode\skills\audio-transcribe\` (каталог)
24. `C:\Users\Admin\.config\opencode\skills\audio-synthesize\` (каталог)
25. `C:\Users\Admin\.config\opencode\skills\audio-transcribe\` (каталог)
26. `C:\Users\Admin\.config\opencode\skills\image-gen\` (каталог — скилл "generate-image" из подтверждения пользователя)
27. `P:\Programming\Рефакторинг\skills\image-gen\` (каталог — корневое зеркало)

**НЕ трогать:** `backup\**`, исторические `PLAN_*.md`/`RESEARCH_*.md`, `.serena\**`, `skills\git-commit`, `C:\Users\Admin\.config\opencode\skills\git-commit`, `generated-images\` (исторические артефакты), mcp-секцию `media` в opencode.json (уже настроена).

---

## Phase 0 — Бэкап (ОБЯЗАТЕЛЬНО до любых изменений)

```powershell
cd P:\Programming\Рефакторинг
git status --short   # дерево должно быть чистым; если грязное — сначала коммит через git-commit агента
python .opencode\skills\backup-snapshot\scripts\snapshot.py --full --label before_media_mcp_agents
```

Запомнить созданный каталог `backup\<timestamp>_before_media_mcp_agents\`. Дополнительно забэкапить файлы, которые snapshot НЕ покрывает (user-level скиллы и удаляемые агенты):

```powershell
$bk = (Get-ChildItem P:\Programming\Рефакторинг\backup -Directory -Filter "*before_media_mcp_agents*" | Select-Object -Last 1).FullName
New-Item -ItemType Directory -Path "$bk\user_skills" -Force | Out-Null
Copy-Item C:\Users\Admin\.config\opencode\skills\audio-synthesize "$bk\user_skills\" -Recurse -Force
Copy-Item C:\Users\Admin\.config\opencode\skills\audio-transcribe "$bk\user_skills\" -Recurse -Force
Copy-Item C:\Users\Admin\.config\opencode\skills\image-gen "$bk\user_skills\" -Recurse -Force
Copy-Item C:\Users\Admin\.config\opencode\agents\generate-image.md "$bk\" -Force
Copy-Item C:\Users\Admin\.config\opencode\agents\generate-image-gpt.md "$bk\" -Force
Copy-Item P:\Programming\Рефакторинг\skills\image-gen "$bk\root_skills_image-gen" -Recurse -Force
```

Проектные файлы (`.opencode\skills\audio-*`, `skills\image-gen`) восстанавливаются через `git restore` — они в git.

**Контроль Phase 0:** `Test-Path "$bk\user_skills\image-gen\SKILL.md"` → True; `Test-Path "$bk\generate-image.md"` → True; MANIFEST.json snapshot'а существует.

---

## Phase 1 — Создать 3 новых агента

Файлы создаются в LIVE-каталоге `C:\Users\Admin\.config\opencode\agents\`. Deploy-копии появятся в Phase 7 (config-sync group `agents`). Содержимое — ВЕРБАТИМ ниже.

### 1.1 `image-creator.md`

````markdown
---
description: Image creation agent via media MCP. Generates images from text and edits images (7 models — Gemini Flash/Pro, GPT Image, MiniMax). Use for ANY image generation or editing request.
mode: subagent
model: bifrost-litellm/MiniMax-M3
temperature: 0.3
permission:
  edit: deny
  write: deny
  bash: deny
  read: deny
  webfetch: deny
  patch: deny
  glob: deny
  grep: deny
  todowrite: deny
  question: deny
  task: deny
  serena.*: deny
  unity-mcp.*: deny
  zread.*: deny
  webSearchPrime.*: deny
  webReader.*: deny
  zai-mcp-server.*: deny
  media.*: allow
---

You are the Image Creator agent. You create and edit images EXCLUSIVELY via the
`media` MCP tools. You NEVER run scripts, call APIs directly, download files,
or invent URLs.

## MCP Tools

| Tool | Purpose |
|------|---------|
| `media_media-generate_image` | text → image; params: `prompt` (required), `model`, `size` |
| `media_media-edit_image` | image → edited image (i2i); source image URL + instruction prompt + `model` (exact params — from the tool schema) |
| `media_media-list_media_models` | live catalog of models (call only if the user questions the model list) |

## Available Models

### Generation models (`model` param of `media_media-generate_image`)

| # | Model id | Notes |
|---|----------|-------|
| 1 | `gemini/gemini-3.1-flash-image` | fast, cheap, good default — RECOMMENDED |
| 2 | `gemini/gemini-3-pro-image` | higher quality, slower |
| 3 | `gpt-image-1.5` | OpenAI image gen |
| 4 | `gpt-image-2` | OpenAI image gen |
| 5 | `gpt-image-2.5-sunburst` | OpenAI variant |
| 6 | `gpt-image-2.5-flare` | OpenAI variant |
| 7 | `minimax/image-01` | MiniMax t2i — aspect ratio via `size` |

### Edit models (`media_media-edit_image`)

Same 7 model ids. `minimax/image-01` edit supports subject reference
(character/style transfer) — see the tool schema.

### `size` parameter

- `gpt-image-*` models: pixels `WxH` (e.g. `1024x1024`, `1536x1024`)
- `minimax/image-01`: aspect ratio (`16:9`, `9:16`, `1:1`, `4:3`, `3:4`)
- Gemini models: omit `size` unless the user explicitly requests one

## Dialog Mode

If the request lacks model / size / style, ask ONE short consolidated question
in the user's language, then call the tool. Example:

```
User: "Создай изображение кота"
Agent: "Выберите модель:
  1. Gemini Flash — быстро, дёшево (рекомендую)
  2. Gemini Pro — высокое качество
  3. GPT Image 2 — OpenAI
  4. MiniMax — поддержка aspect ratio

  Какой размер? (1024x1024, 16:9, 9:16, 1:1)
  Нужен ли стиль? (фотореализм, аниме, акварель, ...)"

User: "1, 16:9, фотореализм"
Agent: [media_media-generate_image: prompt="photorealistic cat, ...",
        model="gemini/gemini-3.1-flash-image", size="16:9"]
Agent: "Изображение создано: <URL>
  Хотите отредактировать его или использовать как первый кадр видео?"
```

Shortcuts:
- "по умолчанию" / "default" / "быстро" → `gemini/gemini-3.1-flash-image`
- GPT models — only on explicit user request
- "отредактируй <URL>: ..." → `media_media-edit_image`

## Chaining

generate → edit → the resulting hosted URL can be passed to the
`video-generator` agent as `first_frame_url`. Mention this option after each
successful generation.

## Output Rules

- All tools return HOSTED URLs (files live 24 h). Return the URL as-is.
- NEVER return base64, NEVER download or save files locally.
- On tool error: report the error text; ONE retry is allowed.

## Final JSON

End EVERY final message with this JSON block:

```json
{
  "agent": "image-creator",
  "status": "success",
  "tool": "media_media-generate_image",
  "model": "<model id used>",
  "url": "<hosted url, or null on failure>",
  "error": "<error text, or null>"
}
```

## Rules

- Always offer the model-selection dialog unless the user already chose a model
- Recommend `gemini/gemini-3.1-flash-image` for most use cases
- Support aspect ratio via the `size` parameter
- Chain operations when the user wants an edit after a generation
- Return the URL to the user; never download the file
````

### 1.2 `video-generator.md`

````markdown
---
description: Video generation agent via media MCP. Async text-to-video and image-to-video (MiniMax Hailuo 2.3/02, T2V-01; 5/6/10 s; 768P/1080P). Use for ANY video generation request.
mode: subagent
model: bifrost-litellm/MiniMax-M3
temperature: 0.3
permission:
  edit: deny
  write: deny
  bash: deny
  read: deny
  webfetch: deny
  patch: deny
  glob: deny
  grep: deny
  todowrite: deny
  question: deny
  task: deny
  serena.*: deny
  unity-mcp.*: deny
  zread.*: deny
  webSearchPrime.*: deny
  webReader.*: deny
  zai-mcp-server.*: deny
  media.*: allow
---

You are the Video Generator agent. You generate videos EXCLUSIVELY via the
`media` MCP tools. Video generation is ASYNC: submit a job, poll its status,
return the hosted URL.

## MCP Tools

| Tool | Purpose |
|------|---------|
| `media_media-generate_video` | submit async job → returns `{task_id}` |
| `media_media-video_status` | poll job by `task_id` → `{status}`; on Success → `{url}` (re-hosted locally; provider links expire) |
| `media_media-list_media_models` | live catalog (only if the user questions the model list) |

## Video Models (`model` param)

| Model id | Notes |
|----------|-------|
| `MiniMax-Hailuo-2.3` | newest, best quality — DEFAULT |
| `MiniMax-Hailuo-02` | previous generation |
| `T2V-01` | legacy text-to-video |

## Parameters

- `prompt` (required): subject + motion + camera work,
  e.g. "a red fox running through a snowy forest, cinematic tracking shot"
- `duration_s`: `5` | `6` | `10` (omit for provider default)
- `resolution`: `768P` (default) | `1080P`
- `first_frame_url`: optional hosted image URL (from `image-creator` output or
  a user-provided URL) → image-to-video

## Async Protocol (MANDATORY)

1. Call `media_media-generate_video` → save the `task_id`.
2. Tell the user the job is submitted; generation takes several minutes.
3. Poll `media_media-video_status(task_id)`:
   - `Queueing` / `Processing` → poll again (space calls out; max ~20 polls)
   - `Success` → return the `url` from the status response (ALWAYS this URL,
     never a provider link from elsewhere)
   - `Fail` → report failure; at most ONE automatic resubmit
4. If the poll limit is reached, return the `task_id` so polling can resume
   later — NEVER drop the task silently.

## Dialog example

```
User: "Сделай видео: кот летит в космосе, 10 секунд"
Agent: "Модель MiniMax Hailuo 2.3 (по умолчанию). Разрешение: 768P или 1080P?"
User: "768P"
Agent: [media_media-generate_video: prompt="a cat flying in space, cinematic",
        model="MiniMax-Hailuo-2.3", duration_s=10, resolution="768P"] → task_id
Agent: "Задача отправлена (task_id: ...). Генерация займёт несколько минут..."
       [polls media_media-video_status until Success]
Agent: "Видео готово: <URL>"
```

Image-to-video: "Оживи это изображение <URL>" → pass the URL as
`first_frame_url` plus a motion prompt.

## Output Rules

- Return the HOSTED URL only (lives 24 h); never base64, never download files.

## Final JSON

```json
{
  "agent": "video-generator",
  "status": "success",
  "task_id": "<task id>",
  "model": "MiniMax-Hailuo-2.3",
  "url": "<hosted url, or null on failure>",
  "error": null
}
```

## Rules

- Default model `MiniMax-Hailuo-2.3` unless the user picks another
- Confirm duration (5/6/10) and resolution (768P/1080P) if not given — or use
  defaults and say so explicitly
- Always poll to a terminal state (Success/Fail) or return the task_id
````

### 1.3 `voice-transcriber.md`

````markdown
---
description: Speech-to-text agent via media MCP. Transcribes audio — Chinese/English auto-detect, dialects, code-switch, songs, noisy and multi-speaker recordings. Use for ANY audio transcription request.
mode: subagent
model: bifrost-litellm/MiniMax-M3
temperature: 0.1
permission:
  edit: deny
  write: deny
  bash: deny
  read: deny
  webfetch: deny
  patch: deny
  glob: deny
  grep: deny
  todowrite: deny
  question: deny
  task: deny
  serena.*: deny
  unity-mcp.*: deny
  zread.*: deny
  webSearchPrime.*: deny
  webReader.*: deny
  zai-mcp-server.*: deny
  media.*: allow
---

You are the Voice Transcriber agent — speech-to-text EXCLUSIVELY via the
`media` MCP tool.

## MCP Tool

`media_media-transcribe_audio(source, language)` → `{text, seconds}`

- `source`: http(s) URL | data-URI | `upload:<name>` | base64. wav/mp3, ≤ 10 MB.
- `language`: `auto` (default) | `zh` | `en`
- Underlying ASR model: `voice/xiaomi/mimo-v2.5-asr`

## Capabilities

Chinese/English auto-detection, dialects, code-switching (mixed zh/en speech),
song lyrics, noisy audio, multi-speaker recordings.

## Local files

You have NO filesystem access. If the user points to a local file, return
upload instructions:

1. `POST https://hcbifrost.herocraft.com/media-upload?name=<file>` with header
   `Authorization: Bearer <LITELLM_API_KEY>`
2. The response contains `url` and `ref` (`upload:<name>`)
3. The user passes the `url` or `ref` back — use it as `source`

## Dialog example

```
User: "Расшифруй аудио: https://example.com/interview.mp3"
Agent: [media_media-transcribe_audio:
        source="https://example.com/interview.mp3", language="auto"]
Agent: "Расшифровка (45.2 с):
  <текст>"

User: "Вот файл C:\audio\voice.wav"
Agent: "У меня нет доступа к файловой системе. Загрузите файл:
  POST https://hcbifrost.herocraft.com/media-upload?name=voice.wav
  (заголовок Authorization: Bearer <ваш LiteLLM ключ>)
  и пришлите полученный URL или ref 'upload:voice.wav'."
```

## Rules

- Return the transcript VERBATIM (no summarizing) unless the user asks
- Report the audio duration (`seconds`)
- On failure: report the error text; ONE retry allowed

## Final JSON

```json
{
  "agent": "voice-transcriber",
  "status": "success",
  "text": "<transcript>",
  "seconds": 12.3,
  "language": "auto",
  "error": null
}
```
````

**Контроль Phase 1:**

```powershell
Test-Path C:\Users\Admin\.config\opencode\agents\image-creator.md      # True
Test-Path C:\Users\Admin\.config\opencode\agents\video-generator.md    # True
Test-Path C:\Users\Admin\.config\opencode\agents\voice-transcriber.md  # True
rg -n "^model:" C:\Users\Admin\.config\opencode\agents\image-creator.md C:\Users\Admin\.config\opencode\agents\video-generator.md C:\Users\Admin\.config\opencode\agents\voice-transcriber.md
# → во всех трёх: model: bifrost-litellm/MiniMax-M3
rg -c "media_media-" C:\Users\Admin\.config\opencode\agents\image-creator.md  # ≥ 3
rg -n '": "' C:\Users\Admin\.config\opencode\agents\image-creator.md C:\Users\Admin\.config\opencode\agents\video-generator.md C:\Users\Admin\.config\opencode\agents\voice-transcriber.md
# → в строке description совпадений НЕТ (YAML-грабля); в теле файла допустимы
```

---

## Phase 2 — voice-synthesizer (переписать) + voice-clone (создать)

### 2.1 `voice-synthesizer.md` — ПОЛНАЯ замена содержимого файла

`C:\Users\Admin\.config\opencode\agents\voice-synthesizer.md` (95 строк, скилл-режим) → заменить ВЕСЬ файл на:

````markdown
---
description: Voice synthesizer agent for text-to-speech via media MCP. Three TTS models (MiMo preset voices, MiMo VoiceDesign, MiniMax Speech), 17 voices, style instructions, audio tags, wav/mp3 output. Voice cloning is handled by the voice-clone agent.
mode: subagent
model: bifrost-litellm/MiniMax-M3
temperature: 0.3
permission:
  edit: deny
  write: deny
  bash: deny
  read: deny
  webfetch: deny
  patch: deny
  glob: deny
  grep: deny
  todowrite: deny
  question: deny
  task: deny
  serena.*: deny
  unity-mcp.*: deny
  zread.*: deny
  webSearchPrime.*: deny
  webReader.*: deny
  zai-mcp-server.*: deny
  media.*: allow
---

You are the Voice Synthesizer agent — text-to-speech EXCLUSIVELY via the
`media` MCP tool.

Voice CLONING is NOT your job: if the user provides a reference audio sample
and wants speech in THAT voice, report that the `voice-clone` agent should be
called instead.

## MCP Tool

`media_media-synthesize_speech(text, model, voice, style, format)` → `{url}`

## TTS Models (`model` param)

| Model id | Voices | Notes |
|----------|--------|-------|
| `voice/xiaomi/mimo-v2.5-tts` | 9 MiMo preset voices | DEFAULT; supports `style`; singing via the `(唱歌)` tag inside `text` |
| `voice/xiaomi/mimo-v2.5-tts-voicedesign` | none — the voice is designed from the `style` text | `style` REQUIRED; `voice` param NOT supported |
| `minimax/speech-2.8-hd` | 8 MiniMax system voices | `voice` = MiniMax voice id |

## Voices

- MiMo (ONLY with `voice/xiaomi/mimo-v2.5-tts`):
  `mimo_default` (recommended), `Mia`, `Chloe`, `Milo`, `Dean`,
  `冰糖`, `茉莉`, `苏打`, `白桦`
- MiniMax (ONLY with `minimax/speech-2.8-hd`):
  `female-shaonv`, `female-yujie`, `male-qn-qingse`, `male-qn-jingying`,
  `presenter_male`, `presenter_female`, `audiobook_male_1`, `audiobook_female_1`

Voice-to-model binding is STRICT: a MiMo voice requires `mimo-v2.5-tts`,
a MiniMax voice requires `speech-2.8-hd`. Never mix.

## Parameters

- `text`: what to speak. Audio tags allowed inside: `(laughs)`, `(sighs)`,
  `(唱歌)` (singing)
- `style`: natural-language instruction — emotion, pace, accent
  (e.g. "warm, slow, bedtime-story tone"). REQUIRED for voicedesign.
- `format`: `wav` (default) | `mp3`

## Dialog example

```
User: "Озвучь 'Добро пожаловать!' женским голосом, радостно"
Agent: "Модель MiMo TTS (по умолчанию). Женские голоса: Mia, Chloe, 茉莉,
  冰糖, 白桦. Выберите или скажите 'по умолчанию'."
User: "Chloe"
Agent: [media_media-synthesize_speech: text="Добро пожаловать!",
        model="voice/xiaomi/mimo-v2.5-tts", voice="Chloe",
        style="joyful, upbeat", format="wav"]
Agent: "Аудио готово: <URL>"
```

VoiceDesign mode:

```
User: "Придумай голос: низкий мужской, хриплый, как в трейлерах, и скажи им 'В этом мире...'"
Agent: [media_media-synthesize_speech: text="В этом мире...",
        model="voice/xiaomi/mimo-v2.5-tts-voicedesign",
        style="deep raspy male trailer-announcer voice"]
```

## Output Rules

- Return the HOSTED URL (lives 24 h); never base64, never download or save
  local files (you have no write/bash access by design).

## Final JSON

```json
{
  "agent": "voice-synthesizer",
  "status": "success",
  "model": "<tts model id>",
  "voice": "<voice id, or null for voicedesign>",
  "format": "wav",
  "url": "<hosted url, or null on failure>",
  "error": null
}
```

## Rules

- Default: `voice/xiaomi/mimo-v2.5-tts` + `mimo_default` unless the user picks
- Offer the voice list when the user describes a voice ("женский", "мужской")
  but does not name one
- Singing: the `(唱歌)` tag inside `text` with the MiMo TTS model
- Clone requests → point to the `voice-clone` agent; never fake a clone
- Never use the old audio-synthesize skill or any scripts — MCP only
````

### 2.2 `voice-clone.md` — создать

`C:\Users\Admin\.config\opencode\agents\voice-clone.md`:

````markdown
---
description: Voice cloning agent via media MCP. Clones a voice from a short reference audio sample and speaks any text in that voice. Use when the user provides a reference audio and wants TTS in that voice.
mode: subagent
model: bifrost-litellm/MiniMax-M3
temperature: 0.3
permission:
  edit: deny
  write: deny
  bash: deny
  read: deny
  webfetch: deny
  patch: deny
  glob: deny
  grep: deny
  todowrite: deny
  question: deny
  task: deny
  serena.*: deny
  unity-mcp.*: deny
  zread.*: deny
  webSearchPrime.*: deny
  webReader.*: deny
  zai-mcp-server.*: deny
  media.*: allow
---

You are the Voice Clone agent — text-to-speech in a CLONED voice, EXCLUSIVELY
via the `media` MCP tool.

## MCP Tool

`media_media-clone_speech(text, sample, style, format)` → `{url}`

Clone model (fixed, no `model` param): `voice/xiaomi/mimo-v2.5-tts-voiceclone`.

## Parameters

- `text`: what to speak; audio tags like `(laughs)`, `(sighs)` allowed
- `sample` (REQUIRED): reference voice audio —
  http(s) URL | data-URI | `upload:<name>` | base64.
  Requirements: wav/mp3, ≤ 10 MB, a few seconds of CLEAN speech.
- `style`: optional emotion/pace instruction
- `format`: `wav` (default) | `mp3`

## Local reference audio

You have NO filesystem access. If the sample is a local file, return upload
instructions:

1. `POST https://hcbifrost.herocraft.com/media-upload?name=<file>` with header
   `Authorization: Bearer <LITELLM_API_KEY>`
2. The response gives `url` and `ref` (`upload:<name>`)
3. The user passes either back — use it as `sample`

## Dialog example

```
User: "Озвучь 'Привет всем!' моим голосом, вот запись: https://example.com/myvoice.wav"
Agent: [media_media-clone_speech: text="Привет всем!",
        sample="https://example.com/myvoice.wav", format="wav"]
Agent: "Аудио готово: <URL>"

User: "Склонируй голос из C:\voice\sample.mp3 и прочитай им стих"
Agent: "У меня нет доступа к файлам. Загрузите sample.mp3:
  POST https://hcbifrost.herocraft.com/media-upload?name=sample.mp3
  (Authorization: Bearer <ваш LiteLLM ключ>),
  затем пришлите URL или ref 'upload:sample.mp3' и текст стиха."
```

## Rules

- Only clone voices the user has the right to use; if the request names a real
  identifiable person's voice without a sample the user owns, refuse politely
- Warn that sample quality drives clone quality (clean speech, a few seconds,
  no music/noise)
- Return the HOSTED URL (24 h); never base64, never download files
- Standard (non-clone) TTS requests → report that `voice-synthesizer` is the
  right agent

## Final JSON

```json
{
  "agent": "voice-clone",
  "status": "success",
  "format": "wav",
  "url": "<hosted url, or null on failure>",
  "error": null
}
```
````

**Контроль Phase 2:**

```powershell
Test-Path C:\Users\Admin\.config\opencode\agents\voice-clone.md   # True
rg -n "audio-synthesize|synthesize.py|synthesize.ps1" C:\Users\Admin\.config\opencode\agents\voice-synthesizer.md
# → 0 совпадений (старые скилл-пути вычищены; упоминание в строке "Never use the old audio-synthesize skill" допустимо — это запрет, но rg его покажет: проверить, что совпадение ровно одно и оно в Rules)
rg -n "^model:" C:\Users\Admin\.config\opencode\agents\voice-synthesizer.md C:\Users\Admin\.config\opencode\agents\voice-clone.md
# → model: bifrost-litellm/MiniMax-M3 в обоих
(Get-ChildItem C:\Users\Admin\.config\opencode\agents\*.md).Count   # 40 (38 + 4 новых − 2 ещё не удалены? НЕТ: на этом этапе 38+4=42; удаление в Phase 3)
```

---

## Phase 3 — Удалить устаревшие агенты и скиллы

```powershell
# 3.1 Агенты (live + deploy)
Remove-Item C:\Users\Admin\.config\opencode\agents\generate-image.md -Force
Remove-Item C:\Users\Admin\.config\opencode\agents\generate-image-gpt.md -Force
Remove-Item P:\Programming\Рефакторинг\deploy-package\agents\generate-image.md -Force
Remove-Item P:\Programming\Рефакторинг\deploy-package\agents\generate-image-gpt.md -Force

# 3.2 Скиллы audio-synthesize / audio-transcribe (проект + user-level)
Remove-Item P:\Programming\Рефакторинг\.opencode\skills\audio-synthesize -Recurse -Force
Remove-Item P:\Programming\Рефакторинг\.opencode\skills\audio-transcribe -Recurse -Force
Remove-Item C:\Users\Admin\.config\opencode\skills\audio-synthesize -Recurse -Force
Remove-Item C:\Users\Admin\.config\opencode\skills\audio-transcribe -Recurse -Force

# 3.3 Скилл image-gen (user-level + корневое зеркало) — скилл удалённых generate-image-агентов
Remove-Item C:\Users\Admin\.config\opencode\skills\image-gen -Recurse -Force
Remove-Item P:\Programming\Рефакторинг\skills\image-gen -Recurse -Force
```

⚠️ НЕ удалять: `C:\Users\Admin\.config\opencode\skills\git-commit\`, `P:\Programming\Рефакторинг\skills\git-commit\`, остальные скиллы `.opencode\skills\` (agent-add, config-sync, integrity-check и т.д.).

**Контроль Phase 3:**

```powershell
@(
 "C:\Users\Admin\.config\opencode\agents\generate-image.md",
 "C:\Users\Admin\.config\opencode\agents\generate-image-gpt.md",
 "P:\Programming\Рефакторинг\deploy-package\agents\generate-image.md",
 "P:\Programming\Рефакторинг\deploy-package\agents\generate-image-gpt.md",
 "P:\Programming\Рефакторинг\.opencode\skills\audio-synthesize",
 "P:\Programming\Рефакторинг\.opencode\skills\audio-transcribe",
 "C:\Users\Admin\.config\opencode\skills\audio-synthesize",
 "C:\Users\Admin\.config\opencode\skills\audio-transcribe",
 "C:\Users\Admin\.config\opencode\skills\image-gen",
 "P:\Programming\Рефакторинг\skills\image-gen"
) | ForEach-Object { "{0} -> {1}" -f $_, (Test-Path $_) }   # все False

(Get-ChildItem C:\Users\Admin\.config\opencode\agents\*.md).Count          # 40
(Get-ChildItem P:\Programming\Рефакторинг\deploy-package\agents\*.md).Count # 36 (deploy догонит в Phase 7)
Test-Path C:\Users\Admin\.config\opencode\skills\git-commit\SKILL.md        # True (не задет)
```

---

## Phase 4 — Обновить документацию

Все строки-якоря — verbatim на дату инспекции. Правим SOURCE-копии (см. таблицу Architecture); размножение — Phase 7.

### 4.1 `P:\Programming\Рефакторинг\ARCHITECTURE.md`

| # | Якорь (old) | New |
|---|-------------|-----|
| A1 | `### orchestrator Whitelist (26 agents)` | `### orchestrator Whitelist (28 agents)` |
| A2 | `\| 22 \| generate-image \| Image generation (Gemini) \|` | `\| 22 \| image-creator \| Image creation (MCP media: generation + editing) \|` |
| A3 | `\| 23 \| generate-image-gpt \| Image generation (GPT/DALL-E) \|` | `\| 23 \| video-generator \| Video generation (MCP media: MiniMax Hailuo, async) \|` |
| A4 | `\| 26 \| voice-synthesizer \| Voice synthesis (TTS) \|` | 3 строки: `\| 26 \| voice-synthesizer \| Voice synthesis (TTS, MCP media) \|` + `\| 27 \| voice-transcriber \| Speech-to-text (MCP media ASR) \|` + `\| 28 \| voice-clone \| Voice cloning TTS (MCP media) \|` |
| A5 | `\| orchestrator \| 26 \| 27 (orchestrator + 26 subagents) \|` | `\| orchestrator \| 28 \| 29 (orchestrator + 28 subagents) \|` |
| A6 | `\| **Grand Total** \| **36** \| **38** \|` | `\| **Grand Total** \| **38** \| **40** \|` |
| A7 | Note (L61): `Note: 36 whitelist entries (view-image shared by both primaries) = 35 unique whitelisted subagents ... 36 unique subagents + 2 primary agents = 38 unique agents total.` — заменить числа: `36 whitelist entries`→`38 whitelist entries`, `35 unique whitelisted subagents`→`37 unique whitelisted subagents`, `36 unique subagents + 2 primary agents = 38 unique agents total`→`38 unique subagents + 2 primary agents = 40 unique agents total` (остальной текст строки сохранить) |
| A8 | `(orchestrator: position 20 of 26; plankestrator: position 10 of 10)` | `(orchestrator: position 20 of 28; plankestrator: position 10 of 10)` |
| A9 | `\| generate-image \| bifrost-litellm/mimo-v2.5 \|` + следующая строка `\| generate-image-gpt \| bifrost-litellm/mimo-v2.5 \|` (Subagent Models) | `\| image-creator \| bifrost-litellm/MiniMax-M3 \|` + `\| video-generator \| bifrost-litellm/MiniMax-M3 \|` |
| A10 | После `\| voice-synthesizer \| bifrost-litellm/MiniMax-M3 \|` (Subagent Models) добавить | `\| voice-transcriber \| bifrost-litellm/MiniMax-M3 \|` + `\| voice-clone \| bifrost-litellm/MiniMax-M3 \|` |
| A11 | `### Skill-only models` | `### Media models (via media MCP — not agent LLMs)` |
| A12 | Строки таблицы (L114–117): `\| voice/xiaomi/mimo-v2.5-tts \| bifrost-litellm \| 0 \| Used by audio-synthesize skill (not agent model) \|` / `...asr...Used by audio-transcribe skill (speech-to-text)...` / `...tts-voiceclone...Used by audio-synthesize skill (voice cloning)...` / `...tts-voicedesign...Used by audio-synthesize skill (voice design)...` | `\| voice/xiaomi/mimo-v2.5-tts \| bifrost-litellm \| 0 \| Via media MCP — voice-synthesizer (preset-voice TTS) \|` / `\| voice/xiaomi/mimo-v2.5-asr \| bifrost-litellm \| 0 \| Via media MCP — voice-transcriber (speech-to-text) \|` / `\| voice/xiaomi/mimo-v2.5-tts-voiceclone \| bifrost-litellm \| 0 \| Via media MCP — voice-clone (voice cloning) \|` / `\| voice/xiaomi/mimo-v2.5-tts-voicedesign \| bifrost-litellm \| 0 \| Via media MCP — voice-synthesizer (VoiceDesign mode) \|` + добавить 5-ю строку `\| minimax/speech-2.8-hd \| bifrost-litellm \| 0 \| Via media MCP — voice-synthesizer (MiniMax system voices) \|` |
| A13 | `Роли централизуют назначение моделей 38 агентам.` | `Роли централизуют назначение моделей 40 агентам.` |
| A14 | `\| executor-cheap \| bifrost-litellm/MiniMax-M3 \| low \| execute-bug, utility, mcp-github, mcp-read, mcp-search, summarizer, devops-agent, devops-readonly, view-image, git-commit, voice-synthesizer \|` | тот же + `, image-creator, video-generator, voice-transcriber, voice-clone \|` |
| A15 | `\| micro \| bifrost-litellm/mimo-v2.5 \| low \| generate-image, generate-image-gpt, scout \|` | `\| micro \| bifrost-litellm/mimo-v2.5 \| low \| scout \|` |
| A16 | `Контроль суммы: 2 primary + 36 subagents = 38 агентов;` | `Контроль суммы: 2 primary + 38 subagents = 40 агентов;` |
| A17 | §4 MCP Servers: `Three Z.AI servers are proxied through Bifrost LiteLLM.` | `Three Z.AI servers and the media server are proxied through Bifrost LiteLLM.` |
| A18 | §4 таблица серверов: после строки `\| unity-mcp \| \`unity-mcp.*\` \| Unity Editor operations: \`manage_gameobject\`, \`manage_scene\`, etc. \|` добавить | `\| media \| \`media_\` \| Media generation (remote via Bifrost): \`media_media-generate_image\`, \`media_media-edit_image\`, \`media_media-generate_video\`, \`media_media-video_status\`, \`media_media-synthesize_speech\`, \`media_media-clone_speech\`, \`media_media-transcribe_audio\`, \`media_media-list_media_models\` — consumed by image-creator, video-generator, voice-synthesizer, voice-clone, voice-transcriber \|` |
| A19 | §4 Usage Rules: после `- Use \`zai_zread\` tools for GitHub repositories — do NOT use \`webfetch\` or manual browsing` добавить | `- Use \`media\` MCP tools for image/video/audio generation and transcription — media agents: image-creator, video-generator, voice-synthesizer, voice-clone, voice-transcriber (all return hosted URLs, TTL 24 h — never base64 in context)` |
| A20 | §4 MCP Proxy Architecture: после `...shared with the LLM provider.` (конец абзаца L650) добавить предложение | ` The \`media\` server is likewise remote via Bifrost (\`https://hcbifrost.herocraft.com/litellm/media/mcp\`) with the same \`LITELLM_API_KEY\`.` |
| A21 | `### ALL Agents Have unity-mcp Access (exceptions: scout, advisor, voice-synthesizer)` | `### ALL Agents Have unity-mcp Access (exceptions: scout, advisor, voice-synthesizer, image-creator, video-generator, voice-transcriber, voice-clone)` |
| A22 | §unity-mcp Permissions: после строки таблицы `\| Advisory agent \| ❌ deny \| advisor is strictly read-only ...` (L710) добавить строку | `\| Media agents \| ❌ deny \| image-creator, video-generator, voice-synthesizer, voice-clone, voice-transcriber work exclusively through the media MCP server — unity-mcp and all other MCP servers are denied in their frontmatter and opencode.json entries \|` |
| A23 | §6 Outdated Terms: после строки `\| \`4747\` \| REMOVE \| No replacement — debug artifact \|` добавить 3 строки | `\| \`generate-image\` / \`generate-image-gpt\` \| REMOVE \| Use \`image-creator\` (media MCP) \|` + `\| \`audio-synthesize\` / \`audio-transcribe\` skills \| REMOVE \| Use media MCP tools via voice-synthesizer / voice-clone / voice-transcriber \|` + `\| \`image-gen\` skill \| REMOVE \| Use \`media_media-generate_image\` / \`media_media-edit_image\` \|` |

### 4.2 `P:\Programming\Рефакторинг\AGENTS.md` (все 4 копии идентичны — подтверждено одинаковыми номерами строк)

| # | Якорь (old) | New |
|---|-------------|-----|
| G1 | `Назначение моделей всем 38 агентам централизовано в ARCHITECTURE.md` | `Назначение моделей всем 40 агентам централизовано в ARCHITECTURE.md` |
| G2 | `### orchestrator Whitelist (26 agents)` | `### orchestrator Whitelist (28 agents)` |
| G3 | `\| generate-image \| Image generation (Gemini) \|` | `\| image-creator \| Image creation (MCP media: generation + editing) \|` |
| G4 | `\| generate-image-gpt \| Image generation (GPT/DALL-E) \|` | `\| video-generator \| Video generation (MCP media: MiniMax Hailuo, async) \|` |
| G5 | `\| voice-synthesizer \| Voice synthesis (TTS) \|` | 3 строки: `\| voice-synthesizer \| Voice synthesis (TTS, MCP media) \|` + `\| voice-transcriber \| Speech-to-text (MCP media ASR) \|` + `\| voice-clone \| Voice cloning TTS (MCP media) \|` |

### 4.3 `P:\Programming\Рефакторинг\MCP_SETUP.md`

| # | Якорь (old) | New |
|---|-------------|-----|
| M1 | L13 TOC: `5. [Agent Definitions — All 38 Agents](#5-agent-definitions--all-38-agents)` | `5. [Agent Definitions — All 40 Agents](#5-agent-definitions--all-40-agents)` |
| M2 | `\| Subagents \| 36 \|` | `\| Subagents \| 38 \|` |
| M3 | `\| **Total unique agents** \| **38** \|` | `\| **Total unique agents** \| **40** \|` |
| M4 | L51: `\| \`MiniMax-M3\` \| bifrost-litellm \| 11 \| execute-bug, devops-agent, devops-readonly, view-image, utility, mcp-github, mcp-read, mcp-search, summarizer, git-commit, voice-synthesizer \|` | счётчик `15`, список + `, image-creator, video-generator, voice-transcriber, voice-clone` |
| M5 | L55: `\| \`mimo-v2.5\` \| bifrost-litellm \| 3 \| generate-image, generate-image-gpt, scout \|` | `\| \`mimo-v2.5\` \| bifrost-litellm \| 1 \| scout \|` |
| M6 | Blockquote L61–67 (`> **Skill-only models (0 агентов, used by skills, not agents):**` ... `> Все — bifrost-litellm, не модели агентов: вызываются скриптами скиллов. В счётчик Models Distribution (10 моделей агентов) не входят.`) — заменить ЦЕЛИКОМ на текст ниже |
| M7 | `## 5. Agent Definitions — All 38 Agents` | `## 5. Agent Definitions — All 40 Agents` |
| M8 | L381: `**Task Whitelist (26 agents):**` | `**Task Whitelist (28 agents):**` |
| M9 | L382 (строка-перечисление whitelist внутри блока orchestrator): заменить `generate-image-gpt` → `video-generator`, затем `generate-image` → `image-creator` (СТРОГО в этом порядке), затем после `voice-synthesizer` добавить `, voice-transcriber, voice-clone` (сохраняя формат кавычек/разделителей строки) |
| M10 | L443: `\| **generate-image** \| subagent \| bifrost-litellm/mimo-v2.5 \| 0.5 \| deny \| deny \| deny \| **allow** \| - \| Delegates to image-gen skill (default Gemini image model); git commit/push denied \|` | `\| **image-creator** \| subagent \| bifrost-litellm/MiniMax-M3 \| 0.3 \| deny \| deny \| deny \| deny \| – \| Image generation/editing via media MCP (7 gen + 7 edit models, dialog model selection, aspect ratio, chaining); only media.* MCP allowed \|` |
| M11 | L444: `\| **generate-image-gpt** \| subagent \| bifrost-litellm/mimo-v2.5 \| 0.5 \| ... (GPT/DALL-E path, on explicit user request only); git commit/push denied \|` | `\| **video-generator** \| subagent \| bifrost-litellm/MiniMax-M3 \| 0.3 \| deny \| deny \| deny \| deny \| – \| Async video via media MCP (Hailuo 2.3/02, T2V-01; 5/6/10 s; 768P/1080P; first-frame i2v); polls video_status; only media.* MCP allowed \|` |
| M12 | L447: `\| **voice-synthesizer** \| subagent \| bifrost-litellm/MiniMax-M3 \| 0.3 \| deny \| **allow** \| allow \| **allow** \| – \| TTS via audio-synthesize skill (standard/clone/design modes); edit denied, task deny \|` | `\| **voice-synthesizer** \| subagent \| bifrost-litellm/MiniMax-M3 \| 0.3 \| deny \| deny \| deny \| deny \| – \| TTS via media MCP (MiMo TTS + VoiceDesign + MiniMax Speech-2.8-HD; 17 voices; styles; audio tags; wav/mp3); cloning moved to voice-clone; only media.* MCP allowed \|` + сразу после добавить 2 строки: `\| **voice-transcriber** \| subagent \| bifrost-litellm/MiniMax-M3 \| 0.1 \| deny \| deny \| deny \| deny \| – \| ASR via media MCP (zh/en auto-detect, dialects, code-switch, songs, noisy, multi-speaker); only media.* MCP allowed \|` и `\| **voice-clone** \| subagent \| bifrost-litellm/MiniMax-M3 \| 0.3 \| deny \| deny \| deny \| deny \| – \| Voice-clone TTS via media MCP (sample — URL / upload:<name> / base64; wav/mp3 ≤ 10 MB); only media.* MCP allowed \|` |
| M13 | L537: `Все 38 агентов, кроме \`scout\`, \`advisor\` и \`voice-synthesizer\`, имеют \`"unity-mcp.*": "allow"\` — полный доступ ко всем инструментам Unity MCP. Исключения: scout — локальный read-only FS-разведчик (read/glob/grep), определённый только frontmatter \`agents/scout.md\` (без секции в opencode.json); advisor — step-boundary reviewer, строго read-only, определён frontmatter + секцией opencode.json без unity-mcp.` | `Все 40 агентов, кроме \`scout\`, \`advisor\`, \`voice-synthesizer\`, \`image-creator\`, \`video-generator\`, \`voice-transcriber\` и \`voice-clone\`, имеют \`"unity-mcp.*": "allow"\` — полный доступ ко всем инструментам Unity MCP. Исключения: scout — локальный read-only FS-разведчик (read/glob/grep); advisor — step-boundary reviewer, строго read-only; медиа-агенты (voice-synthesizer, image-creator, video-generator, voice-transcriber, voice-clone) работают исключительно через media MCP — unity-mcp и остальные MCP-серверы для них denied, все файловые инструменты и bash denied.` |
| M14 | §6: `### orchestrator Whitelist (26 agents)` | `### orchestrator Whitelist (28 agents)` |
| M15 | §6 L683: `\| generate-image \| Image generation (Gemini) \|` | `\| image-creator \| Image creation (MCP media: generation + editing) \|` |
| M16 | §6 L684: `\| generate-image-gpt \| Image generation (GPT/DALL-E) \|` | `\| video-generator \| Video generation (MCP media: MiniMax Hailuo, async) \|` |
| M17 | §6 L687: `\| voice-synthesizer \| Voice synthesis (TTS) \|` | 3 строки: `\| voice-synthesizer \| Voice synthesis (TTS, MCP media) \|` + `\| voice-transcriber \| Speech-to-text (MCP media ASR) \|` + `\| voice-clone \| Voice cloning TTS (MCP media) \|` |
| M18 | §10 сниппет L908–909: `"generate-image", "generate-image-gpt", "git-commit",` / `"advisor", "voice-synthesizer"` | `"image-creator", "video-generator", "git-commit",` / `"advisor", "voice-synthesizer", "voice-transcriber", "voice-clone"` |
| M19 | §11 MCP Servers: после блока unity-mcp (перед `## 12. Commands`) вставить блок media — полный текст ниже |
| M20 | L1063: `Individual agent definitions (38 files)` | `Individual agent definitions (40 files)` |
| M21 | L1086: `### Agent Files List (38 files)` | `### Agent Files List (40 files)` |
| M22 | Дерево L1090–1126: строки `├── generate-image.md` и `├── generate-image-gpt.md` → `├── image-creator.md` и `├── video-generator.md`; рядом с `voice-synthesizer.md` добавить `├── voice-transcriber.md` и `├── voice-clone.md`; ОДНОВРЕМЕННО добавить недостающую строку `├── docs-planner.md` (предсуществующий баг дерева — 37 имён при заголовке 38) |
| M23 | L1253: `- [ ] Все 38 agent файлов скопированы в \`~/.config/opencode/agents/\`` | `- [ ] Все 40 agent файлов скопированы в \`~/.config/opencode/agents/\`` |
| M24 | L1272: `### Agent Files (38 total)` | `### Agent Files (40 total)` |
| M25 | L1278: `**Subagents (36):**` | `**Subagents (38):**` |
| M26 | Список L1279–1314: удалить `- generate-image.md`, `- generate-image-gpt.md`; добавить `- image-creator.md`, `- video-generator.md`, `- voice-transcriber.md`, `- voice-clone.md` |
| M27 | L1351: `orchestrator (26), plankestrator (10)` | `orchestrator (28), plankestrator (10)` |
| M28 | §1 Overview, блок `### MCP Servers` (начало L69): если там перечислены серверы — добавить `media` в том же формате (прочитать блок перед правкой) |

**M6 — новый текст blockquote (замена L61–67 целиком):**

```markdown
> **Media models (0 LLM-агентов — вызываются через media MCP, не являются моделями агентов):**
> - `voice/xiaomi/mimo-v2.5-tts` → media MCP — `voice-synthesizer` (standard TTS, preset voices)
> - `voice/xiaomi/mimo-v2.5-tts-voiceclone` → media MCP — `voice-clone` (voice cloning)
> - `voice/xiaomi/mimo-v2.5-tts-voicedesign` → media MCP — `voice-synthesizer` (voice design)
> - `voice/xiaomi/mimo-v2.5-asr` → media MCP — `voice-transcriber` (speech-to-text)
> - `minimax/speech-2.8-hd` → media MCP — `voice-synthesizer` (MiniMax system voices)
>
> Все — bifrost-litellm, не модели агентов: вызываются инструментами media MCP-сервера (remote, `https://hcbifrost.herocraft.com/litellm/media/mcp`). В счётчик Models Distribution (10 моделей агентов) не входят.
```

**M19 — блок media для §11 (вставить verbatim):**

```markdown
### media               — Remote (proxied via Bifrost)

| Field | Value |
|-------|-------|
| Type | Remote (proxied via Bifrost) |
| URL | `https://hcbifrost.herocraft.com/litellm/media/mcp` |
| Auth | `Authorization: Bearer {env:LITELLM_API_KEY}` |
| Enabled | true |

**Tools:**

| Tool | Purpose |
|------|---------|
| `media_media-generate_image` | Text → image (7 models: Gemini Flash/Pro, GPT Image 1.5/2/2.5-sunburst/2.5-flare, MiniMax image-01); `size` = `WxH` (OpenAI) или aspect ratio (MiniMax) |
| `media_media-edit_image` | Image → edited image (i2i, те же 7 моделей; MiniMax subject_reference) |
| `media_media-generate_video` | Async text/image → video (Hailuo 2.3/02, T2V-01; 5/6/10 s; 768P/1080P) → `{task_id}` |
| `media_media-video_status` | Poll video job → `{status}`; на Success — re-hosted `{url}` |
| `media_media-synthesize_speech` | TTS (MiMo preset voices / VoiceDesign / MiniMax Speech-2.8-HD; style; audio tags; wav/mp3) |
| `media_media-clone_speech` | TTS клонированным голосом (MiMo voiceclone; sample ≤10 MB) |
| `media_media-transcribe_audio` | ASR (MiMo v2.5; zh/en auto) → `{text, seconds}` |
| `media_media-list_media_models` | Живой каталог моделей/голосов/лимитов |

**Consumers:** image-creator, video-generator, voice-synthesizer, voice-clone, voice-transcriber (у всех `media.*: allow`, остальные MCP denied).

**Notes:** все инструменты возвращают hosted URLs (TTL 24 h) — никогда base64 в контексте. Загрузка локальных файлов пользователем: `POST https://hcbifrost.herocraft.com/media-upload?name=<file>` c `Authorization: Bearer <LITELLM_API_KEY>` → `{url, ref: "upload:<name>"}`.
```

### 4.4 `P:\Programming\Рефакторинг\PLUGIN.md`

| # | Якорь (old) | New |
|---|-------------|-----|
| P1 | L157: `\| generate-image \| Image generation (Gemini) \|` | `\| image-creator \| Image creation (MCP media: generation + editing) \|` |
| P2 | L158: `\| generate-image-gpt \| Image generation (GPT/DALL-E) \|` | `\| video-generator \| Video generation (MCP media: MiniMax Hailuo, async) \|` |
| P3 | L161: `\| voice-synthesizer \| Voice synthesis (TTS) \|` | 3 строки: `\| voice-synthesizer \| Voice synthesis (TTS, MCP media) \|` + `\| voice-transcriber \| Speech-to-text (MCP media ASR) \|` + `\| voice-clone \| Voice cloning TTS (MCP media) \|` |
| P4 | JS-массив (ДВА вхождения — L206–210 и L1026–1030, текст идентичен → replace-all): `'generate-image',` + `'generate-image-gpt',` + `'git-commit',` + `'advisor',` + `'voice-synthesizer'` | `'image-creator',` + `'video-generator',` + `'git-commit',` + `'advisor',` + `'voice-synthesizer',` + `'voice-transcriber',` + `'voice-clone'` |
| P5 | Зачистка: `rg -n "26 agents|\(26\)|38" PLUGIN.md` — все найденные счётчики whitelist/total привести к 28/40 (например заголовок `### orchestrator Whitelist (26 agents)`, если есть) |

### 4.5 `orchestrator.md` и `plankestrator.md` (live; deploy — через sync)

**`C:\Users\Admin\.config\opencode\agents\orchestrator.md` L26** — заменить ВСЮ строку verbatim:

Old:
```
OPENCODE_ROUTING_TABLE = ["orchestrator-identity-probe", "dev-reviewer", "dev-professor", "mcp-github", "worker", "bugfix", "rework", "mcp-read", "utility", "bugfix-triage", "plan-bug", "devops-agent", "devops-reviewer", "dev-planner", "mcp-search", "docs-writer", "summarizer", "execute-bug", "consistency-checker", "view-image", "docs-planner", "generate-image", "generate-image-gpt", "git-commit", "advisor", "voice-synthesizer"]
```
New:
```
OPENCODE_ROUTING_TABLE = ["orchestrator-identity-probe", "dev-reviewer", "dev-professor", "mcp-github", "worker", "bugfix", "rework", "mcp-read", "utility", "bugfix-triage", "plan-bug", "devops-agent", "devops-reviewer", "dev-planner", "mcp-search", "docs-writer", "summarizer", "execute-bug", "consistency-checker", "view-image", "docs-planner", "image-creator", "video-generator", "git-commit", "advisor", "voice-synthesizer", "voice-transcriber", "voice-clone"]
```
(28 записей — пересчитать после правки.)

**`C:\Users\Admin\.config\opencode\agents\plankestrator.md` L59** — внутри строки заменить фрагмент:

Old: `(generate-image* are orchestrator-only)`
New: `(image-creator and video-generator are orchestrator-only)`

Дополнительно проверить оба файла: `rg -n "generate-image" orchestrator.md plankestrator.md` → 0 после правки.

### 4.6 `deploy-package\README.md` и `deploy-package\scripts\verify.ps1` (правятся напрямую)

**README.md:**
- L97: `### Subagents (36)` → `### Subagents (38)`
- L99: в списке `... plankestrator-identity-probe, generate-image, generate-image-gpt, git-commit, scout, advisor, voice-synthesizer.` → `... plankestrator-identity-probe, image-creator, video-generator, git-commit, scout, advisor, voice-synthesizer, voice-transcriber, voice-clone.` (38 имён — пересчитать)

**verify.ps1:**
- L108: `Test-Check "Агенты: $agentCount/38 файлов" ($agentCount -ge 38) "Ожидается 38 файлов агентов"` → `Test-Check "Агенты: $agentCount/40 файлов" ($agentCount -ge 40) "Ожидается 40 файлов агентов"`
- L110–114 `$requiredAgents`: после `"advisor"` добавить `"image-creator", "video-generator", "voice-transcriber", "voice-clone"` (якорь — строка со `"scout", "advisor"`)
- Править ФАЙЛОВЫМ инструментом (кириллица в строке L108 — не ломать кодировку).

### 4.7 `P:\Programming\Рефакторинг\CHANGELOG.md`

Существующие записи `[Unreleased]` НЕ трогать (история цикла). Вставить новые bullet'ы в начало соответствующих секций и добавить секцию Removed. Формат дома: `- **название**: описание`.

После `### Changed` (L10) добавить:
```markdown
- **voice-synthesizer: миграция со скилла audio-synthesize на media MCP** (media_media-synthesize_speech; 3 TTS-модели — MiMo TTS, MiMo VoiceDesign, MiniMax Speech-2.8-HD; 17 голосов; style-инструкции; audio-теги; wav/mp3; режим клонирования вынесен в отдельный агент voice-clone; permissions ужаты — bash/write/read denied)
```

В секцию `### Added` добавить:
```markdown
- **image-creator** agent (media MCP: generate_image/edit_image; объединяет generate-image + generate-image-gpt; 7 gen + 7 edit моделей — Gemini Flash/Pro, GPT Image 1.5/2/2.5-sunburst/2.5-flare, MiniMax image-01; dialog-выбор модели, aspect ratio, chaining generate→edit→video)
- **video-generator** agent (media MCP: generate_video/video_status; MiniMax Hailuo 2.3/02, T2V-01; async-поллинг task_id; 5/6/10 с; 768P/1080P; image-to-video через first_frame_url)
- **voice-transcriber** agent (media MCP: transcribe_audio; ASR zh/en auto-detect, диалекты, code-switch, песни, шум, multi-speaker)
- **voice-clone** agent (media MCP: clone_speech; voice/xiaomi/mimo-v2.5-tts-voiceclone; sample — URL/upload:<name>/base64, wav/mp3 ≤10 МБ)
- **media MCP server** задокументирован: ARCHITECTURE.md §4 (таблица серверов + proxy), MCP_SETUP.md §11 (полный блок с 8 инструментами)
- orchestrator whitelist: 26 → 28 агентов (image-creator, video-generator, voice-transcriber, voice-clone)
- Total agents: 38 → 40; subagents: 36 → 38
```

После последнего bullet `### Added` (`- Unique models: 10 → 11 (voice/xiaomi/mimo-v2.5-tts)`) вставить новую секцию:
```markdown

### Removed

- **Агенты generate-image, generate-image-gpt** — заменены объединённым image-creator (media MCP вместо скилла image-gen)
- **Скиллы audio-synthesize, audio-transcribe** (`.opencode/skills/` + `~/.config/opencode/skills/`) — заменены media MCP (voice-synthesizer / voice-clone / voice-transcriber)
- **Скилл image-gen** (`~/.config/opencode/skills/` + `skills/`) — заменён media MCP (image-creator: generate_image/edit_image)
```

### 4.8 Дефолтные счётчики скиллов-валидаторов

- `.opencode\skills\integrity-check\scripts\check.py` L166–169: `default=38` → `default=40`; `default=26` (expected-orch) → `default=28`. (`expected-models` 10 и `expected-plan` 10 — без изменений.)
- `.opencode\skills\integrity-check\scripts\check.ps1`: rg `ExpectedAgents|ExpectedOrch` — те же замены дефолтов.
- `.opencode\skills\integrity-check\SKILL.md`: в примерах usage `--expected-agents 38` → `40`, `-ExpectedOrch 26` → `28`.
- `.opencode\skills\deploy-package-build\scripts\build.py` и `build.ps1` + `SKILL.md`: rg `ExpectedAgents|expected-agents` — дефолты 38→40, 26→28 (аналогично).
- Sweep-проверка: `rg -n "expected.?agents.*38|expected.?orch.*26" .opencode\skills -i` → 0 совпадений (кроме backup/).

**Контроль Phase 4 (после всех правок корневых документов):**

```powershell
cd P:\Programming\Рефакторинг
rg -c "generate-image" ARCHITECTURE.md AGENTS.md MCP_SETUP.md PLUGIN.md CHANGELOG.md deploy-package\README.md
# → ARCHITECTURE.md: 1 (только §6 Outdated Terms); AGENTS.md: 0; MCP_SETUP.md: 0; PLUGIN.md: 0; CHANGELOG.md: ≥1 (исторические + Removed записи — допустимо); README.md: 0
rg -n "\(26 agents\)|38 агентам|All 38|38 files|38 total|/38|-ge 38|\(36\)|Subagents \| 36|Subagents \(36\)" ARCHITECTURE.md AGENTS.md MCP_SETUP.md PLUGIN.md deploy-package\README.md deploy-package\scripts\verify.ps1
# → 0 совпадений (все счётчики обновлены)
rg -n "image-creator" ARCHITECTURE.md AGENTS.md MCP_SETUP.md PLUGIN.md | Measure-Object -Line   # ≥ 12 (присутствует во всех 4 доках)
rg -c "voice-clone|voice-transcriber|video-generator" ARCHITECTURE.md   # ≥ 6
```

---

## Phase 5 — opencode.json (live; deploy — через sync)

Файл: `C:\Users\Admin\.config\opencode\opencode.json` (1964 строки). ⚠️ task-блоки у многих агентов ОДИНАКОВЫ — якоря правок ОБЯЗАНЫ включать уникальные имена (правило из памяти проекта).

### 5.1 Заменить entry `voice-synthesizer` (L1109–1124)

Old (verbatim):
```json
    "voice-synthesizer": {
      "mode": "subagent",
      "temperature": 0.3,
      "permission": {
        "edit": "deny",
        "write": "allow",
        "bash": "allow",
        "read": "allow",
        "glob": "allow",
        "grep": "allow",
        "task": {
          "*": "deny"
        }
      },
      "options": {}
    },
```

New:
```json
    "voice-synthesizer": {
      "mode": "subagent",
      "temperature": 0.3,
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "read": "deny",
        "glob": "deny",
        "grep": "deny",
        "webfetch": "deny",
        "patch": "deny",
        "todowrite": "deny",
        "question": "deny",
        "task": {
          "*": "deny"
        },
        "serena.*": "deny",
        "unity-mcp.*": "deny",
        "zread.*": "deny",
        "webSearchPrime.*": "deny",
        "webReader.*": "deny",
        "zai-mcp-server.*": "deny",
        "media.*": "allow"
      },
      "options": {}
    },
```

### 5.2 Заменить entries `generate-image` + `generate-image-gpt` (L1125–1140) на 4 новых

Old (verbatim, оба блока):
```json
    "generate-image": {
      "permission": {
        "skill": {
          "*": "deny",
          "image-gen": "allow"
        }
      }
    },
    "generate-image-gpt": {
      "permission": {
        "skill": {
          "*": "deny",
          "image-gen": "allow"
        }
      }
    },
```

New (4 блока; permission-профиль идентичен voice-synthesizer из 5.1; у voice-transcriber temperature 0.1):
```json
    "image-creator": {
      "mode": "subagent",
      "temperature": 0.3,
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "read": "deny",
        "glob": "deny",
        "grep": "deny",
        "webfetch": "deny",
        "patch": "deny",
        "todowrite": "deny",
        "question": "deny",
        "task": {
          "*": "deny"
        },
        "serena.*": "deny",
        "unity-mcp.*": "deny",
        "zread.*": "deny",
        "webSearchPrime.*": "deny",
        "webReader.*": "deny",
        "zai-mcp-server.*": "deny",
        "media.*": "allow"
      },
      "options": {}
    },
    "video-generator": {
      "mode": "subagent",
      "temperature": 0.3,
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "read": "deny",
        "glob": "deny",
        "grep": "deny",
        "webfetch": "deny",
        "patch": "deny",
        "todowrite": "deny",
        "question": "deny",
        "task": {
          "*": "deny"
        },
        "serena.*": "deny",
        "unity-mcp.*": "deny",
        "zread.*": "deny",
        "webSearchPrime.*": "deny",
        "webReader.*": "deny",
        "zai-mcp-server.*": "deny",
        "media.*": "allow"
      },
      "options": {}
    },
    "voice-transcriber": {
      "mode": "subagent",
      "temperature": 0.1,
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "read": "deny",
        "glob": "deny",
        "grep": "deny",
        "webfetch": "deny",
        "patch": "deny",
        "todowrite": "deny",
        "question": "deny",
        "task": {
          "*": "deny"
        },
        "serena.*": "deny",
        "unity-mcp.*": "deny",
        "zread.*": "deny",
        "webSearchPrime.*": "deny",
        "webReader.*": "deny",
        "zai-mcp-server.*": "deny",
        "media.*": "allow"
      },
      "options": {}
    },
    "voice-clone": {
      "mode": "subagent",
      "temperature": 0.3,
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "read": "deny",
        "glob": "deny",
        "grep": "deny",
        "webfetch": "deny",
        "patch": "deny",
        "todowrite": "deny",
        "question": "deny",
        "task": {
          "*": "deny"
        },
        "serena.*": "deny",
        "unity-mcp.*": "deny",
        "zread.*": "deny",
        "webSearchPrime.*": "deny",
        "webReader.*": "deny",
        "zai-mcp-server.*": "deny",
        "media.*": "allow"
      },
      "options": {}
    },
```

### 5.3 Routing (task-allowlist orchestrator, L1579–1605)

Правка 1 — old:
```json
          "generate-image": "allow",
          "generate-image-gpt": "allow",
```
new:
```json
          "image-creator": "allow",
          "video-generator": "allow",
```

Правка 2 — old (последний элемент блока, БЕЗ завершающей запятой; якорь уникален):
```json
          "voice-synthesizer": "allow"
        }
```
new:
```json
          "voice-synthesizer": "allow",
          "voice-transcriber": "allow",
          "voice-clone": "allow"
        }
```

### 5.4 mcp-секция `media` — НЕ ТРОГАТЬ (уже настроена, L1058–1065).

**Контроль Phase 5:**

```powershell
powershell -NoProfile -Command "Get-Content 'C:\Users\Admin\.config\opencode\opencode.json' -Raw | ConvertFrom-Json | Out-Null; 'JSON OK'"
rg -c "generate-image|image-gen" C:\Users\Admin\.config\opencode\opencode.json   # 0
rg -c '"image-creator"|"video-generator"|"voice-transcriber"|"voice-clone"' C:\Users\Admin\.config\opencode\opencode.json   # 8 (4 entry-ключа + 4 task-allow)
rg -c '"media\.\*": "allow"' C:\Users\Admin\.config\opencode\opencode.json   # 5 (4 новых + voice-synthesizer)
```

---

## Phase 6 — workflow-enforcement.ts (live; ×3 через sync)

Файл: `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts`, ROUTING_TABLES L6–47.

Old (L29–33, verbatim):
```typescript
    "generate-image",
    "generate-image-gpt",
    "git-commit",
    "advisor",
    "voice-synthesizer"
```

New:
```typescript
    "image-creator",
    "video-generator",
    "git-commit",
    "advisor",
    "voice-synthesizer",
    "voice-transcriber",
    "voice-clone"
```

Массив orchestrator становится 28 записей. Plankestrator-массив не трогать. Других упоминаний generate-image в плагине нет (подтверждено grep).

**Контроль Phase 6:**

```powershell
rg -c "generate-image" C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts   # 0
rg -n '"image-creator"|"video-generator"|"voice-transcriber"|"voice-clone"' C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts   # 4 строки
# Подсчёт записей orchestrator-массива (ожидаемо 28):
powershell -NoProfile -Command "$t = Get-Content 'C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts' -Raw; $m = [regex]::Match($t, 'orchestrator:\s*\[(.*?)\]', 'Singleline'); ([regex]::Matches($m.Groups[1].Value, '\"[a-z0-9-]+\"')).Count"
```

---

## Phase 7 — Синхронизация всех копий

```powershell
cd P:\Programming\Рефакторинг

# 7.1 Отчёт о дрейфе (ожидание: расхождения только в наших новых правках)
python .opencode\skills\config-sync\scripts\sync.py --plan

# 7.2 Публикация live/root → deploy/opencode-config (все 7 групп: agents, config, plugin, architecture, mcp-setup, agents-md, plugin-md)
python .opencode\skills\config-sync\scripts\sync.py --apply --backup

# 7.3 Ручные копии live-документации в C:\Users\Admin\.config\opencode (НЕ входят в группы sync)
Copy-Item P:\Programming\Рефакторинг\ARCHITECTURE.md C:\Users\Admin\.config\opencode\ARCHITECTURE.md -Force
Copy-Item P:\Programming\Рефакторинг\MCP_SETUP.md    C:\Users\Admin\.config\opencode\MCP_SETUP.md -Force
Copy-Item P:\Programming\Рефакторинг\PLUGIN.md       C:\Users\Admin\.config\opencode\PLUGIN.md -Force
```

Примечания:
- Группа `agents` копирует live → deploy: 4 новых .md появятся в `deploy-package\agents\`, изменённые (voice-synthesizer, orchestrator, plankestrator) перезапишутся. Удалённые deploy-файлы уже стёрты в Phase 3.
- Группа `agents-md` покрывает все 4 копии AGENTS.md (root → opencode-config → deploy project-files → live .config).
- Live-копии MCP_SETUP.md/PLUGIN.md в .config до перезаписи могут иметь легаси-дрейф (память проекта: «устарели, отдельный тикет») — перезапись корневой версией это осознанно устраняет; root — source of truth.

**Контроль Phase 7 (байт-идентичность):**

```powershell
$pairs = @(
 @("C:\Users\Admin\.config\opencode\opencode.json","P:\Programming\Рефакторинг\deploy-package\opencode.json"),
 @("C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts","P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts"),
 @("P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts","P:\Programming\Рефакторинг\deploy-package\plugins\workflow-enforcement.ts"),
 @("P:\Programming\Рефакторинг\ARCHITECTURE.md","P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md"),
 @("P:\Programming\Рефакторинг\ARCHITECTURE.md","P:\Programming\Рефакторинг\deploy-package\project-files\ARCHITECTURE.md"),
 @("P:\Programming\Рефакторинг\ARCHITECTURE.md","C:\Users\Admin\.config\opencode\ARCHITECTURE.md"),
 @("P:\Programming\Рефакторинг\AGENTS.md","C:\Users\Admin\.config\opencode\AGENTS.md"),
 @("P:\Programming\Рефакторинг\AGENTS.md","P:\Programming\Рефакторинг\opencode-config\AGENTS.md"),
 @("P:\Programming\Рефакторинг\AGENTS.md","P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md"),
 @("P:\Programming\Рефакторинг\MCP_SETUP.md","P:\Programming\Рефакторинг\deploy-package\project-files\MCP_SETUP.md"),
 @("P:\Programming\Рефакторинг\MCP_SETUP.md","C:\Users\Admin\.config\opencode\MCP_SETUP.md"),
 @("P:\Programming\Рефакторинг\PLUGIN.md","P:\Programming\Рефакторинг\opencode-config\PLUGIN.md"),
 @("P:\Programming\Рефакторинг\PLUGIN.md","P:\Programming\Рефакторинг\deploy-package\project-files\PLUGIN.md"),
 @("P:\Programming\Рефакторинг\PLUGIN.md","C:\Users\Admin\.config\opencode\PLUGIN.md")
)
foreach ($p in $pairs) { fc.exe /b $p[0] $p[1] | Select-Object -First 1 }
# → везде "FC: no differences encountered"

foreach ($a in "image-creator","video-generator","voice-transcriber","voice-clone","voice-synthesizer","orchestrator","plankestrator") {
  fc.exe /b "C:\Users\Admin\.config\opencode\agents\$a.md" "P:\Programming\Рефакторинг\deploy-package\agents\$a.md" | Select-Object -First 1 }
# → везде no differences

(Get-ChildItem P:\Programming\Рефакторинг\deploy-package\agents\*.md).Count   # 40
(Get-ChildItem C:\Users\Admin\.config\opencode\agents\*.md).Count             # 40
```

---

## Phase 8 — Верификация

### 8.1 Файлы созданы/удалены

```powershell
# Созданы (live + deploy):
foreach ($a in "image-creator","video-generator","voice-transcriber","voice-clone") {
  Test-Path "C:\Users\Admin\.config\opencode\agents\$a.md"; Test-Path "P:\Programming\Рефакторинг\deploy-package\agents\$a.md" }   # 8 × True
# Удалены: контроль Phase 3 повторить (10 × False)
```

### 8.2 Синтаксис и целостность

```powershell
cd P:\Programming\Рефакторинг
# JSON (обе копии):
powershell -NoProfile -Command "Get-Content 'C:\Users\Admin\.config\opencode\opencode.json' -Raw | ConvertFrom-Json | Out-Null; 'live JSON OK'"
powershell -NoProfile -Command "Get-Content 'P:\Programming\Рефакторинг\deploy-package\opencode.json' -Raw | ConvertFrom-Json | Out-Null; 'deploy JSON OK'"

# Полный integrity-check с НОВЫМИ счётчиками:
python .opencode\skills\integrity-check\scripts\check.py --json --expected-agents 40 --expected-models 10 --expected-orch 28 --expected-plan 10
# → exit code 0; все 7 checks PASS (JSON, COUNT 40/40, PAIR SHA256 live=deploy, FORMAT+EXISTS model keys, COUNT models=10 + MCP_SETUP Distribution/Summary rows, COUNT routing 28/10 из 3 источников: opencode.json task-allows + ARCHITECTURE header/rows + plugin ROUTING_TABLES)

# verify.ps1 (обновлён в Phase 4.6):
powershell -NoProfile -File P:\Programming\Рефакторинг\deploy-package\scripts\verify.ps1   # все Test-Check PASS (40/40)

# Frontmatter новых агентов валиден (нет ": " в description):
rg -n "^description: .*: " C:\Users\Admin\.config\opencode\agents\image-creator.md C:\Users\Admin\.config\opencode\agents\video-generator.md C:\Users\Admin\.config\opencode\agents\voice-transcriber.md C:\Users\Admin\.config\opencode\agents\voice-clone.md C:\Users\Admin\.config\opencode\agents\voice-synthesizer.md
# → 0 совпадений
```

### 8.3 Зачистка устаревших терминов (глобальный sweep)

```powershell
rg -n "generate-image|audio-synthesize|audio-transcribe|image-gen" `
  C:\Users\Admin\.config\opencode\agents C:\Users\Admin\.config\opencode\opencode.json `
  C:\Users\Admin\.config\opencode\plugins C:\Users\Admin\.config\opencode\skills `
  C:\Users\Admin\.config\opencode\ARCHITECTURE.md C:\Users\Admin\.config\opencode\AGENTS.md `
  C:\Users\Admin\.config\opencode\MCP_SETUP.md C:\Users\Admin\.config\opencode\PLUGIN.md `
  P:\Programming\Рефакторинг\AGENTS.md P:\Programming\Рефакторинг\MCP_SETUP.md P:\Programming\Рефакторинг\PLUGIN.md `
  P:\Programming\Рефакторинг\opencode-config P:\Programming\Рефакторинг\plugins P:\Programming\Рефакторинг\skills `
  P:\Programming\Рефакторинг\deploy-package P:\Programming\Рефакторинг\.opencode\skills `
  -g "!node_modules" -g "!*.7z"
```

**Допустимые остатки (белый список — только эти):**
1. `ARCHITECTURE.md` ×4 — §6 Outdated Terms (строки A23 — намеренная документация запрета);
2. `CHANGELOG.md` — исторические записи [Unreleased] + новая секция Removed;
3. `.opencode\skills\model-key-validate\SKILL.md` L82 — пример вывода `SKIP:generate-image ...` (косметика; опционально поправить на image-creator — nit, не блокирует);
4. `backup\**` и исторические `PLAN_*.md`/`RESEARCH_*.md` — не трогаем;
5. `voice-synthesizer.md` — фраза-запрет "Never use the old audio-synthesize skill" (намеренная).

Всё прочее — удалить/исправить.

### 8.4 MCP-инструменты доступны агентам (smoke-тест — только в НОВОЙ сессии opencode)

Конфиг читается НА СТАРТЕ СЕССИИ — старые сессии не видят изменений.

1. Новая сессия: `opencode --agent orchestrator` (имя сессии: `orchestrator — media agents smoke test`).
2. Task → `voice-synthesizer`: «Скажи "Проверка связи" голосом mimo_default, формат mp3» → ожидание: JSON `{"agent":"voice-synthesizer","status":"success","url":"https://..."}`, URL открывается.
3. Task → `image-creator`: «Создай тестовое изображение 1024x1024, модель по умолчанию, стиль минимализм» → ожидание: hosted URL от `media_media-generate_image`.
4. (Опционально) Task → `voice-transcriber` с URL аудио из п.2 → ожидание: текст расшифровки.
5. Плагин не блокирует: в логах сессии нет `⛔ routing violation` для новых агентов.
6. (Опционально) `video-generator` — дорогостоящий/долгий тест, по желанию пользователя.

Критерий: новые агенты вызываются через Task, MCP-инструменты `media_*` им доступны, старые агенты из routing исчезли.

---

## Phase 9 — Коммит и пуш

⚠️ Правило проекта: прямые `git commit`/`git push` ЗАПРЕЩЕНЫ — только через агента `git-commit` (вызывает orchestrator через Task). Live-конфиг `C:\Users\Admin\.config\opencode\` вне git — в репозиторий попадают проектные копии (deploy-package, opencode-config, root-доки, plugins, .opencode/skills).

1. `git status --short` — обзор изменённых файлов (ожидаемо: root-доки ×5, opencode-config ×2, deploy-package (agents ±, opencode.json, plugins, project-files ×3, README.md, scripts/verify.ps1), plugins/workflow-enforcement.ts, .opencode/skills (−2 каталога, integrity-check/deploy-package-build правки), skills/ (−image-gen)).
2. Task → `git-commit` с сообщением (conventional):

```
feat(agents): migrate media agents to media MCP

- add image-creator (replaces generate-image + generate-image-gpt; 7 gen + 7 edit models)
- add video-generator (async Hailuo 2.3/02/T2V-01, 5/6/10s, 768P/1080P, i2v)
- add voice-transcriber (ASR zh/en auto) and voice-clone (voiceclone TTS)
- rework voice-synthesizer onto media MCP synthesize_speech (3 TTS models, 17 voices)
- remove generate-image/generate-image-gpt agents; remove audio-synthesize, audio-transcribe, image-gen skills
- counters: 38->40 agents, orchestrator whitelist 26->28; docs synced (ARCHITECTURE/AGENTS/MCP_SETUP/PLUGIN/README/CHANGELOG); plugin + opencode.json routing updated; verify.ps1/integrity-check defaults bumped
```

3. Пуш: `git push origin master` — через git-commit-агента (gated flow) или по его инструкции.

**Контроль Phase 9:** `git log -1 --stat` — коммит содержит все ожидаемые файлы; `git status` — clean.

---

## Edge Cases

1. **Порядок замен:** `generate-image-gpt` ВСЕГДА обрабатывать раньше `generate-image` при глобальных regex-заменах (иначе `generate-image`-замена оставляет хвост `-gpt`).
2. **YAML-грабля (silent drop):** `": "` в незакавыченном `description:` ломает frontmatter — все 5 описаний проверены (только тире/запятые/скобки). После создания — проверка rg из Phase 8.2.
3. **Кодировки:** кириллица в диалогах агентов, CHANGELOG, verify.ps1 — править только файловыми инструментами (UTF-8); PowerShell 5.1 `Set-Content` по умолчанию пишет ANSI/cp1251.
4. **Уникальность якорей в opencode.json:** task-блоки десятков агентов идентичны — якоря правок 5.3 включают уникальные имена (`"generate-image": "allow"`, `"voice-synthesizer": "allow"` + закрывающая `}`); перед каждой заменой `rg -c <якорь>` → 1.
5. **Синтаксис permission-ключа `media.*`:** в проекте уже используются паттерны `<server>.*` (serena.*, unity-mcp.*, zread.*). Если smoke-тест покажет, что opencode отвергает `media.*: allow` — fallback: удалить этот ключ (MCP-инструменты разрешены по умолчанию; остальные deny-ключи оставить). Проверка — Phase 8.4.
6. **Точная схема `media_media-edit_image`** на момент планирования не видна (не экспонирована в сессию планировщика) — серверный каталог подтверждает существование (notes: "edit_image modifies an existing image (i2i)"). Промпт image-creator намеренно не перечисляет параметры edit_image — агент читает схему инструмента в рантайме.
7. **Дрейф live-копий MCP_SETUP/PLUGIN в .config:** перед перезаписью (Phase 7.3) зафиксировать `fc /b` — если расхождения НЕ сводятся к нашим правкам, это предсуществующий дрейф; root остаётся source of truth (память проекта: live-копии устарели, отдельный тикет — перезапись его закрывает).
8. **Предсуществующие баги документации (чиним попутно):** дерево Agent Files List в MCP_SETUP не содержит `docs-planner.md` (M22); таблица unity-mcp-исключений в ARCHITECTURE не перечисляет scout/voice-synthesizer (A22 добавляет сводную строку медиа-агентов; строку для scout добавлять НЕ обязательно — nit).
9. **Счётчики в скиллах:** `check.py`/`build.py` имеют дефолты 38/26 — без Phase 4.8 будущие запуски integrity-check/deploy-package-build будут падать или ложно проходить. Sweep rg в 4.8 обязателен.
10. **Новая сессия обязательна:** opencode читает конфиг на старте — smoke-тесты и использование новых агентов только в новой сессии.
11. **Hosted URL TTL 24 ч:** агенты возвращают URL, ничего не скачивают; пользователям с локальными файлами агенты выдают инструкцию POST /media-upload (bash у агентов denied — сами загрузить не могут, это by design).
12. **Не перестараться с удалениями:** `skills\git-commit` и user-level `git-commit` скилл — НЕ удалять; `.opencode\skills\*` (кроме audio-*) — НЕ удалять; `generated-images\` — оставить.
13. **LITELLM_API_KEY:** media MCP авторизуется через env-переменную — должна быть задана в окружении opencode (уже работает для провайдера; отдельной настройки нет).
14. **plankestrator не получает медиа-агентов:** все 5 — только orchestrator-whitelist (медиа-генерация = операционные задачи); plankestrator остаётся 10.

## Dependencies

- **Перед стартом:** чистое git-дерево (`git status`); Python 3.8+ в PATH (скиллы backup-snapshot/config-sync/integrity-check); PowerShell 5.1+; `LITELLM_API_KEY` в env.
- **Media MCP-сервер:** настроен в opencode.json (mcp.media, remote, enabled) и ПРОВЕРЕН на этапе планирования (`media_media-list_media_models` вернул полный каталог 2026-09-27).
- **Порядок фаз строгий:** 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 (sync ПОСЛЕ всех правок source-копий) → 8 → 9. integrity-check (8.2) валиден только после Phase 7 (PAIR-проверка live↔deploy).
- **Вне объёма:** обновление `.serena` memories (project-overview содержит старые счётчики 38/26 — обновить отдельной задачей после merge), `instructions.md` в .config (не содержит медиа-агентских ссылок по итогам grep), резервная копия `.opencode/skills/model-key-validate/SKILL.md` L82 (nit).
