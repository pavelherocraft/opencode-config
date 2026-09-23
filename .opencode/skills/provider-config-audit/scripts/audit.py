#!/usr/bin/env python3
"""
audit.py — POSIX mirror of audit.ps1

Usage:
    python audit.py [--config <path>] [--provider <name>] [--json]

Output:
    SEVERITY:/FINDING:/LOCATION: lines (or JSON if --json)

Exit codes:
    0 no findings (or nit-only), 2 usage/environment error,
    3 findings at concern/blocker severity.
"""

import argparse
import json
import sys
from pathlib import Path


def find_duplicate_keys(text):
    """Raw-text JSON scan; json.load silently keeps the last duplicate."""
    dups = []
    stack = []  # frames: {'name': str|None, 'keys': set}
    i, n = 0, len(text)
    pending_key = None

    while i < n:
        c = text[i]

        if c == '"':
            sb = []
            i += 1
            while i < n:
                ch = text[i]
                if ch == '\\':
                    sb.append(ch)
                    i += 1
                    if i < n:
                        sb.append(text[i])
                        i += 1
                    continue
                if ch == '"':
                    break
                sb.append(ch)
                i += 1
            s = ''.join(sb)

            # A string followed by ':' is an object key.
            j = i + 1
            while j < n and text[j].isspace():
                j += 1
            if j < n and text[j] == ':' and stack:
                frame = stack[-1]
                if s in frame['keys']:
                    names = [f['name'] for f in stack if f['name']]
                    path = '.'.join(names) if names else '<root>'
                    dups.append({'name': s, 'path': path})
                else:
                    frame['keys'].add(s)
                pending_key = s
            i += 1
            continue

        if c == '{':
            stack.append({'name': pending_key, 'keys': set()})
            pending_key = None
            i += 1
            continue

        if c == '}':
            if stack:
                stack.pop()
            pending_key = None
            i += 1
            continue

        i += 1

    return dups


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default=str(Path.home() / '.config' / 'opencode' / 'opencode.json'))
    parser.add_argument('--provider', default='bifrost-litellm')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.exists():
        print(f"ERROR: Config not found: {config_path}")
        sys.exit(2)

    raw = config_path.read_text(encoding='utf-8-sig')

    # Invalid JSON is a blocker finding (documented), not an unhandled exception.
    try:
        config = json.loads(raw)
    except json.JSONDecodeError as e:
        finding = {
            'severity': 'blocker',
            'finding': f'invalid JSON: {e}',
            'location': str(config_path),
        }
        if args.json:
            print(json.dumps([finding], indent=2))
        else:
            print(f"BLOCKER:{finding['finding']}:{finding['location']}")
            print("STATUS:FINDINGS (1 total)")
        sys.exit(3)

    if args.provider not in config.get('provider', {}):
        print(f"ERROR: Provider {args.provider} not found")
        sys.exit(2)

    models = config['provider'][args.provider]['models']
    findings = []

    # Check 1: duplicate keys (raw-text scan; json.load deduplicates)
    for dup in find_duplicate_keys(raw):
        findings.append({
            'severity': 'concern',
            'finding': f"duplicate key: {dup['name']}",
            'location': dup['path'],
        })

    # Check 2: per-model validation
    valid_inputs = {'text', 'image', 'audio', 'video'}
    valid_efforts = {'low', 'medium', 'high', 'max'}

    for key, model in models.items():
        # Check limit
        if 'limit' not in model:
            findings.append({
                'severity': 'blocker',
                'finding': 'missing limit',
                'location': key,
            })
            continue

        context = model['limit'].get('context')
        output = model['limit'].get('output')

        if context is not None and context < 0:
            findings.append({
                'severity': 'concern',
                'finding': 'invalid limit.context (< 0)',
                'location': key,
            })

        if output is not None and output < 0:
            findings.append({
                'severity': 'concern',
                'finding': 'invalid limit.output (< 0)',
                'location': key,
            })

        # context=0 is non-conventional except for placeholder models -> nit
        if context == 0 and 'placeholder' not in key.lower():
            findings.append({
                'severity': 'nit',
                'finding': 'non-conventional limit.context=0',
                'location': key,
            })

        # Check modalities
        if 'modalities' in model:
            if 'input' in model['modalities']:
                for inp in model['modalities']['input']:
                    if inp not in valid_inputs:
                        findings.append({
                            'severity': 'concern',
                            'finding': f'invalid modalities.input value: {inp}',
                            'location': key,
                        })

            if 'output' in model['modalities']:
                for out in model['modalities']['output']:
                    if out not in valid_inputs:
                        findings.append({
                            'severity': 'concern',
                            'finding': f'invalid modalities.output value: {out}',
                            'location': key,
                        })

        # Check options.reasoningEffort
        if 'options' in model and 'reasoningEffort' in model['options']:
            if model['options']['reasoningEffort'] not in valid_efforts:
                findings.append({
                    'severity': 'concern',
                    'finding': f"invalid options.reasoningEffort: {model['options']['reasoningEffort']}",
                    'location': key,
                })

        # Check options.thinking (legacy)
        if 'options' in model and 'thinking' in model['options']:
            findings.append({
                'severity': 'nit',
                'finding': 'legacy options.thinking (migrate to reasoningEffort+variants)',
                'location': key,
            })

        # Check variants
        if 'variants' in model:
            for variant_key, variant in model['variants'].items():
                if 'reasoningEffort' not in variant:
                    findings.append({
                        'severity': 'concern',
                        'finding': f'variant {variant_key} missing reasoningEffort',
                        'location': key,
                    })

        # Check attachment
        if 'attachment' in model:
            if not isinstance(model['attachment'], bool):
                findings.append({
                    'severity': 'concern',
                    'finding': 'attachment is not boolean',
                    'location': key,
                })

    # Output
    if args.json:
        print(json.dumps(findings, indent=2))
    else:
        for finding in findings:
            print(f"{finding['severity'].upper()}:{finding['finding']}:{finding['location']}")

        if len(findings) == 0:
            print("STATUS:OK (no findings)")
        else:
            print(f"STATUS:FINDINGS ({len(findings)} total)")

    # Exit 3 when any concern/blocker finding exists (nit-only stays 0).
    if any(f['severity'] != 'nit' for f in findings):
        sys.exit(3)
    sys.exit(0)


if __name__ == '__main__':
    main()