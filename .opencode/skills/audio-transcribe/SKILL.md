---
name: audio-transcribe
description: 'Speech-to-text transcription using MiMo-V2.5-ASR. Supports Chinese, English, dialects, code-switching, song lyrics, noisy environments, and multi-speaker conversations.'
---

# Audio Transcribe Skill

## Purpose

Transcribe audio to text using Xiaomi MiMo-V2.5-ASR model.

## API Details

- **Endpoint:** `https://hcbifrost.herocraft.com/litellm/v1/chat/completions`
- **Model:** `voice/xiaomi/mimo-v2.5-asr`
- **Auth:** `LITELLM_API_KEY` environment variable
- **Response:** `choices[0].message.content` (transcribed text)

## Capabilities

- Chinese Dialects: Wu, Cantonese, Hokkien, Sichuanese
- Code-Switch: Chinese-English code-switching (no language tags required)
- Song Recognition: lyrics transcription (Chinese and English songs)
- Noisy Environments: robust recognition (heavy noise, far-field)
- Multi-Speaker: overlapping conversations (meetings)
- Complex English Scenarios: Open ASR Leaderboard performance
- Knowledge-Intensive: poetry, terminology, names, places
- Native Punctuation: generated from prosody/semantics

## API Protocol

```json
{
  "model": "voice/xiaomi/mimo-v2.5-asr",
  "messages": [
    {"role": "user", "content": ""}
  ],
  "audio": {
    "url": "data:audio/wav;base64,<BASE64_AUDIO>",
    "format": "wav"
  }
}
```

**Optional:** Language tag in user message:
- `<chinese>` — bias for Chinese
- `<english>` — bias for English
- Empty or omit — auto-detection (recommended for code-switching)

## Usage

### PowerShell
```powershell
& ".opencode/skills/audio-transcribe/scripts/transcribe.ps1" `
    -InputPath "audio.wav" `
    -OutputPath "transcript.txt" `
    -Language "auto"
```

### Python
```bash
python ".opencode/skills/audio-transcribe/scripts/transcribe.py" \
    --input "audio.wav" \
    --output "transcript.txt" \
    --language "auto"
```

## Parameters

### Required
- `--input` / `-InputPath` — Input audio file (wav, mp3, m4a)
- `--output` / `-OutputPath` — Output text file

### Optional
- `--language` / `-Language` — Language bias: "chinese", "english", "auto" (default: "auto")

## Environment

- **LITELLM_API_KEY** — required, bifrost-litellm API key

## Output

```
STATUS: success
MODEL: voice/xiaomi/mimo-v2.5-asr
INPUT_PATH: audio.wav
OUTPUT_PATH: transcript.txt
LANGUAGE: chinese
WORD_COUNT: 123
USAGE: {...}
```

## Exit Codes

- 0: Success
- 2: Usage error (invalid parameters)
- 3: Gate block (validation failed, API error, missing env var)

## Gates

- Input audio file must exist
- LITELLM_API_KEY must be set
- Input formats: wav, mp3, m4a
