#!/usr/bin/env python3
"""
validate.py - POSIX mirror of validate.ps1

Fast LLM-free validation of every frontmatter model key against the
opencode.json provider catalog: format provider/model-key (split on FIRST
slash), existence in provider models, Did-you-mean suggestions via
Levenshtein, unused-model report. --both also validates the deploy mirror +
live<->deploy SHA256 PAIRs. STRICTLY READ-ONLY.

Usage:
    python validate.py [--agents DIR] [--both] [--config PATH]
                       [--provider P] [--suggest N] [--json]

Output:
    STATUS:/KEY:/SUGGEST:/SKIP:/UNUSED:/PAIR:/SUMMARY:/ERROR: lines

Exit codes:
    0 all keys valid (UNUSED/SKIP allowed)
    2 usage/environment error
    3 one or more invalid keys / PAIR drift / opencode.json unparsable
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


def read_raw(p):
    data = Path(p).read_bytes()
    bom = data.startswith(b'\xef\xbb\xbf')
    return data.decode('utf-8-sig' if bom else 'utf-8'), bom


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest().upper()


def get_fm_model(text):
    m = re.match(r'(?s)\A---\r?\n(.*?)\r?\n---', text)
    if not m:
        return None
    mm = re.search(r'(?m)^model:[ \t]*(.*)$', m.group(1))
    if not mm:
        return None
    return mm.group(1).strip()


def repo_root(script_dir):
    """<repo>/.opencode/skills/<skill>/scripts -> <repo>."""
    root = script_dir.resolve().parents[3]
    if (root / 'deploy-package').exists():
        return root
    try:
        out = subprocess.check_output(
            ['git', '-C', str(script_dir), 'rev-parse', '--show-toplevel'],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
        if out:
            return Path(out)
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return root


def levenshtein(a, b):
    """Single-row DP — MUST match validate.ps1 scoring (no difflib)."""
    la, lb = len(a), len(b)
    if la == 0:
        return lb
    if lb == 0:
        return la
    prev = list(range(lb + 1))
    curr = [0] * (lb + 1)
    for i in range(1, la + 1):
        curr[0] = i
        for j in range(1, lb + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            curr[j] = min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
        prev, curr = curr, prev
    return prev[lb]


def get_suggestions(bad_key, catalog, providers, n):
    """Identical scoring to validate.ps1: unknown provider -> provider-segment
    distance; known provider -> full-key distance, lower-cased, prefix bonus
    (-2, floor 0), threshold max(3, len//3); sort (dist, cand); take n."""
    slash = bad_key.find('/')
    prov_part = bad_key[:slash] if slash >= 0 else bad_key
    prov_lower = prov_part.lower()
    known_providers = [p.lower() for p in providers]
    if prov_lower not in known_providers:
        scored = []
        for cand in catalog:
            c_slash = cand.find('/')
            cat_prov = cand[:c_slash] if c_slash >= 0 else cand
            dist = levenshtein(prov_lower, cat_prov.lower())
            scored.append((dist, cand))
        scored.sort()
        return [c for _, c in scored[:n]]
    bad_lower = bad_key.lower()
    threshold = max(3, len(bad_key) // 3)
    scored = []
    for cand in catalog:
        cand_lower = cand.lower()
        dist = levenshtein(bad_lower, cand_lower)
        if cand_lower.startswith(bad_lower) or bad_lower.startswith(cand_lower):
            dist = max(0, dist - 2)
        if dist <= threshold:
            scored.append((dist, cand))
    scored.sort()
    return [c for _, c in scored[:n]]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--agents', default='')
    parser.add_argument('--both', action='store_true')
    parser.add_argument('--config', default='')
    parser.add_argument('--provider', default='')
    parser.add_argument('--suggest', type=int, default=3)
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()

    agents_dir = Path(args.agents) if args.agents else Path.home() / '.config' / 'opencode' / 'agents'
    config = Path(args.config) if args.config else Path.home() / '.config' / 'opencode' / 'opencode.json'

    if args.suggest < 1:
        print('ERROR:--suggest must be >= 1')
        sys.exit(2)

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)

    if not agents_dir.is_dir():
        print(f'ERROR:agents dir not found: {agents_dir}')
        sys.exit(2)
    if not config.is_file():
        print(f'ERROR:opencode.json not found: {config}')
        sys.exit(2)

    try:
        cfg_text, _ = read_raw(config)
        cfg = json.loads(cfg_text)
    except (ValueError, OSError) as e:
        print(f'ERROR:opencode.json invalid JSON: {e}')
        sys.exit(3)

    catalog = []
    providers = []
    for p, pv in (cfg.get('provider') or {}).items():
        providers.append(p)
        for k in ((pv or {}).get('models') or {}):
            catalog.append(f'{p}/{k}')

    if not args.json:
        print(f'STATUS:VALIDATE_START agents_dir={agents_dir} '
              f'catalog={len(providers)}/{len(catalog)}')

    keys_report = []
    unused_report = []
    pairs_report = []
    valid = invalid = suggestions = 0
    used = {}

    def check_agent_file(path):
        """Returns dict(status, reason, model, suggestions)."""
        text, _ = read_raw(path)
        m = get_fm_model(text)
        if not m:
            return {'status': 'FAIL', 'reason': 'frontmatter without model line',
                    'model': '<missing>', 'suggestions': []}
        if args.provider:
            slash = m.find('/')
            prov = m[:slash] if slash >= 0 else ''
            if prov != args.provider:
                return {'status': 'SKIP', 'reason': 'provider filter',
                        'model': m, 'suggestions': []}
        if not re.match(r'^[A-Za-z0-9._-]+/.+$', m):
            sug = get_suggestions(m, catalog, providers, args.suggest)
            return {'status': 'FAIL', 'reason': 'malformed', 'model': m,
                    'suggestions': sug}
        slash = m.find('/')
        prov = m[:slash]
        key = m[slash + 1:]
        models = (cfg.get('provider', {}).get(prov) or {}).get('models')
        exists = isinstance(models, dict) and key in models
        if exists:
            return {'status': 'PASS', 'reason': '', 'model': m, 'suggestions': []}
        sug = get_suggestions(m, catalog, providers, args.suggest)
        return {'status': 'FAIL', 'reason': 'not found', 'model': m,
                'suggestions': sug}

    def emit_key(token, r):
        nonlocal suggestions
        if r['status'] == 'PASS':
            pass
        elif r['status'] == 'FAIL' and r['suggestions']:
            suggestions += 1
        if args.json:
            return
        if r['status'] == 'SKIP':
            print(f"SKIP:{token} {r['model']} ({r['reason']})")
        else:
            model_part = ('model=<missing>'
                          if r['status'] == 'FAIL' and r['reason'] == 'frontmatter without model line'
                          else r['model'])
            reason_part = f" ({r['reason']})" if r['reason'] else ''
            print(f"KEY:{token} {model_part} -> {r['status']}{reason_part}")
        if r['suggestions']:
            print(f"SUGGEST:{token} did_you_mean={', '.join(r['suggestions'])}")

    # Live agents
    live_files = sorted(agents_dir.glob('*.md'))
    for f in live_files:
        r = check_agent_file(f)
        if r['status'] == 'PASS':
            valid += 1
            used[r['model']] = True
        elif r['status'] == 'FAIL':
            invalid += 1
        elif r['status'] == 'SKIP':
            used[r['model']] = True
        keys_report.append({'agent': f.stem, 'model': r['model'],
                            'status': r['status'], 'reason': r['reason'],
                            'suggestions': r['suggestions']})
        emit_key(f.stem, r)

    # Deploy mirrors (--both)
    if args.both:
        deploy_dir = root / 'deploy-package' / 'agents'
        if not deploy_dir.is_dir():
            print(f'ERROR:deploy agents dir not found: {deploy_dir}')
            sys.exit(2)
        deploy_files = sorted(deploy_dir.glob('*.md'))
        live_names = [f.stem for f in live_files]
        deploy_names = [f.stem for f in deploy_files]
        union = list(dict.fromkeys(live_names + deploy_names))
        for n in union:
            dp = deploy_dir / f'{n}.md'
            if dp.is_file():
                r = check_agent_file(dp)
                if r['status'] == 'PASS':
                    valid += 1
                elif r['status'] == 'FAIL':
                    invalid += 1
                keys_report.append({'agent': f'deploy/{n}', 'model': r['model'],
                                    'status': r['status'], 'reason': r['reason'],
                                    'suggestions': r['suggestions']})
                emit_key(f'deploy/{n}', r)
            lp = agents_dir / f'{n}.md'
            pair_ok = False
            pair_detail = ''
            if lp.is_file() and dp.is_file():
                h1 = sha256_file(lp)
                h2 = sha256_file(dp)
                if h1 == h2:
                    pair_ok = True
                else:
                    pair_detail = f' live={h1[:8]} deploy={h2[:8]}'
            else:
                pair_detail = ' side missing'
            if pair_ok:
                pairs_report.append({'agent': n, 'status': 'OK', 'detail': ''})
                if not args.json:
                    print(f'PAIR:{n} -> OK')
            else:
                invalid += 1
                pairs_report.append({'agent': n, 'status': 'FAIL',
                                     'detail': pair_detail.strip()})
                if not args.json:
                    print(f'PAIR:{n} -> FAIL{pair_detail}')

    # Unused models
    for key in sorted(catalog):
        if key not in used:
            unused_report.append(key)
            if not args.json:
                print(f'UNUSED:{key} agents=0')

    total_agents = len(live_files)
    if args.json:
        print(json.dumps({
            'keys': keys_report,
            'unused': unused_report,
            'pairs': pairs_report,
            'summary': {'agents': total_agents, 'valid': valid,
                        'invalid': invalid, 'unused': len(unused_report),
                        'suggestions': suggestions}}, indent=2, ensure_ascii=False))
    else:
        print(f'SUMMARY:agents={total_agents} valid={valid} invalid={invalid} '
              f'unused={len(unused_report)} suggestions={suggestions}')
        if invalid > 0:
            print(f'STATUS:FAILURES fail={invalid}')
        else:
            print('STATUS:ALL_VALID')
    sys.exit(3 if invalid > 0 else 0)


if __name__ == '__main__':
    main()
