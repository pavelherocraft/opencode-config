---
name: image-gen
description: 'Internal image generation and editing toolkit for the generate-image / generate-image-gpt agents. Runs Bifrost LiteLLM gateway scripts (generate.ps1 / generate.py) with model routing (gemini/gemini-3.1-flash-image default, gemini/gemini-3-pro-image, gpt-image-2), generate + edit modes, saves to disk, prints "SAVED: <path> (<bytes> bytes)" only — never inline base64. Hidden from all other agents by skill permissions.'
---

# Image Generation & Editing (via Bifrost LiteLLM)

Internal toolkit loaded by the `generate-image` / `generate-image-gpt`
subagents as their default path. Not advertised to primary sessions.

## When to use

- User asks to generate/draw/create an image (any gateway model acceptable)
- User asks to edit/modify/restyle an existing image file
- User mentions: gemini, nano banana, gpt image, dall-e, bifrost image

## When NOT to use

- Task is analysis/description of an existing image (use the view-image subagent)
- User explicitly wants another backend (Midjourney, SD, Imagen via Vertex)

## Context safety rules (CRITICAL)

Violating these poisons the session history with megabytes of base64, causing
HTTP 413 "Request Entity Too Large" and endless auto-compaction loops.

1. **NEVER `read` a generated/saved image file.** The read tool returns the
   image as an inline base64 file-part that is re-sent on every subsequent
   request.
2. **NEVER embed `data:image/...;base64,...` in any reply or tool output.**
3. Report results as **file paths only**.
4. Verify results without loading bytes into context:
   - file size + pixel dimensions via PowerShell `System.Drawing`, or
   - delegate visual checks to the `view-image` subagent (isolated context)
5. For edits, pass the source image **by path** (`--input` / `-InputPath`),
   never paste its content into the prompt or chat.
6. Do not paste/drag the generated image back into the conversation to ask
   for changes — reference its path instead.

## Models

| Model | Endpoint | Notes |
|-------|----------|-------|
| `gemini/gemini-3.1-flash-image` | chat/completions + modalities | **Default.** Fast. |
| `gemini/gemini-3-pro-image` | chat/completions + modalities | Higher quality, slower. |
| `gpt-image-2` | images/generations / images/edits | Explicit GPT/DALL-E requests only. |

## Usage

Python (cross-platform, stdlib only):

```bash
# generate (gemini default)
python ~/.config/opencode/skills/image-gen/scripts/generate.py "a fox in a spacesuit, watercolor"

# generate with gpt-image-2
python ~/.config/opencode/skills/image-gen/scripts/generate.py "a fox in a spacesuit" --model gpt-image-2

# edit an existing image (pass path, not bytes)
python ~/.config/opencode/skills/image-gen/scripts/generate.py "make the sky sunset-colored" --mode edit --input ./generated-images/fox_001.png

# custom output dir / name
python .../generate.py "prompt" --out ./src/assets --name hero_bg
```

PowerShell (Windows-native):

```powershell
& "$env:USERPROFILE\.config\opencode\skills\image-gen\scripts\generate.ps1" -Prompt "a fox in a spacesuit, watercolor"
& ".../generate.ps1" -Prompt "sunset sky" -Mode edit -InputPath ".\generated-images\fox_001.png"
& ".../generate.ps1" -Prompt "prompt" -Model gpt-image-2 -OutDir ".\src\assets"
```

Both scripts print exactly one line per saved file: `SAVED: <path> (<bytes> bytes)`.

## Defaults

- **Model:** `gemini/gemini-3.1-flash-image` (env override: `BIFROST_IMAGE_MODEL`)
- **Base URL:** `https://hcbifrost.herocraft.com/litellm/v1` (env override: `BIFROST_BASE_URL`)
- **Output dir:** `./generated-images/` (project-local; create if missing)
- **Aspect:** model default; append "aspect ratio 16:9" etc. to the prompt
- **API key:** `LITELLM_API_KEY` (fallbacks: `BIFROST_API_KEY`, `OPENAI_API_KEY`)

## Post-generation checklist

1. Report the saved path(s) to the user — nothing else.
2. If the project uses git, suggest adding `generated-images/` to `.gitignore`
   (only suggest; do not edit `.gitignore` unasked).
3. If the user asks how it looks — call the `view-image` subagent with the
   path, do NOT read the image yourself.

## Overrides

| Hint in request | Effect |
|------|--------|
| `model=gpt-image-2` / "use gpt" / "dall-e" | Switch to gpt-image-2 |
| `model=gemini/gemini-3-pro-image` / "pro quality" | Switch to Gemini Pro |
| `out=<dir>` | Change output directory |
| `aspect 16:9` / `vertical` / `horizontal` | Append aspect hint to prompt |

## Troubleshooting

- **No image, only text** — model refused (people/brands/NSFW); rewrite prompt.
- **401** — `LITELLM_API_KEY` missing/expired.
- **404 model not found** — check `GET /models` listing.
- **429 RESOURCE_EXHAUSTED** — gateway quota; wait and retry.
- **413 Request Entity Too Large** — request body too large for the gateway;
  for edits lower `--max-input-size-kb` (default 300) so the source image is
  compressed harder.
- **Edit mode: source not found** — verify the `--input` path exists.

## Safety

- Do not log or print the API key.
- Refuse CSAM, real-person defamation, copyrighted character clones; explain why.
