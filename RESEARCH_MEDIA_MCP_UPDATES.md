# Media MCP Updates Research

Исследование от 2026-10-07. Источники: live-каталог `media-list_media_models`
(обновлённый media MCP) и текущие файлы агентов в
`C:\Users\Admin\.config\opencode\agents\`. Сравнение возможностей MCP с
документацией агентов и рекомендуемые правки промптов.

---

## Update 2026-10-07: reference_media confirmed

Сервер media MCP обновлён. Параметр `reference_media` теперь доступен в схеме `generate_video`.

**Спецификация (MiniMax v2 API, reference-to-video):**
- До 15 items в массиве
- Источники: http(s) URL | upload:<name> | data-URI | base64
- Роль по magic bytes: image/* (≤9), video/* (≤3), audio/* (≤3)
- Картинки → data-URI (MiniMax ненадёжно фетчит /media-files)
- Видео/аудио → http(s) URL (base64 раздует за лимит 64MB)

**Рекомендация:** обновить video-generator.md с документацией reference_media.

---

## Current MCP Capabilities

### Image Models

| Model id | Описание |
|----------|----------|
| `gemini/gemini-3.1-flash-image` | fast, cheap, good default |
| `gemini/gemini-3-pro-image` | higher quality, slower |
| `gpt-image-1.5` | OpenAI image gen |
| `gpt-image-2` | OpenAI image gen |
| `gpt-image-2.5-sunburst` | OpenAI image gen variant |
| `gpt-image-2.5-flare` | OpenAI image gen variant |
| `minimax/image-01` | MiniMax t2i (aspect_ratio через `size`) |

Итого: 7 моделей генерации.

### Image Edit Models

Те же 7 model id поддерживают редактирование (i2i):
`gemini/gemini-3.1-flash-image` (fast edit, default), `gemini/gemini-3-pro-image`
(higher quality edit), `gpt-image-1.5`, `gpt-image-2`, `gpt-image-2.5-sunburst`,
`gpt-image-2.5-flare`, `minimax/image-01` (MiniMax i2i via `subject_reference` —
character/style transfer).

Параметры `edit_image` по схеме инструмента: `image` (source), `prompt`,
`model`, `size` (optional, `WxH` — для OpenAI-моделей). Формы входа `image`:
http(s) URL | data-URI | `upload:<name>` | base64. Выход `edit_image` можно
передавать в `generate_video.first_frame_url`.

### Video Models

| Model id | Описание |
|----------|----------|
| `MiniMax-H3` | newest H3 (v2 API, up to 2K, first/last frame + reference inputs, PAYG billing) |
| `MiniMax-Hailuo-2.3` | v1 flagship, good quality (TokenPlan) |
| `MiniMax-Hailuo-02` | v1 previous generation |
| `T2V-01` | v1 legacy text-to-video |

Параметры `generate_video` по схеме: `prompt`, `model`, `duration_s`
(5 | 6 | 10), `resolution` (768P | 1080P | 2K — только H3), `ratio`
(16:9 | 4:3 | 1:1 | 3:4 | 9:16 | 21:9 | adaptive — только i2v),
`first_frame_url`, `last_frame_url` (H3 only), `reference_media` (H3 only,
до 15 items: image/video/audio источники с автоматическим определением роли
по magic bytes). Каталог подтверждает «reference media / reference inputs»
для H3.

### TTS Models

| Model id | Описание |
|----------|----------|
| `voice/xiaomi/mimo-v2.5-tts` | preset mimo voices + style instructions; singing via `(唱歌)` tag |
| `voice/xiaomi/mimo-v2.5-tts-voicedesign` | free-form voice from `style` description (style REQUIRED; `voice` NOT supported) |
| `minimax/speech-2.8-hd` | system voices (TokenPlan) or cloned `voice_id` from `register_voice_clone` (auto-routed to PAYG) |

Параметры `synthesize_speech` по схеме инструмента: `text`, `model`, `voice`,
`style`, `format`. **Отдельного параметра `voice_id` в схеме НЕТ** — описание
параметра `voice`: «mimo presets / minimax system voices / a cloned voice_id
from register_voice_clone». Каталог: `synthesize_speech(model='minimax/speech-2.8-hd', voice=<voice_id>)`.

Голоса:
- MiMo (9): `mimo_default`, `冰糖`, `茉莉`, `苏打`, `白桦`, `Mia`, `Chloe`, `Milo`, `Dean`
- MiniMax (8): `female-shaonv`, `female-yujie`, `male-qn-qingse`, `male-qn-jingying`, `presenter_male`, `presenter_female`, `audiobook_male_1`, `audiobook_female_1`

Форматы аудио: `wav`, `mp3`. `style` = natural-language инструкция (эмоция,
темп, акцент); audio-теги `(laughs)`, `(sighs)`, `(唱歌)` — внутри `text`.

### Voice Clone Models

| Режим | Модель / инструмент | Описание |
|-------|---------------------|----------|
| Zero-shot | `voice/xiaomi/mimo-v2.5-tts-voiceclone` (`clone_speech`) | sample передаётся с каждым запросом |
| Persistent | `minimax/speech-2.8-hd` (`register_voice_clone`) | reusable `voice_id` → далее `synthesize_speech(..., voice=<voice_id>)` |

Требования к семплу: wav/mp3, ≤ 10 MB, чистая речь; zero-shot — несколько
секунд, persistent — ≥ ~10 s (рекомендация MiniMax). Параметры
`register_voice_clone`: `sample`, `voice_id` (кастомное имя: начинается с
буквы, ≥ 8 символов, буквы/цифры/`-`/`_`), `noise_reduction`,
`volume_normalization`. Выход: `{voice_id, file_id, usage}`.

### ASR Models

Единственная модель: `voice/xiaomi/mimo-v2.5-asr`. Инструмент
`transcribe_audio(source, language)` → `{text, seconds}`; `language`:
`auto` | `zh` | `en`. Вход `source`: http(s) URL | data-URI | `upload:<name>` |
base64, wav/mp3 ≤ 10 MB.

### Общие правила MCP (notes)

- Все инструменты возвращают hosted URL (файлы живут 24 ч) — никогда base64 в контекст
- Загрузка локального файла: `POST https://hcbifrost.herocraft.com/media-upload?name=<file>` с `Authorization: Bearer <LiteLLM key>` → ответ даёт `url` и `ref` (`upload:<name>`)
- Видео асинхронное: `generate_video` → `task_id` → poll `video_status` до `Success`
- Длительности видео: 5 / 6 / 10 с; разрешения: 768P / 1080P / 2K (2K — только H3)
- H3/H3-Max и voice_clone биллятся на MiniMax PAYG аккаунт

---

## Current Agent State

### image-creator

- **Documented models:** 7/7 генерации и 7/7 редактирования — полное совпадение с каталогом; `size`-правила для gpt-image (WxH), minimax (aspect ratio) и Gemini (omit) описаны корректно; chaining с `video-generator` (`first_frame_url`) на месте.
- **Missing / некорректно:**
  1. Параметры `edit_image` не задокументированы явно («exact params — from the tool schema»): нет списка `image`, `prompt`, `model`, `size`; не описано, что `size` для edit — output size `WxH` у OpenAI-моделей.
  2. Не описаны формы входа `image`: http(s) URL | data-URI | `upload:<name>` | base64; нет инструкции загрузки локального файла (в отличие от voice-clone/voice-transcriber).
  3. `subject_reference` у `minimax/image-01` упомянут («см. tool schema»), но в схеме `edit_image` такого параметра нет (только `image/prompt/model/size`) — механизм передачи character/style reference не определён.
  4. Диалоговое меню показывает только 4 модели (нет gpt-image-1.5, 2.5-sunburst, 2.5-flare).
- **Recommended changes:**
  - КРИТИЧНО: нет.
  - ВАЖНО: заменить «exact params — from the tool schema» на явную таблицу параметров `edit_image` (`image`, `prompt`, `model`, `size`); добавить раздел «Входное изображение» с формами `image` и upload-рецептом (curl raw body, как в voice-clone).
  - ВАЖНО: уточнить или снять формулировку про `subject_reference` (как именно передаётся character/style reference — параметр, `image` или prompt-инструкция).
  - ОПЦИОНАЛЬНО: расширить диалоговое меню списком GPT-вариантов или пометкой «GPT-варианты по запросу».

### video-generator

- **Documented models:** 4/4 (`MiniMax-H3`, `MiniMax-Hailuo-2.3`, `MiniMax-Hailuo-02`, `T2V-01`) — совпадение; параметры `prompt`, `duration_s`, `resolution`, `ratio` (включая `21:9` и `adaptive`), `first_frame_url`, `last_frame_url`, `reference_media` описаны полностью; async-протокол, billing, warning про невалидные frame URL — на месте.
- **Missing / некорректно:**
  1. «Reference media» для H3 заявлено в frontmatter description (L2) И в строке таблицы моделей (L43), и теперь подтверждено схемой `generate_video` (параметр `reference_media`). Расхождение устранено — сервер обновлён.
  2. «H3-Max» упомянут в Billing, но в каталоге video_models его нет (только `MiniMax-H3` как v2-флагман).
- **Recommended changes:**
  - КРИТИЧНО: нет.
  - ВАЖНО: добавить документацию параметра `reference_media` в раздел Parameters video-generator.md (до 15 items, magic bytes для определения роли, передача картинок через data-URI, видео/аудио через http(s) URL).
  - ОПЦИОНАЛЬНО: уточнить формулировку Billing: «H3-Max» → привести в соответствие с каталогом (или явно указать, что H3-Max = тот же PAYG-класс).

### voice-synthesizer

- **Documented models:** 3/3 TTS-модели, 17 голосов (9 MiMo + 8 MiniMax), binding голос↔модель, `style`, `(唱歌)`, `format` wav/mp3, billing — всё совпадает с каталогом.
- **Missing / некорректно:**
  1. **Несуществующий параметр `voice_id`.** Агент описывает
     `synthesize_speech(text, model, voice, voice_id, style, format)` и передаёт
     `voice_id="ref_voice_26x2"` в примерах. По схеме инструмента параметров
     `voice_id` НЕТ: зарегистрированный clone `voice_id` передаётся через
     `voice` (`synthesize_speech(model='minimax/speech-2.8-hd', voice=<voice_id>)`
     — так указано и в каталоге MCP, и в глобальных правилах).
- **Recommended changes:**
  - КРИТИЧНО: исправить сигнатуру инструмента на
    `synthesize_speech(text, model, voice, style, format)`; во всех примерах и
    правилах заменить вызовы `voice_id="..."` на `voice="<clone voice_id>"`;
    в разделе «Registered clone voices» уточнить: «clone voice_id передаётся в
    параметр `voice` вместе с `model='minimax/speech-2.8-hd'`»; поле `voice_id`
    оставить только в Final JSON (как выходное), либо переименовать для ясности.
  - ОПЦИОНАЛЬНО: добавить хинт, что `style` поддержан и для MiniMax
    `speech-2.8-hd` (в схеме он не REQUIRED, кроме voicedesign).

### voice-clone

- **Documented models:** оба режима (zero-shot `voice/xiaomi/mimo-v2.5-tts-voiceclone` через `clone_speech`; persistent `minimax/speech-2.8-hd` через `register_voice_clone`) — совпадение с каталогом.
- **Missing / некорректно:**
  1. **Пропагация несуществующего параметра `voice_id`** (та же ошибка, что и в
     voice-synthesizer): агент в 3 местах учит передавать clone id как
     `voice_id` в `synthesize_speech` — таблица режимов (L52:
     `synthesize_speech(model='minimax/speech-2.8-hd', voice_id=<id>)`),
     диалоговый пример (L124–125) и Rules (L146: «`synthesize_speech` with
     `voice_id`»). По схеме инструмента параметра `voice_id` у
     `synthesize_speech` нет — clone id передаётся через `voice`. (Параметр
     `voice_id` самого `register_voice_clone` при этом корректен — ошибка
     только в вызовах `synthesize_speech`.)
- Совпадения (проверено, правки не нужны): сигнатуры `clone_speech(text, sample, style, format)` и `register_voice_clone(sample, voice_id, noise_reduction, volume_normalization)` совпадают со схемами инструментов; требования к семплу (wav/mp3, ≤ 10 MB, чистая речь; zero-shot — секунды, persistent — ≥ ~10 s) совпадают; upload-рецепт (raw body + Content-Type, не multipart) — самый полный среди агентов; правила `voice_id` naming совпадают со схемой.
- **Recommended changes:**
  - КРИТИЧНО (одним коммитом с voice-synthesizer): в L52, L124–125 и L146
    заменить `voice_id=<id>` на `voice=<id>` в вызовах/описаниях
    `synthesize_speech`.
  - ОПЦИОНАЛЬНО: добавить расшифровку выхода `register_voice_clone`
    (`usage` — как использовать `voice_id`); сослаться, что `upload:<name>`
    работает и для `sample`.

### voice-transcriber

- **Documented models:** единственная ASR-модель `voice/xiaomi/mimo-v2.5-asr` — совпадение; `transcribe_audio(source, language)` → `{text, seconds}`, `language`: auto/zh/en — совпадает со схемой; формы входа `source` перечислены.
- **Missing / некорректно:**
  1. Upload-инструкция упрощённая (3 шага, только `Authorization` header) — без проверенного рецепта из voice-clone: Content-Type должен совпадать с форматом (`audio/wav` / `audio/mpeg`), raw body (`--data-binary`), НЕ multipart (`-F` отклоняется), `name` обязан содержать расширение. Для аудио те же подводные камни, что и при клонировании.
- **Recommended changes:**
  - ВАЖНО: синхронизировать раздел «Local files» с upload-рецептом из voice-clone (curl-пример, raw body, Content-Type, расширение в `name`).
  - ОПЦИОНАЛЬНО: добавить ограничение wav/mp3 ≤ 10 MB в frontmatter description.

---

## Summary of Recommended Changes

### Critical

- **voice-synthesizer** — убрать несуществующий параметр `voice_id` из сигнатуры `synthesize_speech` и из примеров: зарегистрированный clone voice_id передаётся через `voice` при `model='minimax/speech-2.8-hd'` (подтверждено схемой инструмента и каталогом MCP). Задеть: сигнатуру инструмента (строка ~40), вводный split-блок (L36: `model='minimax/speech-2.8-hd'` + `voice_id=<id>`), раздел «Registered clone voices», диалоговые примеры (`voice_id="ref_voice_26x2"` → `voice="ref_voice_26x2"`), правило о клонах, Final JSON (поле оставить только как выходное).
- **voice-clone** — пропагация той же ошибки в 3 местах (L52, L124–125, L146: `synthesize_speech(..., voice_id=<id>)` → `voice=<id>`); чинить одним коммитом с voice-synthesizer, иначе агенты продолжат противоречить друг другу.

### Important

- **image-creator** — задокументировать параметры `edit_image` явно
  (`image`, `prompt`, `model`, `size`) вместо «exact params — from the tool
  schema»; добавить формы входа `image` (http(s) URL | data-URI |
  `upload:<name>` | base64) и upload-рецепт для локальных файлов.
- **image-creator** — уточнить механизм `subject_reference` для
  `minimax/image-01` edit: в схеме `edit_image` такого параметра нет — как
  именно передаётся character/style reference (или снять утверждение).
- **video-generator** — добавить документацию параметра `reference_media` в
  раздел Parameters (до 15 items, magic bytes для определения роли, передача
  картинок через data-URI, видео/аудио через http(s) URL). Упоминание
  «reference media» в description и таблице моделей теперь подтверждено схемой
  — расхождение устранено.
- **voice-transcriber** — дополнить upload-инструкцию проверенным рецептом из
  voice-clone (raw body `--data-binary`, Content-Type `audio/wav`|`audio/mpeg`,
  `name` с расширением, не multipart).

### Optional

- **image-creator** — расширить диалоговое меню полным списком GPT-моделей
  (1.5, 2.5-sunburst, 2.5-flare) или пометкой «по запросу».
- **video-generator** — уточнить Billing: «H3-Max» отсутствует в каталоге
  video_models (есть только `MiniMax-H3`).
- **voice-synthesizer** — добавить хинт, что `style` работает и с
  `minimax/speech-2.8-hd` (не REQUIRED, кроме voicedesign).
- **voice-clone** — расшифровать поле `usage` из ответа
  `register_voice_clone` и упомянуть `upload:<name>` как валидную форму `sample`.
- **voice-transcriber** — вынести «wav/mp3, ≤ 10 MB» в frontmatter description.
- **Все агенты** — при желании добавить cross-link: выход `edit_image` можно
  передавать в `video-generator` как `first_frame_url` (сейчас есть только у
  image-creator/video-generator).

### Применение правок

Правки вносить в LIVE-файлы `C:\Users\Admin\.config\opencode\agents\*.md`
(только body промптов; frontmatter без нужды не трогать), после правок —
`config-sync --save` для снапшота в репо (sync-пары, см. ARCHITECTURE.md).
Изменения агентов подхватываются только в НОВОЙ сессии opencode.

## Limitations

- Механизм «reference media / reference inputs» для H3: каталог заявляет, но
  параметра в схеме `generate_video` нет; до выяснения у владельца media MCP
  безопаснее УБРАТЬ упоминание из документации агента, а не описывать
  гипотетический способ передачи.
- Форма выхода `register_voice_clone` (`{voice_id, file_id, usage}`) взята из
  текущего voice-clone.md (тестовый опыт агента), а не из каталога MCP —
  сверить с фактическим ответом инструмента при ближайшей регистрации.
- Рекомендации по upload-рецепту (raw body, Content-Type, не multipart)
  опираются на задокументированный опыт voice-clone.md (`audio/wav`
  проверен; `audio/mpeg` — по аналогии, явно не проверен).
