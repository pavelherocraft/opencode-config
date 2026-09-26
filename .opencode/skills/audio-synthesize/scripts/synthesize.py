#!/usr/bin/env python3
"""MiMo-V2.5-TTS Synthesis Script — real API integration"""

import argparse
import base64
import json
import os
import sys

try:
    import requests
except ImportError:
    print("ERROR: 'requests' module not found. Install: pip install requests")
    sys.exit(3)

BASE_URL = "https://hcbifrost.herocraft.com/litellm/v1"

def main():
    parser = argparse.ArgumentParser(description="MiMo-V2.5-TTS Synthesis")
    parser.add_argument("--text", required=True, help="Text to synthesize")
    parser.add_argument("--output", required=True, help="Output audio path")
    parser.add_argument("--voice", default="mimo_default", help="Voice name (standard mode)")
    parser.add_argument("--voice-description", default=None, help="Voice description (design mode)")
    parser.add_argument("--reference-audio", default=None, help="Reference audio for clone mode")
    parser.add_argument("--format", default="wav", choices=["wav", "mp3"], help="Output format")
    parser.add_argument("--model", default=None, help="TTS model override (default: auto-select by mode)")
    
    args = parser.parse_args()
    
    # Validation
    if len(args.text) > 5000:
        print("ERROR: Text exceeds 5000 character limit")
        sys.exit(3)
    
    if not os.environ.get("LITELLM_API_KEY"):
        print("ERROR: LITELLM_API_KEY environment variable not set")
        sys.exit(3)
    
    # Determine mode and model
    if args.reference_audio:
        mode = "clone"
        if not os.path.exists(args.reference_audio):
            print(f"ERROR: Reference audio not found: {args.reference_audio}")
            sys.exit(3)
        model = args.model or "voice/xiaomi/mimo-v2.5-tts-voiceclone"
    elif args.voice_description:
        mode = "design"
        if len(args.voice_description) < 10:
            print("ERROR: Voice description must be at least 10 characters")
            sys.exit(3)
        model = args.model or "voice/xiaomi/mimo-v2.5-tts-voicedesign"
    else:
        mode = "standard"
        model = args.model or "voice/xiaomi/mimo-v2.5-tts"

    # Validate reference audio format for clone mode
    if mode == "clone":
        ext = os.path.splitext(args.reference_audio)[1].lower()
        if ext != ".wav":
            print(f"ERROR: Voice clone requires WAV format. Got: {ext}")
            print("Convert m4a/mp3 to WAV first (e.g., using ffmpeg)")
            sys.exit(3)

        # Check file size
        file_size = os.path.getsize(args.reference_audio)
        if file_size > 10 * 1024 * 1024:  # 10MB
            print(f"ERROR: Reference audio too large ({file_size / 1024 / 1024:.1f}MB)")
            print("Maximum size: 10MB")
            sys.exit(3)
    
    # Build messages based on mode
    if mode == "design":
        messages = [
            {"role": "user", "content": args.voice_description},
            {"role": "assistant", "content": args.text},
        ]
    elif mode == "clone":
        with open(args.reference_audio, "rb") as f:
            audio_bytes = f.read()
        audio_base64 = base64.b64encode(audio_bytes).decode("utf-8")

        ext = os.path.splitext(args.reference_audio)[1].lower()
        mime_type = "audio/wav" if ext == ".wav" else "audio/mp4" if ext == ".m4a" else "audio/mpeg" if ext == ".mp3" else "audio/wav"

        messages = [
            {"role": "user", "content": ""},
            {"role": "assistant", "content": args.text},
        ]

        audio_field = {
            "voice": f"data:{mime_type};base64,{audio_base64}",
            "format": args.format,
        }
    else:
        messages = [
            {"role": "assistant", "content": args.text},
        ]
        
        audio_field = {
            "voice": args.voice,
            "format": args.format,
        }
    
    # Build request body
    if mode == "design":
        # design mode does NOT support audio.voice
        body = {
            "model": model,
            "messages": messages,
            "audio": {"format": args.format},
        }
    else:
        body = {
            "model": model,
            "messages": messages,
            "audio": audio_field,
        }
    
    # Ensure output directory exists
    output_dir = os.path.dirname(args.output)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    
    # Make API call
    try:
        resp = requests.post(
            f"{BASE_URL}/chat/completions",
            headers={
                "Authorization": f"Bearer {os.environ['LITELLM_API_KEY']}",
                "Content-Type": "application/json",
            },
            json=body,
            timeout=180,
        )
        resp.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"ERROR: API request failed: {e}")
        sys.exit(3)
    
    # Extract audio
    try:
        result = resp.json()
        audio = result["choices"][0]["message"]["audio"]
        raw = base64.b64decode(audio["data"])
    except (KeyError, ValueError) as e:
        print(f"ERROR: Failed to parse API response: {e}")
        print(f"Response: {resp.text[:500]}")
        sys.exit(3)
    
    # Save audio
    with open(args.output, "wb") as f:
        f.write(raw)
    
    # Output
    usage = result.get("usage", {})
    print(f"STATUS: success")
    print(f"MODE: {mode}")
    print(f"MODEL: {model}")
    print(f"OUTPUT_PATH: {args.output}")
    print(f"SIZE_BYTES: {len(raw)}")
    print(f"FORMAT: {args.format}")
    print(f"USAGE: {json.dumps(usage)}")
    
    sys.exit(0)

if __name__ == "__main__":
    main()
