---
name: audio-synthesize
description: 'Text-to-speech synthesis using MiMo-V2.5-TTS via bifrost-litellm API. Supports standard TTS, voice design, and voice clone modes.'
---

# Audio Synthesize Skill

## Purpose

Synthesize speech from text using Xiaomi MiMo-V2.5-TTS models via bifrost-litellm API.

## API Details

- **Endpoint:** `https://hcbifrost.herocraft.com/litellm/v1/chat/completions`
- **Models (by mode):** see [Models by Mode](#models-by-mode)
- **Auth:** `LITELLM_API_KEY` environment variable
- **Response:** `choices[0].message.audio.data` (base64-encoded audio)

## Models by Mode

| Mode | Model |
|------|-------|
| Standard TTS | `voice/xiaomi/mimo-v2.5-tts` |
| Voice Clone | `voice/xiaomi/mimo-v2.5-tts-voiceclone` |
| Voice Design | `voice/xiaomi/mimo-v2.5-tts-voicedesign` |

The script automatically selects the correct model based on mode.

## Modes

### 1. Standard TTS (`voice/xiaomi/mimo-v2.5-tts`)
- `user` message: voice description or instruction
- `assistant` message: text to synthesize
- `audio.voice`: voice name (default: "mimo_default")

### 2. Voice Design (`voice/xiaomi/mimo-v2.5-tts-voicedesign`)
- `user` message: description of desired voice (e.g., "warm male voice, low pitch")
- `assistant` message: text to synthesize
- `audio.voice`: "mimo_default"

### 3. Voice Clone (`voice/xiaomi/mimo-v2.5-tts-voiceclone`)
- `user` message: instruction + reference audio path
- `assistant` message: text to synthesize
- `audio.voice`: "mimo_default"
- **Note:** API parameter for reference audio not yet documented

## Usage

### Standard TTS
```powershell
& ".opencode/skills/audio-synthesize/scripts/synthesize.ps1" `
    -Text "Hello, world!" `
    -Voice "mimo_default" `
    -OutputPath "output.wav"
```

```bash
python ".opencode/skills/audio-synthesize/scripts/synthesize.py" \
    --text "Hello, world!" \
    --voice "mimo_default" \
    --output "output.wav"
```

### Voice Design
```powershell
& ".opencode/skills/audio-synthesize/scripts/synthesize.ps1" `
    -Text "Текст для озвучки" `
    -VoiceDescription "Тёплый мужской голос, низкий тембр" `
    -OutputPath "designed.wav"
```

### Voice Clone
```powershell
& ".opencode/skills/audio-synthesize/scripts/synthesize.ps1" `
    -Text "Текст для озвучки" `
    -ReferenceAudio "reference.wav" `
    -OutputPath "cloned.wav"
```

## Parameters

### Required
- `-Text` / `--text` — Text to synthesize (max 5000 chars)
- `-OutputPath` / `--output` — Output audio file path

### Optional
- `-Voice` / `--voice` — Voice name (default: "mimo_default")
- `-VoiceDescription` / `--voice-description` — Voice description for design mode
- `-ReferenceAudio` / `--reference-audio` — Reference audio for clone mode
- `-Format` / `--format` — Output format: "wav" or "mp3" (default: "wav")
- `-Model` / `--model` — TTS model override (default: auto-selected by mode)

## Environment

- **LITELLM_API_KEY** — required, bifrost-litellm API key

## Output

```
STATUS: success
MODE: standard|clone|design
MODEL: voice/xiaomi/mimo-v2.5-tts[-voiceclone|-voicedesign]
OUTPUT_PATH: path/to/output.wav
SIZE_BYTES: 12345
FORMAT: wav
USAGE: {...}
```

## Exit Codes

- 0: Success
- 2: Usage error (invalid parameters)
- 3: Gate block (validation failed, API error, missing env var)

## Gates

- Text length ≤ 5000 characters
- LITELLM_API_KEY must be set
- Reference audio must exist (for clone mode)
- Voice description ≥ 10 characters (for design mode)
