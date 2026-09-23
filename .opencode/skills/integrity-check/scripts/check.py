#!/usr/bin/env python3
"""
check.py - POSIX mirror of check.ps1

Fast LLM-free integrity check of the agent orchestration config:
SHA256 agent pairs, counters, frontmatter model key format/existence.

Usage:
    python check.py [--json] [--expected-agents 37] [--expected-models 10]
                    [--expected-orch 25] [--expected-plan 10]
                    [--config <path>]

Output:
    STATUS:/COUNT:/PAIR:/FORMAT:/EXISTS:/JSON:/WARN:/SUMMARY:/ERROR: lines

Exit codes:
    0 all pass (WARNs allowed)
    2 usage/environment error
    3 one or more FAIL findings

Strictly read-only.
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


def read_raw(p):
    """Byte-safe read: decode UTF-8 (strip BOM if present), report BOM state."""
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


def count_task_allow(cfg, primary):
    try:
        task = cfg['agent'][primary]['permission']['task']
    except (KeyError, TypeError):
        return None
    return sum(1 for k, v in task.items() if k != '*' and v == 'allow')


def count_routing_plugin(ts_text, primary):
    outer = re.search(r'const ROUTING_TABLES = \{(.*?)\r?\n\}', ts_text, re.S)
    if not outer:
        return None
    inner = re.search(re.escape(primary) + r'\s*:\s*\[(.*?)\]', outer.group(1), re.S)
    if not inner:
        return None
    return len(re.findall(r'"[^"]+"', inner.group(1)))


def get_whitelist_count(arch_text, primary):
    m = re.search(r'^### ' + re.escape(primary) + r' Whitelist \((\d+) agents\)',
                  arch_text, re.M)
    if not m:
        return None
    header = int(m.group(1))
    after = arch_text[m.end():]
    fp = re.search(r'(?m)^\|', after)
    if not fp:
        return {'header': header, 'rows': -1}
    rest = after[fp.start():]
    blank = re.search(r'\r?\n[ \t]*\r?\n', rest)
    tbl = rest[:blank.start()] if blank else rest
    rows = len(re.findall(r'(?m)^\|\s*\d+\s*\|', tbl))
    return {'header': header, 'rows': rows}


def distribution_rows(text):
    lines = re.split(r'\r\n|\r|\n', text)
    start = -1
    for i, line in enumerate(lines):
        if re.match(r'^### Models Distribution\s*$', line):
            start = i
            break
    if start < 0:
        return None
    count = 0
    for i in range(start + 1, len(lines)):
        if re.match(r'^### ', lines[i]):
            break
        if re.match(r'^\|\s*`', lines[i]):
            count += 1
    return count


def summary_models_count(text):
    m = re.search(r'(?m)^\| Models \| (\d+) \| bifrost-litellm \(', text)
    if not m:
        return None
    return int(m.group(1))


class Report:
    def __init__(self, as_json):
        self.checks = []
        self.pass_n = 0
        self.fail_n = 0
        self.warn_n = 0
        self.as_json = as_json

    def add(self, cid, target, status, detail=''):
        self.checks.append({'id': cid, 'target': target, 'status': status, 'detail': detail})
        if status == 'PASS':
            self.pass_n += 1
        elif status == 'FAIL':
            self.fail_n += 1
        else:
            self.warn_n += 1
        if not self.as_json:
            display = status
            if cid == 'PAIR' and status == 'PASS':
                display = 'OK'
            payload = target
            if detail:
                payload = f'{target} {detail}' if target else detail
            print(f'{cid}:{payload} -> {display}')


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-agents', type=int, default=37)
    parser.add_argument('--expected-models', type=int, default=10)
    parser.add_argument('--expected-orch', type=int, default=25)
    parser.add_argument('--expected-plan', type=int, default=10)
    parser.add_argument('--config', default='')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()

    config = Path(args.config) if args.config else Path.home() / '.config' / 'opencode' / 'opencode.json'

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)

    live_dir = Path.home() / '.config' / 'opencode'
    live_agents_dir = live_dir / 'agents'
    deploy_root = root / 'deploy-package'
    deploy_agents_dir = deploy_root / 'agents'

    if not live_agents_dir.is_dir():
        print(f'ERROR: live agents dir not found: {live_agents_dir}')
        sys.exit(2)
    if not deploy_root.is_dir():
        print(f'ERROR: deploy-package not found: {deploy_root}')
        sys.exit(2)
    if not config.is_file():
        print(f'ERROR: opencode.json not found: {config}')
        sys.exit(2)

    rep = Report(args.json)
    if not args.json:
        print('STATUS:CHECK_START')

    # 1. opencode.json validity
    cfg = None
    json_ok = True
    try:
        text, _ = read_raw(config)
        cfg = json.loads(text)
    except (ValueError, OSError):
        json_ok = False
    rep.add('JSON', 'opencode.json', 'PASS' if json_ok else 'FAIL',
            'parse ok' if json_ok else 'invalid JSON')

    # 2. Agent counts + name sets
    live_files = sorted(live_agents_dir.glob('*.md'))
    deploy_files = sorted(deploy_agents_dir.glob('*.md'))
    live_names = [f.stem for f in live_files]
    deploy_names = [f.stem for f in deploy_files]
    extra_live = [n for n in live_names if n not in deploy_names]
    extra_deploy = [n for n in deploy_names if n not in live_names]
    names_equal = not extra_live and not extra_deploy
    detail = (f'agents_live={len(live_files)} agents_deploy={len(deploy_files)} '
              f'expected={args.expected_agents}')
    if not names_equal:
        detail += f" live_only=[{','.join(extra_live)}] deploy_only=[{','.join(extra_deploy)}]"
    count_ok = (len(live_files) == args.expected_agents
                and len(deploy_files) == args.expected_agents
                and names_equal)
    rep.add('COUNT', '', 'PASS' if count_ok else 'FAIL', detail)

    # 3. Pairs (agents + opencode.json)
    union = list(dict.fromkeys(live_names + deploy_names))
    for n in union:
        lp = live_agents_dir / f'{n}.md'
        dp = deploy_agents_dir / f'{n}.md'
        if lp.is_file() and dp.is_file():
            h1 = sha256_file(lp)
            h2 = sha256_file(dp)
            if h1 == h2:
                rep.add('PAIR', n, 'PASS')
            else:
                rep.add('PAIR', n, 'FAIL', f'live={h1[:8]} deploy={h2[:8]}')
        else:
            rep.add('PAIR', n, 'FAIL', 'side missing')
    deploy_cfg = deploy_root / 'opencode.json'
    if deploy_cfg.is_file():
        hc1 = sha256_file(config)
        hc2 = sha256_file(deploy_cfg)
        if hc1 == hc2:
            rep.add('PAIR', 'opencode.json', 'PASS')
        else:
            rep.add('PAIR', 'opencode.json', 'FAIL', f'live={hc1[:8]} deploy={hc2[:8]}')
    else:
        rep.add('PAIR', 'opencode.json', 'FAIL', 'deploy copy missing')

    # 4. FORMAT / EXISTS per live agent
    models_used = {}
    for f in live_files:
        name = f.stem
        text, _ = read_raw(f)
        m = get_fm_model(text)
        if not m:
            rep.add('FORMAT', name, 'FAIL', 'model=<missing> frontmatter without model line')
            continue
        models_used[m] = True
        fmt_ok = re.match(r'^[A-Za-z0-9._-]+/.+$', m) is not None
        rep.add('FORMAT', name, 'PASS' if fmt_ok else 'FAIL', f'model={m}')
        if json_ok:
            exists = False
            if fmt_ok and cfg is not None:
                slash = m.find('/')
                prov = m[:slash]
                key = m[slash + 1:]
                models = (cfg.get('provider', {}).get(prov) or {}).get('models')
                if isinstance(models, dict):
                    exists = key in models
            rep.add('EXISTS', name, 'PASS' if exists else 'FAIL', m)
    if not json_ok:
        rep.add('EXISTS', '', 'WARN', 'checks skipped (opencode.json parse failed)')

    # 5. Models-in-use counter
    mu_ok = len(models_used) == args.expected_models
    rep.add('COUNT', '', 'PASS' if mu_ok else 'FAIL',
            f'models_used={len(models_used)} expected={args.expected_models}')

    # 6. MCP_SETUP.md cross-checks
    mcp_path = root / 'MCP_SETUP.md'
    if mcp_path.is_file():
        mcp_text, _ = read_raw(mcp_path)
        dist = distribution_rows(mcp_text)
        if dist is not None:
            rep.add('COUNT', '', 'PASS' if dist == args.expected_models else 'FAIL',
                    f'mcp_distribution rows={dist} expected={args.expected_models}')
        else:
            rep.add('COUNT', '', 'FAIL',
                    'mcp_distribution anchor not found (### Models Distribution)')
        sc = summary_models_count(mcp_text)
        if sc is not None:
            rep.add('COUNT', '', 'PASS' if sc == args.expected_models else 'FAIL',
                    f'mcp_summary_models count={sc} expected={args.expected_models}')
        else:
            rep.add('COUNT', '', 'FAIL',
                    'mcp_summary_models anchor not found (| Models | N | bifrost-litellm ()')
    else:
        rep.add('COUNT', '', 'FAIL', 'MCP_SETUP.md not found')

    # 7. Routing counters (3 sources)
    arch_text = None
    arch_path = root / 'ARCHITECTURE.md'
    if arch_path.is_file():
        arch_text, _ = read_raw(arch_path)
    ts_text = None
    ts_path = live_dir / 'plugins' / 'workflow-enforcement.ts'
    if ts_path.is_file():
        ts_text, _ = read_raw(ts_path)

    for primary, exp in (('orchestrator', args.expected_orch),
                         ('plankestrator', args.expected_plan)):
        json_n = count_task_allow(cfg, primary) if json_ok else None
        arch_h = arch_r = None
        if arch_text is not None:
            wl = get_whitelist_count(arch_text, primary)
            if wl is not None:
                arch_h, arch_r = wl['header'], wl['rows']
        plug_n = count_routing_plugin(ts_text, primary) if ts_text is not None else None
        ok = (json_n is not None and json_n == exp
              and arch_h is not None and arch_h == exp
              and arch_r is not None and arch_r == exp)
        if plug_n is not None and plug_n != exp:
            ok = False
        plug_s = str(plug_n) if plug_n is not None else '-'
        rep.add('COUNT', '', 'PASS' if ok else 'FAIL',
                f'routing_{primary} json={json_n} arch_header={arch_h} '
                f'arch_rows={arch_r} plugin={plug_s} expected={exp}')
        if plug_n is None:
            rep.add('WARN', 'routing', 'WARN',
                    f'{primary} plugin anchor not parsed (skipped plugin source)')

    # 8. Summary
    if args.json:
        doc = {
            'checks': rep.checks,
            'summary': {
                'total': len(rep.checks),
                'pass': rep.pass_n,
                'fail': rep.fail_n,
                'warn': rep.warn_n,
            },
        }
        print(json.dumps(doc, indent=2, ensure_ascii=False))
    else:
        print(f'SUMMARY:checks={len(rep.checks)} pass={rep.pass_n} '
              f'fail={rep.fail_n} warn={rep.warn_n}')
        if rep.fail_n > 0:
            print(f'STATUS:FAILURES fail={rep.fail_n}')
        else:
            print('STATUS:ALL_PASS')

    sys.exit(3 if rep.fail_n > 0 else 0)


if __name__ == '__main__':
    main()
