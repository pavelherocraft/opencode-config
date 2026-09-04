#!/usr/bin/env python3
"""Generate or edit an image via the Bifrost LiteLLM gateway.

Routes by model:
  - gemini/*      -> POST /chat/completions  (modalities: text+image)
  - gpt-image-*   -> POST /images/generations (or /images/edits in edit mode)
  - edit mode     -> POST /images/edits (multipart, any model)

Prints one line per saved file: SAVED: <path> (<bytes> bytes)
Stdlib only.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime
from pathlib import Path

DEFAULT_BASE_URL = "https://hcbifrost.herocraft.com/litellm/v1"
DEFAULT_MODEL = "gemini/gemini-3.1-flash-image"
DEFAULT_OUT_DIR = "./generated-images"
MAX_EDIT_INPUT_BYTES = 300 * 1024  # warn threshold, compression is ps1-side


def get_api_key() -> str:
    for name in ("LITELLM_API_KEY", "BIFROST_API_KEY", "OPENAI_API_KEY"):
        key = os.environ.get(name, "").strip()
        if key:
            return key
    print("Error: set LITELLM_API_KEY (or BIFROST_API_KEY / OPENAI_API_KEY).", file=sys.stderr)
    sys.exit(1)


def slugify(text: str, max_len: int = 40) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "_", text).strip("_").lower()
    return (slug or "image")[:max_len]


def mime_to_ext(mime: str) -> str:
    m = mime.lower()
    if "jpeg" in m or "jpg" in m:
        return "jpg"
    if "webp" in m:
        return "webp"
    return "png"


def http_json(url: str, payload: dict, api_key: str, timeout: int = 180) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(f"HTTP {e.code} {e.reason}", file=sys.stderr)
        print(body[:2000], file=sys.stderr)
        sys.exit(2)
    except urllib.error.URLError as e:
        print(f"Network error: {e.reason}", file=sys.stderr)
        sys.exit(2)


def http_multipart(url: str, fields: dict, file_field: str, file_path: Path, api_key: str, timeout: int = 180) -> dict:
    boundary = f"----imagegen{uuid.uuid4().hex}"
    body = bytearray()
    for name, value in fields.items():
        body += (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'
        ).encode("utf-8")
    body += (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode("utf-8")
    body += file_path.read_bytes()
    body += f"\r\n--{boundary}--\r\n".encode("utf-8")
    req = urllib.request.Request(
        url,
        data=bytes(body),
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} {e.reason}", file=sys.stderr)
        print(e.read().decode("utf-8", errors="replace")[:2000], file=sys.stderr)
        sys.exit(2)
    except urllib.error.URLError as e:
        print(f"Network error: {e.reason}", file=sys.stderr)
        sys.exit(2)


def generate_gemini(prompt: str, model: str, base_url: str, api_key: str) -> list[tuple[bytes, str]]:
    data = http_json(
        f"{base_url.rstrip('/')}/chat/completions",
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "modalities": ["text", "image"],
        },
        api_key,
    )
    images: list[tuple[bytes, str]] = []
    for choice in data.get("choices", []):
        msg = choice.get("message") or {}
        for img in msg.get("images") or []:
            url = (img.get("image_url") or {}).get("url") or ""
            if url.startswith("data:"):
                header, _, b64 = url.partition(",")
                mime = header[len("data:"):].split(";", 1)[0] or "image/png"
                try:
                    images.append((base64.b64decode(b64), mime_to_ext(mime)))
                except Exception:
                    continue
    return images


def generate_openai_style(prompt: str, model: str, base_url: str, api_key: str, size: str) -> list[tuple[bytes, str]]:
    data = http_json(
        f"{base_url.rstrip('/')}/images/generations",
        {"model": model, "prompt": prompt, "size": size, "n": 1},
        api_key,
    )
    images: list[tuple[bytes, str]] = []
    for item in data.get("data", []):
        b64 = item.get("b64_json")
        if b64:
            images.append((base64.b64decode(b64), "png"))
    return images


def edit_any(prompt: str, model: str, base_url: str, api_key: str, input_path: Path, size: str) -> list[tuple[bytes, str]]:
    if input_path.stat().st_size > MAX_EDIT_INPUT_BYTES:
        print(
            f"Warning: input is {input_path.stat().st_size} bytes (> {MAX_EDIT_INPUT_BYTES}). "
            "Consider generate.ps1 which auto-compresses, or a smaller source.",
            file=sys.stderr,
        )
    data = http_multipart(
        f"{base_url.rstrip('/')}/images/edits",
        {"prompt": prompt, "model": model, "n": "1", "size": size},
        "image",
        input_path,
        api_key,
    )
    images: list[tuple[bytes, str]] = []
    for item in data.get("data", []):
        b64 = item.get("b64_json")
        if b64:
            images.append((base64.b64decode(b64), "png"))
    return images


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate/edit an image via Bifrost LiteLLM.")
    parser.add_argument("prompt", help="Image prompt / edit instruction")
    parser.add_argument("--model", default=os.environ.get("BIFROST_IMAGE_MODEL", DEFAULT_MODEL),
                        help=f"Model (default: {DEFAULT_MODEL}; env: BIFROST_IMAGE_MODEL)")
    parser.add_argument("--base-url", default=os.environ.get("BIFROST_BASE_URL", DEFAULT_BASE_URL),
                        help=f"Gateway base URL (default: {DEFAULT_BASE_URL}; env: BIFROST_BASE_URL)")
    parser.add_argument("--mode", choices=["generate", "edit"], default="generate",
                        help="generate (default) or edit")
    parser.add_argument("--input", default=None,
                        help="Source image path for edit mode (pass PATH, never paste bytes)")
    parser.add_argument("--out", default=DEFAULT_OUT_DIR,
                        help=f"Output directory (default: {DEFAULT_OUT_DIR})")
    parser.add_argument("--name", default=None, help="Filename slug (default: derived from prompt)")
    parser.add_argument("--size", default="1024x1024", help="OpenAI-style size (default: 1024x1024)")
    args = parser.parse_args()

    api_key = get_api_key()
    out_dir = Path(args.out).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.mode == "edit":
        if not args.input:
            print("Error: --mode edit requires --input <path-to-image>", file=sys.stderr)
            sys.exit(1)
        input_path = Path(args.input).expanduser()
        if not input_path.is_file():
            print(f"Error: input not found: {input_path}", file=sys.stderr)
            sys.exit(1)
        images = edit_any(args.prompt, args.model, args.base_url, api_key, input_path, args.size)
    elif args.model.startswith("gpt-image") or "dall-e" in args.model:
        images = generate_openai_style(args.prompt, args.model, args.base_url, api_key, args.size)
    else:
        images = generate_gemini(args.prompt, args.model, args.base_url, api_key)

    if not images:
        print("Error: no image in response (refusal or safety block).", file=sys.stderr)
        sys.exit(3)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    slug = args.name or slugify(args.prompt)
    for idx, (raw, ext) in enumerate(images):
        suffix = "" if len(images) == 1 else f"_{idx + 1}"
        out_path = out_dir / f"{timestamp}_{slug}{suffix}.{ext}"
        out_path.write_bytes(raw)
        print(f"SAVED: {out_path} ({len(raw)} bytes)")


if __name__ == "__main__":
    main()
