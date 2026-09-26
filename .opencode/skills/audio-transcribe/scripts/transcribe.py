#!/usr/bin/env python3
"""MiMo-V2.5-ASR Transcription Script — real API integration"""

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
    parser = argparse.ArgumentParser(description="MiMo-V2.5-ASR Transcription")
    parser.add_argument("--input", required=True, help="Input audio file")
    parser.add_argument("--output", required=True, help="Output text file")
    parser.add_argument("--language", default="auto", choices=["chinese", "english", "auto"], help="Language bias (default: auto-detection)")
    
    args = parser.parse_args()
    
    # Validation
    if not os.path.exists(args.input):
        print(f"ERROR: Input file not found: {args.input}")
        sys.exit(3)

    # Validate input format
    ext = os.path.splitext(args.input)[1].lower()
    if ext not in [".wav", ".mp3", ".m4a"]:
        print(f"ERROR: Unsupported input format: {ext}")
        print("Supported formats: wav, mp3, m4a")
        sys.exit(3)

    if not os.environ.get("LITELLM_API_KEY"):
        print("ERROR: LITELLM_API_KEY environment variable not set")
        sys.exit(3)
    
    # Read audio file
    with open(args.input, "rb") as f:
        audio_bytes = f.read()
    
    # Determine MIME type
    mime_type = {
        ".wav": "audio/wav",
        ".mp3": "audio/mpeg",
        ".m4a": "audio/mp4",
    }.get(ext, "audio/wav")
    
    audio_base64 = base64.b64encode(audio_bytes).decode("utf-8")
    
    # Build messages
    if args.language == "auto":
        user_content = ""
    else:
        user_content = f"<{args.language}>"
    
    messages = [
        {"role": "user", "content": user_content},
    ]
    
    # Build request body
    body = {
        "model": "voice/xiaomi/mimo-v2.5-asr",
        "messages": messages,
        "audio": {
            "url": f"data:{mime_type};base64,{audio_base64}",
            "format": ext[1:],  # Remove leading dot
        },
    }
    
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
    
    # Extract transcription
    try:
        result = resp.json()
        transcription = result["choices"][0]["message"]["content"]
    except (KeyError, ValueError) as e:
        print(f"ERROR: Failed to parse API response: {e}")
        print(f"Response: {resp.text[:500]}")
        sys.exit(3)
    
    # Ensure output directory exists
    output_dir = os.path.dirname(args.output)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    
    # Save output
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(transcription)
    
    # Output
    usage = result.get("usage", {})
    print(f"STATUS: success")
    print("MODEL: voice/xiaomi/mimo-v2.5-asr")
    print(f"INPUT_PATH: {args.input}")
    print(f"OUTPUT_PATH: {args.output}")
    print(f"LANGUAGE: {args.language}")
    print(f"WORD_COUNT: {len(transcription.split())}")
    print(f"USAGE: {json.dumps(usage)}")
    
    sys.exit(0)

if __name__ == "__main__":
    main()
