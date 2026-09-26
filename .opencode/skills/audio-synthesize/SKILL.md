---
name: audio-synthesize
description: 'Text-to-speech synthesis using MiMo-V2.5-TTS models. Supports standard TTS (built-in voices), voice cloning (from reference audio), and voice design (from text description). Generates MP3 output.'
---

# Audio Synthesize Skill

## Purpose

Synthesize speech from text using Xiaomi MiMo-V2.5-TTS models.

## Modes

1. **Standard TTS** — Use built-in voices with fine-grained control
2. **Voice Clone** — Clone voice from reference audio samples
3. **Voice Design** — Create new voice from text description

## Usage

### Standard TTS
```powershell
& "$env:USERPROFILE\.config\opencode\skills\audio-synthesize\scripts\synthesize.ps1" `
    -Text "Hello, world!" `
    -Voice "alloy" `
    -Model "voice/xiaomi/mimo-v2.5-tts" `
    -Speed 1.0 `
    -OutputPath "output.mp3"
```

### Voice Clone
```powershell
& "$env:USERPROFILE\.config\opencode\skills\audio-synthesize\scripts\synthesize.ps1" `
    -Text "Text to synthesize" `
    -ReferenceAudio "reference_voice.wav" `
    -Model "voice/xiaomi/mimo-v2.5-tts-voiceclone" `
    -OutputPath "cloned_voice.mp3"
```

### Voice Design
```powershell
& "$env:USERPROFILE\.config\opencode\skills\audio-synthesize\scripts\synthesize.ps1" `
    -Text "Text to synthesize" `
    -VoiceDescription "warm male voice, low pitch, calm tone" `
    -Model "voice/xiaomi/mimo-v2.5-tts-voicedesign" `
    -OutputPath "designed_voice.mp3"
```

## Parameters

### Required
- `-Text` — Text to synthesize (max 5000 chars)
- `-OutputPath` — Output MP3 file path

### Mode-specific
**Standard TTS:**
- `-Voice` — Voice name (default: "alloy")
- `-Speed` — Speed multiplier 0.5-2.0 (default: 1.0)

**Voice Clone:**
- `-ReferenceAudio` — Path to reference audio file (min 10 seconds)

**Voice Design:**
- `-VoiceDescription` — Text description of desired voice (min 10 chars)

### Common
- `-Model` — Model name (auto-detected from mode)

## Models

| Model ID | Mode |
|----------|------|
| `voice/xiaomi/mimo-v2.5-tts` | Standard TTS (default) |
| `voice/xiaomi/mimo-v2.5-tts-voiceclone` | Voice Clone |
| `voice/xiaomi/mimo-v2.5-tts-voicedesign` | Voice Design |

## Output

- STATUS: success|error
- OUTPUT_PATH: path to generated MP3
- DURATION: duration in seconds
- MODEL: model used

## Gates

- Text length ≤ 5000 characters
- Reference audio ≥ 10 seconds (for clone mode)
- Voice description ≥ 10 characters (for design mode)
- Output directory exists and is writable

## Exit Codes

- 0: Success
- 2: Usage error (invalid parameters)
- 3: Gate block (validation failed)
