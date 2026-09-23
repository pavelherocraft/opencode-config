#!/usr/bin/env python3
"""
discover.py — POSIX mirror of discover.ps1

Usage:
    python discover.py [--api-base-url <url>] [--config <path>] [--json]

Output:
    IN_API_NOT_CONFIG:/IN_CONFIG_NOT_API:/LIMIT_MISMATCH: lines (or JSON if --json)

Exit codes:
    0 no findings, 2 usage/environment error, 3 findings present.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


CONTEXT_FIELDS = ('max_input_tokens', 'context_length', 'context_window')
OUTPUT_FIELDS = ('max_output_tokens', 'max_tokens', 'output_tokens')


def first_int(model, fields):
    for field in fields:
        value = model.get(field)
        if value is not None:
            try:
                return int(value)
            except (TypeError, ValueError):
                continue
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--api-base-url', default='https://hcbifrost.herocraft.com/litellm/v1')
    parser.add_argument('--config', default=str(Path.home() / '.config' / 'opencode' / 'opencode.json'))
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()

    # Check API key
    api_key = os.environ.get('LITELLM_API_KEY')
    if not api_key:
        print("ERROR: LITELLM_API_KEY env var not set")
        sys.exit(2)

    # Check config
    config_path = Path(args.config)
    if not config_path.exists():
        print(f"ERROR: Config not found: {config_path}")
        sys.exit(2)

    # Fetch models from API
    api_url = f"{args.api_base_url}/models"
    req = urllib.request.Request(api_url, headers={
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json'
    })

    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            data = json.loads(response.read().decode('utf-8'))
            api_data = data.get('data', [])
    except (urllib.error.URLError, json.JSONDecodeError) as e:
        print(f"ERROR: API request failed: {e}")
        sys.exit(2)

    api_models = [m['id'] for m in api_data if m.get('id')]
    api_by_id = {m['id']: m for m in api_data if m.get('id')}

    # Read config
    with open(config_path, 'r', encoding='utf-8-sig') as f:
        config = json.load(f)

    config_model_map = config['provider']['bifrost-litellm']['models']
    config_models = list(config_model_map.keys())

    # Compare membership
    in_api_not_config = [m for m in api_models if m not in config_models]
    in_config_not_api = [m for m in config_models if m not in api_models]

    # Compare limits (only when the API exposes them)
    limit_mismatches = []
    for key in config_models:
        api_model = api_by_id.get(key)
        if api_model is None:
            continue
        cfg_model = config_model_map[key]
        cfg_limit = cfg_model.get('limit') or {}

        cfg_context = cfg_limit.get('context')
        cfg_output = cfg_limit.get('output')
        api_context = first_int(api_model, CONTEXT_FIELDS)
        api_output = first_int(api_model, OUTPUT_FIELDS)

        if api_context is not None and cfg_context is not None and int(api_context) != int(cfg_context):
            limit_mismatches.append({
                'key': key, 'limit': 'context', 'config': int(cfg_context), 'api': int(api_context)
            })
        if api_output is not None and cfg_output is not None and int(api_output) != int(cfg_output):
            limit_mismatches.append({
                'key': key, 'limit': 'output', 'config': int(cfg_output), 'api': int(api_output)
            })

    has_findings = bool(in_api_not_config or in_config_not_api or limit_mismatches)

    # Output
    if args.json:
        print(json.dumps({
            'in_api_not_config': in_api_not_config,
            'in_config_not_api': in_config_not_api,
            'limit_mismatch': limit_mismatches,
        }, indent=2))
    else:
        for model in in_api_not_config:
            print(f"IN_API_NOT_CONFIG: {model}")

        for model in in_config_not_api:
            print(f"IN_CONFIG_NOT_API: {model}")

        for m in limit_mismatches:
            print(f"LIMIT_MISMATCH: {m['key']} {m['limit']} (config={m['config']} api={m['api']})")

        if not has_findings:
            print("STATUS:OK (config matches API)")
        else:
            print(f"STATUS:FINDINGS ({len(in_api_not_config)} in API not config, "
                  f"{len(in_config_not_api)} in config not API, "
                  f"{len(limit_mismatches)} limit mismatch(es))")

    sys.exit(3 if has_findings else 0)


if __name__ == '__main__':
    main()